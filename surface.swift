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

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyFile), keyEquivalent: "c")
        menu.addItem(withTitle: "Close", action: #selector(closeWindow), keyEquivalent: "w")
        return menu
    }

    @objc func copyFile() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }

    @objc func closeWindow() {
        NSApp.terminate(nil)
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

// MARK: - Instance Stacking

/// Coordinates window positions across multiple surface instances using PID files in /tmp.
class InstanceStack {
    static let stackDir = "/tmp/surface-stack"
    private let pidFile: String

    init() {
        let dir = InstanceStack.stackDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        pidFile = "\(dir)/\(ProcessInfo.processInfo.processIdentifier)"
    }

    /// Returns the stack index (0-based) for this instance after cleaning up stale entries.
    func claim() -> Int {
        let fm = FileManager.default
        let dir = InstanceStack.stackDir

        // Clean up stale PID files from dead processes
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        var liveCount = 0
        for entry in entries {
            if let pid = Int32(entry), kill(pid, 0) != 0 {
                try? fm.removeItem(atPath: "\(dir)/\(entry)")
            } else {
                liveCount += 1
            }
        }

        // Register this instance
        fm.createFile(atPath: pidFile, contents: nil)

        return liveCount
    }

    func release() {
        try? FileManager.default.removeItem(atPath: pidFile)
    }
}

// MARK: - Window Setup

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let fileURL: URL
    let timeout: TimeInterval?
    let instanceStack = InstanceStack()
    var timeoutTimer: Timer?

    init(fileURL: URL, timeout: TimeInterval?) {
        self.fileURL = fileURL
        self.timeout = timeout
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

        // Determine stack position and offset vertically
        let titleBarHeight: CGFloat = 22
        let stackIndex = instanceStack.claim()
        let stackOffset = CGFloat(stackIndex) * (windowHeight + titleBarHeight + 8)

        // Position bottom-right of screen, stacked upward
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.maxX - windowWidth - 20,
            y: screenFrame.minY + 20 + stackOffset
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

        // Start auto-dismiss timer if timeout was specified
        if let timeout = timeout, timeout > 0 {
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timeoutTimer?.invalidate()
        instanceStack.release()
    }
}

// MARK: - Argument Parsing

let args = CommandLine.arguments
let isForeground = args.contains("--foreground")

// Parse --timeout value
var timeout: TimeInterval? = nil
if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
   let seconds = TimeInterval(args[idx + 1]) {
    timeout = seconds
}

// Collect positional arguments (skip flags and their values)
var positional: [String] = []
var i = 1
while i < args.count {
    if args[i] == "--foreground" {
        i += 1
    } else if args[i] == "--timeout" {
        i += 2  // skip flag and its value
    } else {
        positional.append(args[i])
        i += 1
    }
}

guard !positional.isEmpty else {
    fputs("Usage: surface <file>... [--timeout <seconds>]\n", stderr)
    exit(1)
}

let cwd = FileManager.default.currentDirectoryPath
var urls: [URL] = []
for path in positional {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else {
        url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        fputs("File not found: \(url.path)\n", stderr)
        exit(1)
    }
    urls.append(url)
}

// If launched with --foreground, run the app directly (single file)
if isForeground {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(fileURL: urls[0], timeout: timeout)
    app.delegate = delegate
    app.run()
} else {
    // Spawn a background process per file
    let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
    for url in urls {
        var spawnArgs = ["surface", url.path, "--foreground"]
        if let timeout = timeout {
            spawnArgs += ["--timeout", String(Int(timeout))]
        }
        var cArgs = spawnArgs.map { strdup($0) } + [nil]
        var pid: pid_t = 0
        let status = posix_spawn(&pid, execPath, nil, nil, &cArgs, nil)
        cArgs.compactMap { $0 }.forEach { free($0) }
        if status != 0 {
            fputs("Failed to launch background process for: \(url.path)\n", stderr)
        }
    }
    exit(0)
}
