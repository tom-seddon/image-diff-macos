import AppKit

/// Reads file URLs from a drag.
func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
    let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL]
    return urls ?? []
}

/// The window's content view; files dropped anywhere that doesn't handle them itself land here.
final class DropContentView: NSView {
    var onDrop: (([URL], NSPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFiles(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = droppedFiles(sender)
        guard !files.isEmpty else { return false }
        onDrop?(files, sender.draggingLocation)
        return true
    }
}

/// A path box that also takes files dropped onto it.
final class PathField: NSTextField {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFiles(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = droppedFiles(sender)
        guard !files.isEmpty else { return super.performDragOperation(sender) }
        onDrop?(files)
        return true
    }
}

/// A label that lets clicks and drags through to whatever is underneath.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The "Left: ..." / "Right: ..." label shown over the image in Flip view.
final class BadgeView: NSView {
    let label = PassthroughLabel(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer?.cornerRadius = 4
        label.textColor = .white
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shows one image, one image pixel per point at 100%, with hard pixel edges when zoomed in.
/// The image is the layer's contents, so showing or hiding it is instant.
final class ImageLayerView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .trilinear
    }

    // Mouse events go to the canvas underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The scroll view's document: a checkerboard (so transparency shows) with the difference image and
/// both originals on top, aligned at the top-left. Handles panning, click to flip and the pixel readout.
final class CanvasView: NSView {
    let diffView = ImageLayerView()
    let leftView = ImageLayerView()
    let rightView = ImageLayerView()

    /// A left click without dragging.
    var onClick: (() -> Void)?
    /// The mouse moved over the canvas; the point is in image pixels, or nil when the mouse left.
    var onHover: ((NSPoint?) -> Void)?

    // A click that moves less than this (in screen points) flips instead of panning.
    private static let clickSlop: CGFloat = 4

    private var dragButton: Int?
    private var dragStart = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var panning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for view in [diffView, leftView, rightView] {
            addSubview(view)
        }
        leftView.isHidden = true
        rightView.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()

        // Keep the squares at least 8 points on screen however far out the view is zoomed.
        let magnification = enclosingScrollView?.magnification ?? 1
        let cell = max(8, 8 / magnification)
        NSColor(white: 0.88, alpha: 1).setFill()
        let x0 = Int(floor(dirtyRect.minX / cell)), x1 = Int(ceil(dirtyRect.maxX / cell))
        let y0 = Int(floor(dirtyRect.minY / cell)), y1 = Int(ceil(dirtyRect.maxY / cell))
        for y in y0..<y1 {
            for x in x0..<x1 where (x + y) % 2 != 0 {
                NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell).fill()
            }
        }
    }

    // ------------------------------------------------------------ Pixel readout

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { reportHover(event) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    private func reportHover(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onHover?(bounds.contains(p) ? NSPoint(x: floor(p.x), y: floor(p.y)) : nil)
    }

    // ------------------------------------------------------------ Panning and click to flip

    override func mouseDown(with event: NSEvent) { beginDrag(event) }
    override func rightMouseDown(with event: NSEvent) { beginDrag(event) }
    override func otherMouseDown(with event: NSEvent) { beginDrag(event) }
    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func otherMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag(event) }
    override func otherMouseUp(with event: NSEvent) { endDrag(event) }

    private func beginDrag(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        guard dragButton == nil, let clip = enclosingScrollView?.contentView else { return }
        dragButton = event.buttonNumber
        dragStart = event.locationInWindow
        dragStartOrigin = clip.bounds.origin
        panning = false
    }

    private func continueDrag(_ event: NSEvent) {
        reportHover(event)
        guard event.buttonNumber == dragButton, let scrollView = enclosingScrollView else { return }

        let dx = event.locationInWindow.x - dragStart.x
        let dy = event.locationInWindow.y - dragStart.y
        if !panning && hypot(dx, dy) < Self.clickSlop { return }
        if !panning {
            panning = true
            NSCursor.closedHand.push()
        }

        // Window y points up and the canvas is flipped, so dragging down moves the view up the image.
        let clip = scrollView.contentView
        let m = scrollView.magnification
        let origin = NSPoint(x: dragStartOrigin.x - dx / m, y: dragStartOrigin.y + dy / m)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func endDrag(_ event: NSEvent) {
        guard event.buttonNumber == dragButton else { return }
        let click = !panning && dragButton == 0
        if panning {
            NSCursor.pop()
        }
        dragButton = nil
        panning = false
        if click {
            onClick?()
        }
    }
}

/// Zooms with Command + scroll wheel (pinch works too), and reports resizes so Fit can follow the window.
final class ZoomScrollView: NSScrollView {
    /// Zoom by a factor, keeping the given canvas point under the mouse.
    var onZoom: ((CGFloat, NSPoint) -> Void)?
    var onResize: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let documentView else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? exp(delta * 0.01) : (delta > 0 ? 1.25 : 0.8)
        onZoom?(factor, documentView.convert(event.locationInWindow, from: nil))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}
