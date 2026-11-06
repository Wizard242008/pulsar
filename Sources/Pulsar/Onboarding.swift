import AppKit

// First-run onboarding and the "what's new" sheet.
//
// The failure this replaces: a new user launches Pulsar, sees nothing happen, finds a menu item
// called "Grant Accessibility…" that opens the *top* of Privacy & Security (the old pre-Ventura
// deep link), turns the switch on, relaunches, and still gets no tiling — because the app had
// already stopped polling for the permission and never told them a relaunch was the missing step.
//
// So this window does three things the app did not do before:
//   1. states, in order, what is missing and where exactly to click;
//   2. polls the permission while it is open, so turning the switch on is acknowledged live;
//   3. offers the relaunch itself, because a running process cannot pick up a TCC grant.

extension Controller {

    // MARK: - Permission helpers

    /// The modern deep link. `com.apple.preference.security?Privacy_Accessibility` (the Big Sur
    /// spelling) now lands on the top level of Privacy & Security on macOS 13+, which is exactly the
    /// "it only took me to one spot" complaint.
    private static let accessibilityPane =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    private static let legacyAccessibilityPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    @objc func openAccessibilityPane() {
        for raw in [Self.accessibilityPane, Self.legacyAccessibilityPane] {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        // Both schemes refused: at least put the user on the right page by hand.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// A running process keeps the Accessibility answer it started with, so a freshly granted
    /// permission needs a relaunch before tiling can begin.
    @objc func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        task.waitUntilExit()
        NSApp.terminate(nil)
    }

    // MARK: - Onboarding window

    /// Shown once, on the very first launch. `force` is for the menu's "Getting Started…" item and
    /// the button in Settings; it never re-arms the automatic first-run behaviour.
    func showOnboarding(force: Bool = false) {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if !force, UserDefaults.standard.bool(forKey: "onboardingCompleted") { return }

        let width: CGFloat = 560
        let height: CGFloat = 470
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to Pulsar"
        window.isReleasedWhenClosed = false
        window.contentView = NSView()

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])

        let margin: CGFloat = 26
        let title = NSTextField(labelWithString: "Welcome to Pulsar")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            "A tiling window manager for macOS. Windows snap into panes instead of stacking on top of each other, and each letter of the alphabet is its own workspace.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = width - margin * 2

        // The body changes per step; everything above and below it stays put.
        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false

        let dots = NSTextField(labelWithString: "")
        dots.font = .systemFont(ofSize: 11)
        dots.textColor = .tertiaryLabelColor

