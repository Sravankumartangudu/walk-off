// Camera check: a live, mirrored preview with a box on each face Walk Off sees.
// Green boxes count; grey ones are too far away. Also the welcome window on first launch.
import AppKit

enum AppInfo {
    static let name = "Walk Off"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static let repo = URL(string: "https://github.com/Sravankumartangudu/walk-off")!
}

final class CheckWindow: NSObject, NSWindowDelegate {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isOpen = false

    private var window: NSWindow?
    private let preview = NSImageView()
    private let verdict = NSTextField(labelWithString: "Waiting for the camera…")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let state = NSTextField(labelWithString: "")

    func show() {
        if window == nil { build() }
        isOpen = true
        onOpen?()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        preview.image = nil
        verdict.stringValue = "Waiting for the camera…"
        onClose?()
    }

    func update(faces: [SeenFace], image: CGImage?, minHeight: CGFloat, status: String) {
        guard isOpen else { return }
        state.stringValue = status
        let counted = faces.filter { $0.box.height >= minHeight }.count
        if counted > 0 {
            verdict.stringValue = "✓ I can see you"
            verdict.textColor = .systemGreen
        } else if !faces.isEmpty {
            verdict.stringValue = "Too far away to count"
            verdict.textColor = .systemOrange
        } else {
            verdict.stringValue = "No face in view"
            verdict.textColor = .secondaryLabelColor
        }
        guard let image else { return }
        preview.image = Self.draw(image, faces: faces, minHeight: minHeight)
    }

    func showProblem(_ text: String) {
        guard isOpen else { return }
        verdict.stringValue = "⚠️ \(text)"
        verdict.textColor = .systemOrange
    }

    private static func draw(_ cg: CGImage, faces: [SeenFace], minHeight: CGFloat) -> NSImage {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Mirror it, like a mirror (and like FaceTime), so moving left moves left.
            ctx.translateBy(x: w, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(cg, in: rect)
            for f in faces {
                let r = CGRect(x: f.box.minX * w, y: f.box.minY * h, width: f.box.width * w, height: f.box.height * h)
                let counts = f.box.height >= minHeight
                ctx.setStrokeColor((counts ? NSColor.systemGreen : NSColor.systemGray).cgColor)
                ctx.setLineWidth(counts ? 5 : 3)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil))
                ctx.strokePath()
            }
            return true
        }
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "\(AppInfo.name) — Camera check"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let title = NSTextField(labelWithString: "👀 \(AppInfo.name)")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let intro = NSTextField(wrappingLabelWithString:
            "Locks your Mac when you walk away, and wakes the screen when you come back so Touch ID or your " +
            "Apple Watch can unlock it. The camera only turns on after you stop typing for a while. " +
            "Pictures stay in memory: nothing is saved or sent.")
        intro.textColor = .secondaryLabelColor

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 12
        preview.layer?.masksToBounds = true
        preview.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 330).isActive = true

        verdict.font = .systemFont(ofSize: 17, weight: .semibold)
        detail.stringValue = "Green box = a face that counts. Grey box = too far away (change it under 👀 › Faces that count)."
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        state.textColor = .tertiaryLabelColor
        state.font = .systemFont(ofSize: 11)

        let tip = NSTextField(wrappingLabelWithString:
            "Tip: macOS doesn't let apps unlock the Mac, and the camera can't do Face ID's 3D check, so Walk Off " +
            "never unlocks it. For a hands-free unlock, turn on Apple Watch unlock under Touch ID & Password: " +
            "when Walk Off wakes the screen, your watch unlocks it.")
        tip.font = .systemFont(ofSize: 12)

        let settings = NSButton(title: "Open Touch ID & Password", target: self, action: #selector(openTouchID))
        let done = NSButton(title: "Done", target: self, action: #selector(closeTapped))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [settings, NSView(), done])
        buttons.distribution = .fill

        let stack = NSStackView(views: [title, intro, preview, verdict, detail, tip, state, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        stack.setCustomSpacing(16, after: intro)
        stack.setCustomSpacing(14, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [intro, preview, detail, tip, buttons] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 560),
        ])
        w.contentView = content
        w.center()
        window = w
    }

    @objc private func openTouchID() { MacScreen.openTouchIDSettings() }
    @objc private func closeTapped() { close() }
}
