import CoreGraphics

/// Pure geometry. Kept free of AX and AppKit so it can be reasoned about (and unit-tested)
/// without a window server.
///
/// The central problem this file solves: **apps clamp their own size**. AX provides no way to ask
/// for a window's minimum, so a layout that divides the screen evenly can hand a window a pane
/// smaller than it accepts; the app then keeps its larger size and overlaps its neighbour.
/// Everything here is written so that (a) known minimums are respected, and (b) when the minimums
/// cannot all fit, the screen is divided evenly instead of piling panes on top of one another.
enum Layout {

    /// Minimum pane size assumed for a window whose real minimum has never been observed.
    ///
    /// It used to be 1 pt, which meant an over-subscribed desktop could legally hand a window a
    /// 1-pixel sliver (kitty did exactly that). A guess large enough to stay grabbable keeps the
    /// layout honest: if the minimums can't fit, `slice` divides evenly instead.
    static let unknownMinimum: CGFloat = 44

    /// Divide `total` among weighted slots, respecting per-slot minimums *and* maximums.
    ///
    /// Minimums are pinned first: slots that cannot get their minimum at the proportional share are
    /// pinned to it, and the remaining space is redistributed among the rest. If the minimums alone
    /// exceed `total`, an even split is used instead: panes stay fully on-screen.
    ///
    /// Maximums are the mirror image, and they matter just as much: an app that refuses to grow
    /// (System Settings caps itself at 757 pt) keeps its smaller frame, so the space the layout
    /// handed it is never used and shows up as a gap at the trailing edge. A slot at its maximum is
    /// pinned there and the surplus goes to the slots that can still grow.
    static func slice(weights: [CGFloat],
                      minimums: [CGFloat],
                      maximums: [CGFloat] = [],
                      total: CGFloat) -> [CGFloat] {
        let n = weights.count
        guard n > 0 else { return [] }
        let safeWeights = weights.map { max($0, 0.05) }
        var safeMins = minimums.count == n ? minimums.map { max($0, 1) } : Array(repeating: 1, count: n)
        // Maximums are the mirror of minimums. A recorded minimum can be wrong once a ceiling is
        // known: System Settings was once seen to keep 757 pt in a smaller cell, which got learned
        // as its minimum, and a minimum of 757 with a ceiling of 757 silently cancels the ceiling
        // (nothing is "above" 757, so the slot looked unconstrained and took 840 again). The app
        // demonstrably accepts its own maximum, so that is the floor whenever both are known.
        var safeMaxes = [CGFloat](repeating: .greatestFiniteMagnitude, count: n)
        if maximums.count == n {
            for i in 0..<n where maximums[i] > 1 {
                safeMaxes[i] = maximums[i]
                safeMins[i] = min(safeMins[i], maximums[i])
            }
        }

        var result = [CGFloat](repeating: 0, count: n)
        var pending = Array(0..<n)
        var space = total
        var weightLeft = safeWeights.reduce(0, +)

        /// Pin every slot in `pending` whose proportional share falls below its minimum.
        func pinMinimums() {
            var pinned = true
            while pinned && !pending.isEmpty {
                pinned = false
                for i in pending where weightLeft > 0 {
                    let share = space * safeWeights[i] / weightLeft
                    if share < safeMins[i] {
                        result[i] = safeMins[i]
                        space -= safeMins[i]
                        weightLeft -= safeWeights[i]
                        pending.removeAll { $0 == i }
                        pinned = true
                        break
                    }
                }
            }
        }

        pinMinimums()

        // Pin slots that cannot grow to their share, then re-check the minimums: taking space away
        // from the flexible slots can push one of them under its own minimum.
        var capped = true
        while capped && pending.count > 0 && weightLeft > 0 {
            capped = false
            let scale = space / weightLeft
            for i in pending where safeWeights[i] * scale > safeMaxes[i] + 0.5 {
                result[i] = safeMaxes[i]
                space -= safeMaxes[i]
                weightLeft -= safeWeights[i]
                pending.removeAll { $0 == i }
                capped = true
                break
            }
            if capped { pinMinimums() }
        }

        if !pending.isEmpty, weightLeft > 0 {
            let scale = space / weightLeft
            for i in pending { result[i] = max(min(safeWeights[i] * scale, safeMaxes[i]), 1) }
        } else {
            for i in pending { result[i] = safeMins[i] }
        }

        // Over-subscribed: the minimums can't all be honoured. Divide evenly so every pane stays
        // visible instead of the last ones falling off the bottom of the screen.
        let used = result.reduce(0, +)
        if total > 0, used > total + 0.5 {
            let even = total / CGFloat(n)
            for i in 0..<n { result[i] = even }
        }
        return result
    }

