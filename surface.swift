import Cocoa
import QuickLookThumbnailing

// MARK: - Draggable Image View

class DraggableFileView: NSView, NSDraggingSource {
    let fileURL: URL
    var thumbnail: NSImage?

    init(fileURL: URL, frame: NSRect) {
        self.fileURL = fileURL
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL])
        loadThumbnail()
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadThumbnail() {
        let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { [weak self] rep, _, error in
            DispatchQueue.main.async {
                if let cgImage = rep?.cgImage {
                    self?.thumbnail = NSImage(cgImage: cgImage, size: self?.bounds.size ?? .zero)
                } else {
                    // Fallback to file icon
                    self?.thumbnail = NSWorkspace.shared.icon(forFile: self?.fileURL.path ?? "")
                }
                self?.needsDisplay = true
            }
        }
        // Show icon immediately while thumbnail loads
        thumbnail = NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        if let img = thumbnail {
            let aspect = img.size.width / img.size.height
            var drawRect = bounds.insetBy(dx: 8, dy: 8)
            if aspect > 1 {
                let h = drawRect.width / aspect
                drawRect.origin.y += (drawRect.height - h) / 2
                drawRect.size.height = h
            } else {
                let w = drawRect.height * aspect
                drawRect.origin.x += (drawRect.width - w) / 2
                drawRect.size.width = w
            }
            img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    // MARK: - Open on double-click

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NSWorkspace.shared.open(fileURL)
        }
    }

    // MARK: - Drag Source

    override func mouseDragged(with event: NSEvent) {
        // Use NSURL as the pasteboard writer — browsers recognize this as a file drop
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let img = thumbnail ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        draggingItem.setDraggingFrame(bounds, contents: img)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .outsideApplication ? .copy : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            // Successfully dragged — close the window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Filename Label

class FilenameLabel: NSTextField {
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.isEditable = false
        self.isBordered = false
        self.drawsBackground = false
        self.alignment = .center
        self.lineBreakMode = .byTruncatingMiddle
        self.maximumNumberOfLines = 1
        self.font = NSFont.systemFont(ofSize: 11)
        self.textColor = .secondaryLabelColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Window Setup

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let thumbSize: CGFloat = 160
        let labelHeight: CGFloat = 24
        let padding: CGFloat = 4
        let windowWidth = thumbSize + 16
        let windowHeight = thumbSize + labelHeight + padding

        // Position bottom-right of screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.maxX - windowWidth - 20,
            y: screenFrame.minY + 20
        )

        window = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight)),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))

        let dragView = DraggableFileView(
            fileURL: fileURL,
            frame: NSRect(x: 0, y: labelHeight + padding, width: windowWidth, height: thumbSize)
        )
        contentView.addSubview(dragView)

        let label = FilenameLabel(frame: NSRect(x: 4, y: 0, width: windowWidth - 8, height: labelHeight))
        label.stringValue = fileURL.lastPathComponent
        contentView.addSubview(label)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        // Animate in from bottom
        let finalFrame = window.frame
        var startFrame = finalFrame
        startFrame.origin.y -= 40
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
    }
}

// MARK: - Main

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: surface <file>\n", stderr)
    exit(1)
}

let path = CommandLine.arguments[1]
let url: URL
if path.hasPrefix("/") {
    url = URL(fileURLWithPath: path)
} else {
    // Resolve relative path
    let cwd = FileManager.default.currentDirectoryPath
    url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
}

guard FileManager.default.fileExists(atPath: url.path) else {
    fputs("File not found: \(url.path)\n", stderr)
    exit(1)
}

// If launched with --foreground, run the app directly
if CommandLine.arguments.contains("--foreground") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(fileURL: url)
    app.delegate = delegate
    app.run()
} else {
    // Re-launch ourselves in the background with --foreground
    let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let args = ["surface", url.path, "--foreground"]
    var cArgs = args.map { strdup($0) } + [nil]
    var pid: pid_t = 0
    let status = posix_spawn(&pid, execPath, nil, nil, &cArgs, nil)
    cArgs.compactMap { $0 }.forEach { free($0) }
    if status != 0 {
        fputs("Failed to launch background process\n", stderr)
        exit(1)
    }
    exit(0)
}
