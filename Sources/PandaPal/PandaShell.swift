import AppKit

/// What every panda body shares: recognising what your mouse does (tap, press and hold, drag, shake,
/// the pointer coming near), the right-click menu, and the hooks the app calls. Bodies override the hooks.
class PandaShell: NSView {
    var onGesture: ((Gesture) -> Void)?
    var contextMenu: NSMenu?
    var focusMinutes: Double = 0        // screen time without a break, for deep-focus behaviour
    var lastBreakMinutes: Double = 0    // how long the last break was, for the size of the greeting
    var tipAct: TipAct = .stretch       // how it acts out the current break idea
    var bondLevel = 0                   // 0, 1 or 2: higher bond unlocks bigger greetings and tricks
    var temper: Temper?                 // today's mood, which colours some of its moments
    var cursorSide = 0                  // -1 left, 0 near, 1 right: where to glance during a moment
    var gift: Gift?                     // today's gift, which sits beside the panda
    var awakeUntil = Date.distantPast   // a script's message woke it: no nap or doze before this
    var headPoint: NSPoint { NSPoint(x: bounds.midX, y: bounds.maxY) }   // where speech bubbles point

    func show(_ mood: Mood) {}
    func burst() {}
    func pet() {}
    func tumble() {}
    func setPaused(_ paused: Bool) {}
    func cue(_ cue: Cue) {}
    func react(_ reaction: Reaction) {}
    func treat(_ t: Treat) {}           // a surprise: a trick, a heart, or a gift
    func breathe(cycles: Int) {}        // breathes slowly with you: in, hold, out
    func talking(_ on: Bool) {}         // mouth moves while words appear

    private var downPoint: NSPoint?
    private var dragging = false
    private var held = false
    private var holdTimer: Timer?
    private var lastDX: CGFloat = 0
    private var flips: [Date] = []      // horizontal direction changes while dragging: a shake
    private var lastDY: CGFloat = 0
    private var wiggles: [Date] = []    // vertical direction changes of the pointer over the panda: a tickle
    private var lastMoveDX: CGFloat = 0
    private var sways: [Date] = []      // side-to-side direction changes of the pointer over the panda: a wave

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
        held = false
        flips = []
        lastDX = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, !self.dragging else { return }
            self.held = true
            self.onGesture?(.longPress)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, let w = window else { return }
        let p = event.locationInWindow
        let dx = p.x - start.x, dy = p.y - start.y
        if !dragging, hypot(dx, dy) < 3 { return }                  // a small wobble is still a tap
        if !dragging {
            dragging = true
            holdTimer?.invalidate()
            onGesture?(.dragStart)
        }
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx, y: w.frame.origin.y + dy))
        if abs(dx) > 2 {
            if lastDX != 0, (dx > 0) != (lastDX > 0) { flips.append(Date()) }
            lastDX = dx
        }
        flips = flips.filter { Date().timeIntervalSince($0) < 1 }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        if dragging {
            if let w = window { UserDefaults.standard.set(NSStringFromPoint(w.frame.origin), forKey: "pandaOrigin") }
            onGesture?(.dragEnd(shaken: flips.count >= 4))
        } else if !held {
            onGesture?(.tap)
        }
        downPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        if let m = contextMenu { NSMenu.popUpContextMenu(m, with: event, for: self) }
    }

    // the pointer coming near: enter events only, no permission and no tracking elsewhere on screen
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        lastDY = 0
        wiggles = []
        lastMoveDX = 0
        sways = []
        onGesture?(.hover)
    }

    /// Four fast up-and-down turns within a second, without clicking, is a tickle. Only while the pointer is over the panda.
    override func mouseMoved(with event: NSEvent) {
        let dx = event.deltaX                                        // four side-to-side turns in 1.5 seconds: a wave
        if abs(dx) > 2 {
            if lastMoveDX != 0, (dx > 0) != (lastMoveDX > 0) { sways.append(Date()) }
            lastMoveDX = dx
            sways = sways.filter { Date().timeIntervalSince($0) < 1.5 }
            if sways.count >= 4 {
                sways = []
                onGesture?(.wave)
            }
        }
        let dy = event.deltaY
        guard abs(dy) > 2 else { return }                            // slow movement is not a tickle
        if lastDY != 0, (dy > 0) != (lastDY > 0) { wiggles.append(Date()) }
        lastDY = dy
        wiggles = wiggles.filter { Date().timeIntervalSince($0) < 1 }
        if wiggles.count >= 4 {
            wiggles = []
            onGesture?(.tickle)
        }
    }
}
