import AppKit

// "What's new" after an update.
//
// The rule the user asked for: show it when the version changes, never on an ordinary launch, and
// let it be switched off in Settings. The notes come from a bundled CHANGELOG.md rather than the
// network, so the sheet works offline and never shows an empty box because GitHub was slow.

extension Controller {

    /// Version-specific bullets, straight out of the bundled changelog.
    static func releaseNotes(for version: String) -> [String] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var picking = false
        var notes: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let heading = line.replacingOccurrences(of: "## ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                picking = (heading == version)
                continue
            }
            if picking, line.hasPrefix("- ") {
                notes.append(String(line.dropFirst(2)))
            }
        }
        return notes
    }

    /// Called once at launch. Marks the version as seen either way, so the sheet is never repeated.
    func announceIfUpdated() {
        let defaults = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let previous = defaults.string(forKey: "lastRunVersion")

        // First ever launch: the tutorial covers everything, so don't stack two windows on top of it.
        if previous == nil {
            defaults.set(version, forKey: "lastRunVersion")
            return
        }
        defaults.set(version, forKey: "lastRunVersion")
        guard previous != version else { return }
        guard defaults.object(forKey: "showWhatsNew") == nil || defaults.bool(forKey: "showWhatsNew") else { return }

        let notes = Self.releaseNotes(for: version)
        guard !notes.isEmpty else { return }
        showWhatsNew(version: version, notes: notes)
    }

    func showWhatsNew(version: String, notes: [String]) {
        if let existing = whatsNewWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let width: CGFloat = 470
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "What's new"
        window.isReleasedWhenClosed = false

        let root = NSView()
        window.contentView = root
        let margin: CGFloat = 22

        let title = NSTextField(labelWithString: "Pulsar \(version)")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "What changed in this version:")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = width - margin * 2

        var rows: [NSView] = []
        for note in notes {
            let label = NSTextField(wrappingLabelWithString: "•  " + note)
            label.font = .systemFont(ofSize: 12)
            label.preferredMaxLayoutWidth = width - margin * 2 - 12
            rows.append(label)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let dontShow = NSButton(checkboxWithTitle: "Don't show this after updates", target: self,
                                action: #selector(whatsNewToggle(_:)))
        dontShow.state = .off

        let ok = NSButton(title: "Done", target: self, action: #selector(closeWhatsNew))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"

        for view in [title, subtitle, stack, dontShow, ok] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),

            stack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),

            dontShow.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 18),
            dontShow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            dontShow.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -margin - 34),

            ok.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            ok.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
        ])

        let fitting = root.fittingSize
        window.setContentSize(NSSize(width: width, height: max(240, fitting.height)))
        window.center()
        whatsNewWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func whatsNewToggle(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .off, forKey: "showWhatsNew")
    }

    @objc func closeWhatsNew() {
        whatsNewWindow?.close()
        whatsNewWindow = nil
    }
}
