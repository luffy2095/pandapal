import AppKit

/// Bao's speech bubble: a rounded body with a tail pointing down at its head, outlined like the panda's
/// own rim, so it reads as the panda speaking.
final class BubbleView: NSView {
    static let tail: CGFloat = 9                  // height of the tail under the body
    static let font: NSFont = {
        let f = NSFont.systemFont(ofSize: 13)
        return NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: 13) ?? f
    }()
    var tailX: CGFloat = 30 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }     // darker while the button is down, like a button

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1.5, y: Self.tail + 1.5, width: bounds.width - 3, height: bounds.height - Self.tail - 3)
        let round = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let x = min(max(tailX, body.minX + 16), body.maxX - 16)
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: x - 7, y: body.minY + 2))
        tip.line(to: NSPoint(x: x - 2, y: 1.5))
        tip.line(to: NSPoint(x: x + 5, y: body.minY + 2))
        tip.close()
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        (pressed ? NSColor.textBackgroundColor.blended(withFraction: 0.18, of: .labelColor)! : NSColor.textBackgroundColor).setFill()
        for p in [tip, round] { p.lineWidth = 3; p.stroke() }    // the fills cover the inner half: a 1.5 pt outline
        round.fill()
        tip.fill()                                                // also hides the outline where tail meets body
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
        let x = min(max(head.x - 30, screen.minX + 4), screen.maxX - frame.width - 4)
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
        super.init(width: 240)
        label.font = BubbleView.font
        bubble.addSubview(label)
    }

    func show(_ text: String, head: NSPoint, seconds: Double = 9) {
        self.text = text
        label.stringValue = text
        let h = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 214, height: 400)).height)
        label.frame = NSRect(x: 13, y: BubbleView.tail + 9, width: 214, height: h)
        place(height: h + BubbleView.tail + 19, head: head)
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