    /// Slice `rect` into one frame per window along `orientation`, honouring minimum sizes.
    ///
    /// Positions accumulate from the leading edge, so panes never share pixels. The last pane takes
    /// the remainder when everything fits, so rounding leaves no seam at the trailing edge.
    static func frames(weights: [CGFloat],
                       minimums: [CGFloat],
                       maximums: [CGFloat] = [],
                       in rect: CGRect,
                       orientation: Orientation) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        var lengths = slice(weights: weights, minimums: minimums, maximums: maximums,
                            total: orientation == .horizontal ? rect.width : rect.height)
        let available = orientation == .horizontal ? rect.width : rect.height
        let used = lengths.reduce(0, +)
        // Absorb rounding, but never past a slot's own ceiling: giving the surplus to a capped
        // window is what the app will refuse, and the seam reappears.
        if used <= available, !lengths.isEmpty {
            var surplus = available - used
            for i in lengths.indices.reversed() where surplus > 0.01 {
                let ceiling = maximums.count == lengths.count ? maximums[i] : .greatestFiniteMagnitude
                let room = max(0, ceiling - lengths[i])
                let take = min(room, surplus)
                lengths[i] += take
                surplus -= take
            }
        }

        var out: [CGRect] = []
        out.reserveCapacity(lengths.count)
        var offset: CGFloat = 0
        for length in lengths {
            if orientation == .horizontal {
                out.append(CGRect(x: rect.minX + offset, y: rect.minY, width: length, height: rect.height))
            } else {
                out.append(CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: length))
            }
            offset += length
        }
        return out
    }

    /// Grid for 3+ windows: rows of columns, each axis allocated with `slice`.
    ///
    /// A single row thin enough for 7 windows puts every pane below the minimum width apps accept,
    /// so a grid keeps panes usable while still partitioning the screen.
    static func grid(weights: [CGFloat],
                     minWidths: [CGFloat],
                     minHeights: [CGFloat],
                     in rect: CGRect,
                     columns: Int? = nil) -> [CGRect] {
        let n = weights.count
        guard n > 0 else { return [] }
        if n == 1 { return [rect] }

        let cols = max(1, min(n, columns ?? preferredColumns(for: n)))
        let rows = Int(ceil(Double(n) / Double(cols)))

        // Row heights first, each row sized by the tallest minimum among its windows.
        var rowMinHeights = [CGFloat](repeating: 1, count: rows)
        for row in 0..<rows {
            let start = row * cols
            let end = min(n, start + cols)
            guard start < end else { continue }
            rowMinHeights[row] = (start..<end)
                .map { minHeights.indices.contains($0) ? minHeights[$0] : 1 }
                .max() ?? 1
        }
        var rowLengths = slice(weights: Array(repeating: 1, count: rows),
                               minimums: rowMinHeights,
                               total: rect.height)
        let rowUsed = rowLengths.reduce(0, +)
        if rowUsed <= rect.height, !rowLengths.isEmpty {
            rowLengths[rowLengths.count - 1] += rect.height - rowUsed
        }

        var out: [CGRect] = []
        out.reserveCapacity(n)
        var y = rect.minY
        for row in 0..<rows {
            let start = row * cols
            let end = min(n, start + cols)
            guard start < end else { continue }
            let count = end - start

            var colWidths = slice(weights: Array(weights[start..<end]),
                                  minimums: Array(minWidths[start..<end]),
                                  total: rect.width)
            let colUsed = colWidths.reduce(0, +)
            if colUsed <= rect.width, !colWidths.isEmpty {
                colWidths[colWidths.count - 1] += rect.width - colUsed
            }

            var x = rect.minX
            for i in 0..<count {
                out.append(CGRect(x: x, y: y, width: colWidths[i], height: rowLengths[row]))
                x += colWidths[i]
            }
            y += rowLengths[row]
        }
        return out
    }

    /// Square-ish column count, biased toward columns because screens are wider than tall.
    static func preferredColumns(for n: Int) -> Int {
        guard n > 1 else { return 1 }
        return max(1, Int((Double(n).squareRoot() * 1.15).rounded(.up)))
    }

    /// Neighbour index in a direction, for focus and move.
    static func neighbour(from index: Int, count: Int, direction: Direction,
                          orientation: Orientation) -> Int? {
        guard count > 0 else { return nil }
        let forward: Bool
        switch direction {
        case .left, .up:  forward = false
        case .right, .down: forward = true
        }
        let candidate = forward ? index + 1 : index - 1
        return (candidate >= 0 && candidate < count) ? candidate : nil
    }
}

enum Direction {
    case left, right, up, down
}
