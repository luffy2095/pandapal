import AppKit

/// Bao's speech bubble: a thought cloud with two small puffs drifting down to its head, outlined like the
/// panda's own rim.
final class BubbleView: NSView {
    static let tail: CGFloat = 19.5               // room under the cloud for the two puffs
    static let puff: CGFloat = 7                  // room around the cloud's body for its bumps and outline
    static let font: NSFont = {
        let f = NSFont.systemFont(ofSize: 13)
        return NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: 13) ?? f
    }()
    var tailX: CGFloat = 30 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }     // darker while the button is down, like a button

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: Self.puff, y: Self.tail, width: bounds.width - 2 * Self.puff, height: bounds.height - Self.tail - Self.puff)
        let x = min(max(tailX, body.minX + 16), body.maxX - 16)
        let shapes = [Self.cloud(body), Self.circle(x - 1, 12.5, 4.5), Self.circle(x - 5, 4.5, 2.6)].map { NSBezierPath(cgPath: $0) }
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        (pressed ? NSColor.textBackgroundColor.blended(withFraction: 0.18, of: .labelColor)! : NSColor.textBackgroundColor).setFill()
        for p in shapes { p.lineWidth = 3; p.stroke() }    // the fills cover the inner half: a 1.5 pt outline
        for p in shapes { p.fill() }
    }

    /// A rounded body with round bumps along its edge, big and small in turn along the top and bottom.
    private static func cloud(_ b: NSRect) -> CGPath {
        let r: CGFloat = 12, inset = r * 0.55, step = r * 1.3
        func spread(_ from: CGFloat, _ to: CGFloat) -> [CGFloat] {
            let n = max(2, Int(((to - from) / step).rounded()) + 1)
            return (0..<n).map { from + (to - from) * CGFloat($0) / CGFloat(n - 1) }
        }
        var path = CGPath(roundedRect: b, cornerWidth: 10, cornerHeight: 10, transform: nil)
        for (i, x) in spread(b.minX + inset, b.maxX - inset).enumerated() {
            let k: CGFloat = i % 2 == 0 ? 1 : 0.8
            path = path.union(circle(x, b.maxY - inset * k, r * k)).union(circle(x, b.minY + inset * k, r * k))
        }
        for y in spread(b.minY + inset, b.maxY - inset) {
            path = path.union(circle(b.minX + inset, y, r)).union(circle(b.maxX - inset, y, r))
        }
        return path
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
    }

    override func mouseDown(with event: NSEvent) { pressed = onClick != nil }

    /// Acts on release, and only if the pointer is still on the bubble.
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

/// A borderless floating window holding one bubble.
class BubblePanel: NSPanel {
    let bubble = BubbleView()
    weak var anchor: NSWindow?           // the panda's window: while shown, the bubble moves with it as you drag

    init(width: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 40), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = bubble
        bubble.wantsLayer = true
    }

    /// Grows out of Bao's head as it appears.
    func pop() { animate([0.6, 1], duration: 0.25) }

    /// A few small bounces toward Bao's head, to catch your eye when you may have looked away.
    func nudge() { animate([1, 0.93, 1, 0.93, 1, 0.93, 1], duration: 1.4) }

    /// Scales the bubble about its tail tip, so it moves toward and away from Bao's head. Never above 1,
    /// because the window is exactly the bubble's size and would clip it.
    private func animate(_ scales: [CGFloat], duration: Double) {
        guard let layer = bubble.layer else { return }
        let tip = CGPoint(x: bubble.tailX - layer.anchorPoint.x * bubble.bounds.width, y: -layer.anchorPoint.y * bubble.bounds.height)
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = scales.map { s in
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-tip.x, -tip.y, 0),
                                                                           CATransform3DMakeScale(s, s, 1)),
                                                       CATransform3DMakeTranslation(tip.x, tip.y, 0)))
        }
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(a, forKey: "attention")
    }

    /// Sizes the bubble and puts its tail tip just above `head` (screen points), kept on screen.
    func place(height: CGFloat, head: NSPoint) {
        let screen = (NSScreen.screens.first { $0.frame.contains(head) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(head.x - 36, screen.minX + 4), screen.maxX - frame.width - 4)
        let y = min(head.y + 2, screen.maxY - height)
        setFrame(NSRect(x: x, y: y, width: frame.width, height: height), display: true)
        bubble.tailX = head.x - x
        if let anchor, parent == nil { anchor.addChildWindow(self, ordered: .above) }
    }

    override func orderOut(_ sender: Any?) { parent?.removeChildWindow(self); super.orderOut(sender) }
    override func close() { parent?.removeChildWindow(self); super.close() }
}

/// Bao's own short lines, above its head. Click one to put it away; it fades by itself otherwise.
final class SpeechBubble: BubblePanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?
    private(set) var text = ""
    var onClick: (() -> Void)? { didSet { bubble.onClick = { [weak self] in self?.orderOut(nil); self?.onClick?() } } }

    init() {
        super.init(width: 214 + 23 + 2 * BubbleView.puff)     // the text, its padding, and room for the bumps
        label.font = BubbleView.font
        bubble.addSubview(label)
    }

    func show(_ text: String, head: NSPoint, seconds: Double = 9) {
        self.text = text
        label.stringValue = text
        let h = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 214, height: 400)).height)
        label.frame = NSRect(x: BubbleView.puff + 11.5, y: BubbleView.tail + 7.5, width: 214, height: h)
        place(height: h + 16 + BubbleView.tail + BubbleView.puff, head: head)
        orderFrontRegardless()
        pop()
        hide(after: seconds)
    }

    /// Puts the bubble away after `seconds`, unless something new shows in it first.
    func hide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
