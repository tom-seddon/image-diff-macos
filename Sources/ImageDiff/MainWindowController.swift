import AppKit
import ImageDiffCore
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private static let minZoom: CGFloat = 0.02, maxZoom: CGFloat = 64
    private static let appTitle = "Image Diff \(AppVersion.current)"

    // ------------------------------------------------------------ Controls

    private let leftField = PathField()
    private let rightField = PathField()
    private let modeControl = NSSegmentedControl(labels: ["Difference", "Flip"], trackingMode: .selectOne,
                                                 target: nil, action: nil)
    private let flipButton = NSButton(title: "Show right", target: nil, action: nil)
    private let toleranceSlider = NSSlider(value: 0, minValue: 0, maxValue: 255, target: nil, action: nil)
    private let toleranceLabel = NSTextField(labelWithString: "0")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let saveButton = NSButton(title: "Save Difference…", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "Choose two images, or drop them onto this window.")
    private let pixelLabel = NSTextField(labelWithString: "")
    private let scrollView = ZoomScrollView()
    private let canvas = CanvasView()
    private let flipBadge = BadgeView()
    private let emptyHint = PassthroughLabel(
        labelWithString: "Drop two images here, or choose them above.\nYou can also run: imgdiff left.png right.png --show")

    // ------------------------------------------------------------ State

    private var left: PixelImage?
    private var right: PixelImage?
    private var highlight: PixelImage?
    private var diff: DiffResult?
    private var leftName = "", rightName = ""
    private var pendingOutputPath: String?

    private var mode: ViewMode = .difference
    private var showingRight = false
    private var fit = true

    private var loadGeneration = 0, diffGeneration = 0
    private var keyMonitor: Any?

    init(options: CommandLineOptions) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 400)
        window.title = Self.appTitle
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }
        super.init(window: window)
        window.delegate = self

        buildLayout(in: window)

        leftField.stringValue = options.leftPath ?? ""
        rightField.stringValue = options.rightPath ?? ""
        toleranceSlider.integerValue = options.tolerance
        toleranceLabel.stringValue = String(options.tolerance)
        pendingOutputPath = options.outputPath
        setMode(options.mode)
        updateZoomLabel()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }

        if hasBothPaths {
            window.initialFirstResponder = canvas
            DispatchQueue.main.async { self.compare(nil) }
        } else if pendingOutputPath != nil {
            showError("--output needs two images to compare.")
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // ------------------------------------------------------------ Layout

    private func buildLayout(in window: NSWindow) {
        let content = DropContentView()
        window.contentView = content
        content.onDrop = { [weak self] files, point in self?.windowDrop(files, at: point) }

        // Image selection
        for (field, side) in [(leftField, "left (original)"), (rightField, "right (changed)")] {
            field.placeholderString = "Path of the \(side) image"
            field.toolTip = "Path of the \(side) image. Press Return to compare."
            field.target = self
            field.action = #selector(pathEntered(_:))
            field.lineBreakMode = .byTruncatingHead
            field.cell?.usesSingleLineMode = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        leftField.onDrop = { [weak self] files in self?.fieldDrop(files, onLeft: true) }
        rightField.onDrop = { [weak self] files in self?.fieldDrop(files, onLeft: false) }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Left:"), leftField, button("Choose…", #selector(chooseLeft(_:)))],
            [NSTextField(labelWithString: "Right:"), rightField, button("Choose…", #selector(chooseRight(_:)))],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.columnSpacing = 6
        grid.rowSpacing = 6

        let compareButton = button("Compare", #selector(compare(_:)))
        compareButton.keyEquivalent = ""
        compareButton.toolTip = "Load both images and compare (⌘R)"
        let swapButton = button("Swap", #selector(swap(_:)))
        swapButton.toolTip = "Swap left and right"
        let sideButtons = NSStackView(views: [compareButton, swapButton])
        sideButtons.orientation = .vertical
        sideButtons.spacing = 6
        compareButton.widthAnchor.constraint(equalTo: swapButton.widthAnchor).isActive = true

        let selection = NSStackView(views: [grid, sideButtons])
        selection.orientation = .horizontal
        selection.alignment = .centerY
        selection.spacing = 10
        selection.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        // View options
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.setToolTip("Highlight changed pixels (1)", forSegment: 0)
        modeControl.setToolTip("Show one image at a time; Space or click switches instantly (2)", forSegment: 1)

        flipButton.bezelStyle = .rounded
        flipButton.target = self
        flipButton.action = #selector(flip(_:))
        flipButton.isEnabled = false
        flipButton.toolTip = "Switch between left and right (Space, or click the image)"
        flipButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true

        toleranceSlider.target = self
        toleranceSlider.action = #selector(toleranceChanged(_:))
        toleranceSlider.isContinuous = true
        toleranceSlider.toolTip = "Ignore per-channel differences up to this amount (0-255)"
        toleranceSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        toleranceLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        toleranceLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let fitButton = button("Fit", #selector(zoomToFit(_:)))
        fitButton.toolTip = "Fit to window (⌘0)"
        let actualButton = button("100%", #selector(zoomToActualSize(_:)))
        actualButton.toolTip = "Actual size (⌘1)"
        zoomLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        zoomLabel.toolTip = "⌘ + scroll, or pinch, to zoom"

        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveDifference(_:))
        saveButton.isEnabled = false

        let options = NSStackView(views: [
            NSTextField(labelWithString: "View:"), modeControl, flipButton, divider(),
            NSTextField(labelWithString: "Tolerance:"), toleranceSlider, toleranceLabel, divider(),
            NSTextField(labelWithString: "Zoom:"), fitButton, actualButton, zoomLabel, divider(),
            saveButton,
        ])
        options.orientation = .horizontal
        options.alignment = .centerY
        options.spacing = 6
        options.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        options.setHuggingPriority(.defaultHigh, for: .vertical)

        // View
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.5, alpha: 1)
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Self.minZoom
        scrollView.maxMagnification = Self.maxZoom
        scrollView.documentView = canvas
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setContentHuggingPriority(.init(1), for: .vertical)
        scrollView.setContentCompressionResistancePriority(.init(1), for: .vertical)
        scrollView.onZoom = { [weak self] factor, point in self?.zoom(by: factor, at: point) }
        scrollView.onResize = { [weak self] in
            guard let self, self.fit else { return }
            DispatchQueue.main.async { if self.fit { self.applyFit() } }
        }
        canvas.onClick = { [weak self] in self?.flip(nil) }
        canvas.onHover = { [weak self] point in self?.updatePixelReadout(point) }

        NotificationCenter.default.addObserver(self, selector: #selector(viewScrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(pinchStarted(_:)),
                                               name: NSScrollView.willStartLiveMagnifyNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(pinchEnded(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)

        // Status
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pixelLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        pixelLabel.alignment = .right
        pixelLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let status = NSStackView(views: [summaryLabel, NSView(), pixelLabel])
        status.orientation = .horizontal
        status.spacing = 12
        status.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 5, right: 10)

        let main = NSStackView(views: [selection, separator(), options, separator(), scrollView, separator(), status])
        main.orientation = .vertical
        main.spacing = 0
        main.distribution = .fill
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        for view in main.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true
        }

        // Overlays on the view: they stay put and unscaled, and let the mouse through.
        flipBadge.translatesAutoresizingMaskIntoConstraints = false
        flipBadge.isHidden = true
        emptyHint.translatesAutoresizingMaskIntoConstraints = false
        emptyHint.textColor = .white
        emptyHint.font = .systemFont(ofSize: 16)
        emptyHint.alignment = .center
        content.addSubview(flipBadge)
        content.addSubview(emptyHint)
        NSLayoutConstraint.activate([
            flipBadge.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            flipBadge.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            emptyHint.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyHint.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let spaced = NSStackView(views: [box])
        spaced.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        return spaced
    }

    // ------------------------------------------------------------ Loading and comparing

    private var hasBothPaths: Bool {
        !unquote(leftField.stringValue).isEmpty && !unquote(rightField.stringValue).isEmpty
    }

    private func unquote(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return (trimmed as NSString).expandingTildeInPath
    }

    /// Opens files from Finder: two set both sides; one fills an empty side, or replaces the right.
    func openFiles(_ urls: [URL]) {
        let paths = urls.map(\.path)
        if paths.count >= 2 {
            leftField.stringValue = paths[0]
            rightField.stringValue = paths[1]
        } else if let path = paths.first {
            if unquote(leftField.stringValue).isEmpty {
                leftField.stringValue = path
            } else {
                rightField.stringValue = path
            }
        }
        if hasBothPaths { compare(nil) }
    }

    @objc func compare(_ sender: Any?) {
        let leftPath = unquote(leftField.stringValue), rightPath = unquote(rightField.stringValue)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            showError("Choose both a left and a right image.")
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        showStatus("Loading…")

        Task {
            let result = await Task.detached {
                Result { (try ImageFile.load(leftPath), try ImageFile.load(rightPath)) }
            }.value
            guard generation == self.loadGeneration else { return }

            let left: PixelImage, right: PixelImage
            switch result {
            case .success(let images): (left, right) = images
            case .failure(let error):
                self.showError("Could not load images: \(error)")
                return
            }

            self.left = left
            self.right = right
            let leftFile = (leftPath as NSString).lastPathComponent
            let rightFile = (rightPath as NSString).lastPathComponent
            self.leftName = "\(leftFile)  (\(left.width)×\(left.height))"
            self.rightName = "\(rightFile)  (\(right.width)×\(right.height))"

            self.canvas.leftView.image = ImageFile.cgImage(left)
            self.canvas.leftView.frame = NSRect(x: 0, y: 0, width: left.width, height: left.height)
            self.canvas.rightView.image = ImageFile.cgImage(right)
            self.canvas.rightView.frame = NSRect(x: 0, y: 0, width: right.width, height: right.height)
            self.window?.title = "\(leftFile) vs \(rightFile) - \(Self.appTitle)"
            self.window?.representedURL = URL(fileURLWithPath: leftPath)
            self.emptyHint.isHidden = true
            self.flipButton.isEnabled = true
            self.updateVisibleImage()
            if self.window?.firstResponder is NSText {
                self.window?.makeFirstResponder(self.canvas)
            }

            self.recomputeDiff()
        }
    }

    private func recomputeDiff() {
        guard let left, let right else { return }
        let tolerance = toleranceSlider.integerValue
        diffGeneration += 1
        let generation = diffGeneration
        let loaded = loadGeneration

        Task {
            let (diff, highlight) = await Task.detached { () -> (DiffResult, PixelImage) in
                // Tolerance comes from the slider, which is limited to 0-255, so this can't throw.
                let d = try! ImageComparer.compare(left, right, tolerance: tolerance)
                return (d, ImageComparer.renderHighlight(d, background: left))
            }.value
            guard generation == self.diffGeneration, loaded == self.loadGeneration else { return }

            let sizeChanged = self.diff.map { $0.width != diff.width || $0.height != diff.height } ?? true
            self.diff = diff
            self.highlight = highlight
            self.canvas.diffView.image = ImageFile.cgImage(highlight)
            let size = NSRect(x: 0, y: 0, width: diff.width, height: diff.height)
            self.canvas.diffView.frame = size
            self.canvas.frame = size
            self.canvas.needsDisplay = true
            self.saveButton.isEnabled = true
            self.showStatus(diff.summary)

            if sizeChanged && self.fit {
                self.applyFit()
            }

            if let output = self.pendingOutputPath {
                self.pendingOutputPath = nil
                self.saveHighlight(to: output)
            }
        }
    }

    private func saveHighlight(to path: String) {
        guard let highlight else { return }
        do {
            try ImageFile.savePNG(highlight, to: path)
            showStatus("\(diff?.summary ?? "") Difference image saved to \(path).")
        } catch {
            showError("Could not save the difference image: \(error)")
        }
    }

    private func showStatus(_ text: String) {
        summaryLabel.stringValue = text
        summaryLabel.textColor = .labelColor
    }

    private func showError(_ text: String) {
        summaryLabel.stringValue = text
        summaryLabel.textColor = .systemRed
    }

    // ------------------------------------------------------------ Commands

    @objc private func pathEntered(_ sender: NSTextField) {
        // Return in a path box; ending editing by clicking elsewhere also sends this, so check the key.
        guard NSApp.currentEvent?.type == .keyDown else { return }
        compare(nil)
    }

    @objc func swap(_ sender: Any?) {
        (leftField.stringValue, rightField.stringValue) = (rightField.stringValue, leftField.stringValue)
        if hasBothPaths { compare(nil) }
    }

    @objc func chooseLeft(_ sender: Any?) { choose(into: leftField, title: "Choose the left image") }

    @objc func chooseRight(_ sender: Any?) { choose(into: rightField, title: "Choose the right image") }

    private func choose(into field: NSTextField, title: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.message = title
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        let current = unquote(field.stringValue)
        if !current.isEmpty {
            let dir = URL(fileURLWithPath: current).deletingLastPathComponent()
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                panel.directoryURL = dir
            }
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            field.stringValue = url.path
            if self.hasBothPaths { self.compare(nil) }
        }
    }

    @objc func saveDifference(_ sender: Any?) {
        guard let window, highlight != nil else { return }
        let panel = NSSavePanel()
        panel.message = "Save difference image"
        panel.allowedContentTypes = [.png]
        let leftPath = unquote(leftField.stringValue)
        panel.nameFieldStringValue = URL(fileURLWithPath: leftPath).deletingPathExtension().lastPathComponent + "-diff.png"
        panel.directoryURL = URL(fileURLWithPath: leftPath).deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.saveHighlight(to: url.path)
        }
    }

    @objc private func toleranceChanged(_ sender: NSSlider) {
        toleranceLabel.stringValue = String(sender.integerValue)
        recomputeDiff()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        setMode(sender.selectedSegment == 1 ? .flip : .difference)
    }

    @objc func showDifference(_ sender: Any?) { setMode(.difference) }

    @objc func showFlip(_ sender: Any?) { setMode(.flip) }

    /// Switches between the left and right image, entering Flip view if needed.
    @objc func flip(_ sender: Any?) {
        guard left != nil, right != nil else { return }
        if mode == .flip {
            showingRight.toggle()
        } else {
            setMode(.flip)
        }
        updateVisibleImage()
    }

    private func setMode(_ mode: ViewMode) {
        self.mode = mode
        modeControl.selectedSegment = mode == .flip ? 1 : 0
        updateVisibleImage()
    }

    private func updateVisibleImage() {
        let flip = mode == .flip
        // Switching only shows and hides layers that are already decoded and laid out, so it is instant.
        canvas.diffView.isHidden = flip
        canvas.leftView.isHidden = !(flip && !showingRight)
        canvas.rightView.isHidden = !(flip && showingRight)

        let loaded = left != nil && right != nil
        flipBadge.isHidden = !(flip && loaded)
        flipBadge.label.stringValue = showingRight ? "Right: \(rightName)" : "Left: \(leftName)"
        flipButton.title = !flip ? "Flip" : showingRight ? "Show left" : "Show right"
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(saveDifference(_:)): return highlight != nil
        case #selector(flip(_:)): return left != nil && right != nil
        case #selector(showDifference(_:)):
            item.state = mode == .difference ? .on : .off
            return true
        case #selector(showFlip(_:)):
            item.state = mode == .flip ? .on : .off
            return true
        default: return true
        }
    }

    // ------------------------------------------------------------ Zoom

    @objc func zoomToFit(_ sender: Any?) { applyFit() }

    @objc func zoomToActualSize(_ sender: Any?) {
        fit = false
        setZoom(1, anchor: nil)
    }

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1.25, at: nil) }

    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.8, at: nil) }

    private func zoom(by factor: CGFloat, at point: NSPoint?) {
        guard diff != nil else { return }
        fit = false
        setZoom(scrollView.magnification * factor, anchor: point)
    }

    private func applyFit() {
        fit = true
        guard let diff, diff.width > 0, diff.height > 0 else { return }
        let size = scrollView.contentSize
        let width = size.width - 2, height = size.height - 2
        guard width > 0, height > 0 else { return }
        let zoom = min(width / CGFloat(diff.width), height / CGFloat(diff.height))
        scrollView.magnification = min(max(zoom, Self.minZoom), Self.maxZoom)
        canvas.needsDisplay = true
        updateZoomLabel()
    }

    /// Sets the zoom, keeping the canvas point `anchor` at the same place in the view (default: the middle).
    private func setZoom(_ zoom: CGFloat, anchor: NSPoint?) {
        let clip = scrollView.contentView
        let before = clip.bounds
        let at = anchor ?? NSPoint(x: before.midX, y: before.midY)
        let fx = (at.x - before.minX) / before.width, fy = (at.y - before.minY) / before.height

        scrollView.magnification = min(max(zoom, Self.minZoom), Self.maxZoom)

        let after = clip.bounds.size
        let origin = NSPoint(x: at.x - fx * after.width, y: at.y - fy * after.height)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: after)).origin)
        scrollView.reflectScrolledClipView(clip)
        canvas.needsDisplay = true
        updateZoomLabel()
    }

    @objc private func viewScrolled(_ notification: Notification) { updateZoomLabel() }

    @objc private func pinchStarted(_ notification: Notification) { fit = false }

    @objc private func pinchEnded(_ notification: Notification) { canvas.needsDisplay = true }

    private func updateZoomLabel() {
        let percent = (scrollView.magnification * 1000).rounded() / 10
        zoomLabel.stringValue = percent == percent.rounded()
            ? "\(Int(percent))%" : String(format: "%.1f%%", percent)
    }

    // ------------------------------------------------------------ Pixel readout

    private func updatePixelReadout(_ point: NSPoint?) {
        guard let point, let diff, let left, let right else {
            pixelLabel.stringValue = ""
            return
        }
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < diff.width, y < diff.height else {
            pixelLabel.stringValue = ""
            return
        }
        let marker = diff.mask[y * diff.width + x] ? "≠" : "="
        pixelLabel.stringValue = "(\(x), \(y))  L \(hex(left, x, y)) \(marker) R \(hex(right, x, y))"
    }

    private func hex(_ image: PixelImage, _ x: Int, _ y: Int) -> String {
        guard let argb = image.argb(x: x, y: y) else { return " (none)  " }
        return String(format: "#%08X", argb)
    }

    // ------------------------------------------------------------ Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }

        if event.keyCode == 96 { // F5, as on Windows
            compare(nil)
            return nil
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let typing = window?.firstResponder is NSText
        guard modifiers.isEmpty, !typing else { return event }

        switch event.charactersIgnoringModifiers {
        case " ":
            // Ignore auto-repeat so holding the key doesn't strobe between the images.
            if !event.isARepeat { flip(nil) }
            return nil
        case "1":
            setMode(.difference)
            return nil
        case "2":
            setMode(.flip)
            return nil
        default:
            return event
        }
    }

    // ------------------------------------------------------------ Drag and drop

    private func windowDrop(_ files: [URL], at windowPoint: NSPoint) {
        let paths = files.map(\.path)
        if paths.count >= 2 {
            leftField.stringValue = paths[0]
            rightField.stringValue = paths[1]
        } else if unquote(leftField.stringValue).isEmpty {
            leftField.stringValue = paths[0]
        } else if unquote(rightField.stringValue).isEmpty {
            rightField.stringValue = paths[0]
        } else {
            // Both already set: dropping on the left half replaces the left image, otherwise the right.
            let p = scrollView.convert(windowPoint, from: nil)
            (p.x < scrollView.bounds.width / 2 ? leftField : rightField).stringValue = paths[0]
        }
        if hasBothPaths { compare(nil) }
    }

    private func fieldDrop(_ files: [URL], onLeft: Bool) {
        let paths = files.map(\.path)
        (onLeft ? leftField : rightField).stringValue = paths[0]
        if paths.count >= 2 {
            (onLeft ? rightField : leftField).stringValue = paths[1]
        }
        if hasBothPaths { compare(nil) }
    }
}