        let back = NSButton(title: "Back", target: self, action: #selector(rewindOnboarding))
        back.bezelStyle = .rounded
        let next = NSButton(title: "Next", target: self, action: #selector(advanceOnboarding))
        next.bezelStyle = .rounded
        next.keyEquivalent = "\r"
        let skip = NSButton(title: "Skip", target: self, action: #selector(skipOnboardingTutorial))
        skip.bezelStyle = .inline
        skip.isBordered = false

        for view in [title, subtitle, body, dots, back, next, skip] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),

            body.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            body.bottomAnchor.constraint(equalTo: dots.topAnchor, constant: -14),

            dots.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            dots.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),

            skip.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            skip.centerYAnchor.constraint(equalTo: next.centerYAnchor),
            next.trailingAnchor.constraint(equalTo: skip.leadingAnchor, constant: -12),
            next.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            back.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: -8),
            back.centerYAnchor.constraint(equalTo: next.centerYAnchor),
        ])

        onboardingWindow = window
        onboardingBody = body
        onboardingNext = next
        onboardingBack = back
        onboardingSkip = skip
        onboardingDots = dots
        onboardingStep = 0
        renderOnboardingStep()

        // Live permission state: the switch in System Settings is one click away, and the whole
        // point is that it be acknowledged without a relaunch of the tutorial.
        onboardingTimer?.invalidate()
        onboardingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.onboardingWindow?.isVisible == true else { return }
            if self.onboardingStep == 1 { self.renderOnboardingStep() }
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func advanceOnboarding() {
        if onboardingStep >= Self.onboardingSteps - 1 { finishOnboarding(); return }
        onboardingStep += 1
        renderOnboardingStep()
    }

    @objc func rewindOnboarding() {
        onboardingStep = max(0, onboardingStep - 1)
        renderOnboardingStep()
    }

    @objc func skipOnboardingTutorial() { finishOnboarding() }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onboardingTimer?.invalidate()
        onboardingTimer = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        log("onboarding: completed")
        // Tiling only starts once the permission exists; a fresh grant needs the relaunch below.
        if AXIsProcessTrusted() { refresh() }
    }

    static let onboardingSteps = 4

    private func renderOnboardingStep() {
        guard let body = onboardingBody, let next = onboardingNext,
              let back = onboardingBack, let dots = onboardingDots else { return }
        body.subviews.forEach { $0.removeFromSuperview() }
        back.isHidden = onboardingStep == 0
        next.title = onboardingStep == Self.onboardingSteps - 1 ? "Start" : "Next"
        next.isEnabled = true
        dots.stringValue = "Step \(onboardingStep + 1) of \(Self.onboardingSteps)"
        onboardingSkip?.isHidden = onboardingStep == Self.onboardingSteps - 1

        let trusted = AXIsProcessTrusted()
        var rows: [NSView] = []

        switch onboardingStep {
        case 0:
            rows.append(paragraph("Pulsar runs from the menu bar and does three things:"))
            rows.append(bullet("Every window on a workspace is tiled to fill the screen — nothing overlaps."))
            rows.append(bullet("Each letter is a workspace. ⌥a, ⌥b, ⌥t… switch between them instantly."))
            rows.append(bullet("Windows stay where you put them, even across sleep and updates."))
            rows.append(paragraph("Next: one permission, then the keys."))
        case 1:
            let status = NSView()
            let dot = NSTextField(labelWithString: trusted ? "✓  Accessibility is granted" : "●  Accessibility is not granted yet")
            dot.font = .systemFont(ofSize: 13, weight: .medium)
            dot.textColor = trusted ? .systemGreen : .systemOrange
            dot.translatesAutoresizingMaskIntoConstraints = false
            status.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: status.leadingAnchor),
                dot.topAnchor.constraint(equalTo: status.topAnchor),
                dot.bottomAnchor.constraint(equalTo: status.bottomAnchor),
            ])
            rows.append(status)
            rows.append(spacer(8))

            if trusted {
                rows.append(paragraph("macOS applies a new permission only to processes started after it was granted. If windows are not tiling yet, relaunch Pulsar — this button does it and brings you back."))
                let relaunch = NSButton(title: "Relaunch Pulsar", target: self, action: #selector(relaunchApp))
                relaunch.bezelStyle = .rounded
                rows.append(relaunch)
            } else {
                rows.append(paragraph("Open System Settings, find Pulsar in the list, and switch it on:"))
                rows.append(numbered("1.  Click the button below. It opens Privacy & Security → Accessibility directly."))
                rows.append(numbered("2.  If Pulsar is not in the list, choose + and pick /Applications/Pulsar.app."))
                rows.append(numbered("3.  Turn the switch next to Pulsar on."))
                rows.append(numbered("4.  Come back here — this line turns green by itself — then relaunch when Pulsar asks."))
                rows.append(spacer(6))
                let open = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibilityPane))
                open.bezelStyle = .rounded
                rows.append(open)
                next.isEnabled = false     // cannot tile without it; skipping stays available
            }
            rows.append(paragraph("Pulsar needs no Screen Recording, no Full Disk Access and no admin password. Accessibility is the only one."))
        case 2:
            rows.append(paragraph("Hold ⌥ (Option) for everything. Letters are workspaces; the same letters with Shift move windows."))
            let grid = NSGridView(views: [
                [keyCell("⌥ H J K L"), labelCell("focus left / down / up / right")],
                [keyCell("⌥ ⇧ H J K L"), labelCell("move the focused window that way")],
                [keyCell("⌥ A … Z"), labelCell("jump to a workspace")],
                [keyCell("⌥ ⇧ A … Z"), labelCell("send the focused window there")],
                [keyCell("⌥ − / ⌥ ="), labelCell("shrink / grow its share of the screen")],
                [keyCell("⌥ /"), labelCell("stack the workspace vertically or side by side")],
            ])
            grid.rowSpacing = 6
            grid.columnSpacing = 14
            grid.column(at: 0).xPlacement = .trailing
            rows.append(grid)
            rows.append(spacer(10))
            rows.append(paragraph("Workspaces are independent: each keeps its own windows, and switching is instant because other desktops' windows are simply parked off-screen."))
        default:
            rows.append(paragraph("That's it — Pulsar is running in the menu bar (the star glyph), and your windows are already tiled."))
            rows.append(bullet("Reopen this guide any time from the menu: Getting Started…"))
            rows.append(bullet("Change the modifier, restore behaviour or turn off update notes in Settings… (⌘,)."))
            rows.append(bullet("If something looks wrong, Settings → Show Log, or check the menu's status line."))
            if !trusted {
                rows.append(paragraph("Accessibility is still off, so tiling will not start until it is granted."))
            }
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            stack.topAnchor.constraint(equalTo: body.topAnchor),
        ])
    }

    // Small builders, so the step bodies read like prose rather than layout code.
    private func paragraph(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12.5)
        label.preferredMaxLayoutWidth = 508
        return label
    }
    private func bullet(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: "•  " + text)
        label.font = .systemFont(ofSize: 12.5)
        label.preferredMaxLayoutWidth = 508
        return label
    }
    private func numbered(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 508
        return label
    }
    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
    private func keyCell(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        return label
    }
    private func labelCell(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }
}
