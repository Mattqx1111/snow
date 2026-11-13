import AppKit

/// A calm, non-activating floating pill shown at the top of the screen while Sculpt Mode is active,
/// giving clear instructions and one-click Done / Clear Snowmen actions so the user can never feel stuck.
final class SculptHUD {
    var onDone: () -> Void = {}
    var onClearSnowmen: () -> Void = {}

    private var panel: NSPanel?
    private var hintLabel: NSTextField?
    private var clearButton: NSButton?

    func show(snowmanCount: Int) {
        if panel == nil {
            buildPanel()
        }
        update(snowmanCount: snowmanCount)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func update(snowmanCount: Int) {
        clearButton?.isHidden = snowmanCount == 0
        panel?.layoutSubtreeIfNeeded()
        if let panel, let content = panel.contentView {
            let fitting = content.fittingSize
            var frame = panel.frame
            let dx = (frame.width - fitting.width) / 2
            frame.origin.x += dx
            frame.size = fitting
            panel.setFrame(frame, display: true)
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 420, height: 38)
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 14
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: tr("sculpt.hint"))
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel = label

        let clear = NSButton(title: tr("sculpt.clear"), target: self, action: #selector(clearPressed))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        clear.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        clearButton = clear

        let done = NSButton(title: tr("sculpt.done"), target: self, action: #selector(donePressed))
        done.bezelStyle = .rounded
        done.controlSize = .small
        done.keyEquivalent = "\u{1b}"
        done.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let stack = NSStackView(views: [icon, label, clear, done])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        self.panel = panel
    }

    @objc private func clearPressed() {
        onClearSnowmen()
    }

    @objc private func donePressed() {
        onDone()
    }
}
