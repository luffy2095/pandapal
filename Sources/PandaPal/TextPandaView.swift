import AppKit
import QuartzCore

/// The panda in text characters, three lines tall. It follows macOS light and dark mode: dark characters
/// with a white rim in light mode, light characters with a dark rim in dark mode, so it reads on any
/// background without a box. Every frame is drawn to an image once; the compositor swaps the images,
/// so the app does no work while the panda moves.
final class TextPandaView: PandaShell {
    enum Frame: CaseIterable {
        case eat, chomp, blink, lookL, lookR, sneeze1, sneeze2, hiccup, drop1, drop2, doze1, doze2,
             wave1, wave2, stretch1, stretch2, sip1, sip2, hi, happy1, happy2, yawn1, yawn2, curl, nap1, nap2, pet, oops,
             gaze, sun, hi5, giggle1, giggle2, dizzy, shy, angry1, angry2, pout, hug, dangle1, dangle2, curiousL, curiousR, grumble, cheer,
             think, talk1, talk2
    }

    /// Each frame, line by line. Raw strings keep the backslashes literal.
    static let art: [Frame: [String]] = [
        .eat:       [" ●   ●  ╽", " (●ᴥ●)ノ╪", " /(_)   ╿"],
        .chomp:     [" ●   ●  ╽", " (˘ᴥ˘)ノ╪", " /(_)   ╿"],
        .blink:     [" ●   ●  ╽", " (-ᴥ-)ノ╪", " /(_)   ╿"],
        .lookL:     [" ●   ●  ╽", " (◐ᴥ◐)ノ╪", " /(_)   ╿"],
        .lookR:     [" ●   ●  ╽", " (◑ᴥ◑)ノ╪", " /(_)   ╿"],
        .sneeze1:   [" ●   ●  ╽", " (>ᴥ<)ノ╪", " /(_)   ╿"],
        .sneeze2:   [" ●   ●  ╽ ⁎", " (≧ᴥ≦)ノ╪ ⁎⁎", " /(_)   ╿"],
        .hiccup:    [" ●   ●  ╽ hic!", " (°ᴥ°)ノ╪", " /(_)   ╿"],
        .drop1:     [" ●   ●", " (●ᴥ●)ノ", " /(_) ═╪═"],
        .drop2:     [" ●   ●", " (°ᴥ°) !", " /(_) ═╪═"],
        .doze1:     [" ●   ●  z", " (-ᴥ-)", " (u u)═╪═"],          // deep focus: curled up asleep, bamboo set down beside it
        .doze2:     [" ●   ●  zᶻ", " (-ᴥ-)", " (u u)═╪═"],
        .wave1:     [" ●   ●", " (●ᴥ●)ノ", " /(_)"],
        .wave2:     [" ●   ●", " (●ᴥ●)/", " /(_)"],
        .stretch1:  [" ●   ●", #"\(-ᴥ-)/"#, "  (_)"],
        .stretch2:  [" ●   ●", #"\(ᵕᴥᵕ)/"#, "  (_)"],
        .sip1:      [" ●   ●", " (●ᴥ●)っ旦", " /(_)"],
        .sip2:      [" ●   ●", " (˘ᴥ˘)っ旦", " /(_)"],
        .hi:        [" ●   ●  hi", " (ᵔᴥᵔ)ﾉ", " /(_)"],
        .happy1:    [" ●   ●", " (♡ᴥ♡)", #" \(_)/"#],
        .happy2:    [" ●   ●", #"\(♡ᴥ♡)/"#, "  (_)"],
        .yawn1:     [" ●   ●", " (-o-)", " (u u)"],
        .yawn2:     [" ●   ●", " (-O-)", " (u u)"],
        .curl:      [" ●   ●", " (˘ᴥ˘)", " (u u)"],
        .nap1:      [" ●   ●  zᶻ", " (-ᴥ-)", " (u u)"],
        .nap2:      [" ●   ●   zZ", " (-ᴥ-)", " (u u)"],
        .pet:       [" ●   ●  ♡", " (ᵔᴥᵔ)", #" /(_)\"#],
        .oops:      [" ●   ●", " (×ᴥ×)", #"  (_)\_"#],
        .gaze:      [" ●   ●  ╽", " (◔ᴥ◔)ノ╪", " /(_)   ╿"],       // eye rest: gazes into the distance
        .sun:       [" ●   ●  ☼", " (ᵔᴥᵔ)ノ", " /(_)"],            // daylight: waves at the sun
        .hi5:       [" ●   ●  ☆", " (●ᴥ●)ノ", " /(_)"],
        .giggle1:   [" ●   ●  hehe", " (≧ᴥ≦)", #" /(_)\"#],
        .giggle2:   [" ●   ●  hehe", " (>ᴥ<)", #" \(_)/"#],
        .dizzy:     [" ●   ●  ~", " (@ᴥ@)", "  (_)"],
        .shy:       [" ●   ●", " (⁄ᴥ⁄)", #" /(_)\"#],
        .angry1:    [" ●   ●  ╬", " (ÒᴥÓ)", #" /(_)\"#],              // cutely angry: puffed up, stomping
        .angry2:    [" ●   ●   ╬", " (ÒᴥÓ)", #" \(_)/"#],
        .pout:      [" ●   ●  hmph", " (¬ᴥ¬)", "  (_)"],
        .hug:       [" ●   ●  ♡", "⊂(ᵔᴥᵔ)⊃", "  (_)"],
        .dangle1:   [" ●   ●  wheee", #"\(°ᴥ°)/"#, " (u u)"],
        .dangle2:   [" ●   ●  wheee", #"\(°ᴥ°)/"#, " (v v)"],
        .curiousL:  [" ●   ●  ?", " (◐ᴥ◐)", " /(_)"],
        .curiousR:  [" ●   ●  ?", " (◑ᴥ◑)", " /(_)"],
        .grumble:   [" ●   ●  ..", " (-ᴥ•)", " (u u)"],
        .cheer:     [" ●   ●  go!", #"\(●ᴥ●)/"#, "  (_)"],
        .think:     [" ●   ●  …", " (•ᴥ•)", " /(_)"],
        .talk1:     [" ●   ●", " (●ᴥ●)", " /(_)"],
        .talk2:     [" ●   ●", " (●o●)", " /(_)"],
    ]

    static let font = NSFont(name: "Menlo-Regular", size: 22) ?? .monospacedSystemFont(ofSize: 22, weight: .regular)
    static let pad: CGFloat = 4            // room for the rim

    static func fill(_ c: Character, dark: Bool) -> NSColor {
        if "╽╪╿═".contains(c) { return NSColor(red: 0.30, green: 0.66, blue: 0.25, alpha: 1) }   // bamboo
        if c == "♡" { return NSColor(red: 0.98, green: 0.42, blue: 0.58, alpha: 1) }
        if c == "☼" || c == "☆" { return NSColor(red: 0.98, green: 0.68, blue: 0.10, alpha: 1) }
        if c == "⁄" { return NSColor(red: 0.98, green: 0.42, blue: 0.58, alpha: 1) }          // a blush
        if c == "╬" { return NSColor(red: 0.93, green: 0.26, blue: 0.26, alpha: 1) }          // an anger mark
        return dark ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.1, alpha: 1)
    }

    /// Characters drawn two columns wide, as a terminal does. Menlo lacks them, so macOS borrows them from
    /// a font where they are wider than a Menlo cell; a fixed grid keeps everything after them in its column.
    static let wide: Set<Character> = ["ノ", "っ", "旦"]
    static let cellWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
    static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)

    static func columns(_ line: String) -> Int { line.reduce(0) { $0 + (wide.contains($1) ? 2 : 1) } }

    /// `rim` is a thin outline in the opposite tone, drawn first; the normal pass draws the character on top.
    static func attributes(_ c: Character, dark: Bool, rim: Bool) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fill(c, dark: dark)]
        if rim {
            a[.strokeColor] = dark ? NSColor(white: 0.04, alpha: 0.95) : NSColor(white: 1, alpha: 0.95)
            a[.strokeWidth] = 10.0                    // percent of font size; thicker fills the face's gaps
        }
        return a
    }

    /// Fits the widest and tallest frame, so the panda never jumps between frames.
    static let size: NSSize = {
        let cols = art.values.flatMap { $0 }.map(columns).max() ?? 0
        let rows = art.values.map(\.count).max() ?? 0
        return NSSize(width: CGFloat(cols) * cellWidth + pad * 2, height: CGFloat(rows) * lineHeight + pad * 2)
    }()

    /// Draws every character centred in its own grid cell, like a terminal.
    static func render(_ lines: [String], dark: Bool) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for rim in [true, false] {
            for (row, line) in lines.enumerated() {
                let y = size.height - pad - CGFloat(row + 1) * lineHeight
                var col = 0
                for c in line {
                    let span = wide.contains(c) ? 2 : 1
                    if c != " " {
                        let glyph = NSAttributedString(string: String(c), attributes: attributes(c, dark: dark, rim: rim))
                        let x = pad + CGFloat(col) * cellWidth + (CGFloat(span) * cellWidth - glyph.size().width) / 2
                        glyph.draw(at: NSPoint(x: x, y: y))
                    }
                    col += span
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    let holder = CALayer()        // bottom anchor: hops, squish, tumble
    let face = CALayer()
    private var cache: [Frame: CGImage] = [:]
    private var dark = false
    /// Draws a frame the first time it is needed; rare frames such as the sneeze cost nothing until then.
    private func image(_ f: Frame) -> CGImage {
        if let img = cache[f] { return img }
        let img = Self.render(Self.art[f]!, dark: dark)
        cache[f] = img
        return img
    }
    private var paused = false
    private var dozing = false    // curled up asleep by its bamboo during deep focus, so it never distracts you
    private(set) var mood: Mood = .eating

    var deepFocus: Bool { mood == .eating && focusMinutes >= 25 }

    /// The top of the face "(●ᴥ●)", which fills columns 1 to 5 of the grid.
    override var headPoint: NSPoint { NSPoint(x: Self.pad + 3.5 * Self.cellWidth, y: bounds.maxY - Self.pad) }

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        holder.bounds = CGRect(origin: .zero, size: Self.size)
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.position = CGPoint(x: Self.size.width / 2, y: 0)
        layer!.addSublayer(holder)
        face.frame = holder.bounds
        face.contentsScale = 2
        holder.addSublayer(face)
        dark = isDark
        applyPose()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard dark != isDark else { return }
        dark = isDark
        cache = [:]
        applyPose()
    }

    // MARK: motion

    /// Shows `frames` one after another, `step` seconds each, on the compositor.
    private func flip(_ frames: [Frame], step: Double, repeats: Float = 1, key: String = "burst") {
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames.map { image($0) }
        a.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }   // discrete: n + 1
        a.calculationMode = .discrete
        a.duration = step * Double(frames.count)
        a.repeatCount = repeats
        face.add(a, forKey: key)
    }

    /// A long still frame with a quick blink at the end, looping.
    private func blinkLoop(_ open: Frame, _ shut: Frame) {
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = [image(open), image(shut)]
        a.keyTimes = [0, 0.95, 1]
        a.calculationMode = .discrete
        a.duration = 5
        a.repeatCount = .infinity
        face.add(a, forKey: "loop")
    }

    private func move(_ key: String, _ values: [CGFloat], _ duration: Double) {
        let a = CAKeyframeAnimation(keyPath: key)
        a.values = values
        a.duration = duration
        a.isAdditive = true
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        holder.add(a, forKey: key)
    }

    /// The still frame and ongoing loop for the current mood and context.
    private func applyPose() {
        dozing = deepFocus
        let bigHello = lastBreakMinutes >= 30 || bondLevel >= 1     // at bond level 1 it runs to greet you
        let base: Frame
        switch mood {
        case .eating: base = dozing ? .doze1 : .eat
        case .wantsBreak: base = .wave1
        case .happy: base = bigHello ? .happy1 : .hi
        case .napping: base = .nap1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.contents = image(base)
        CATransaction.commit()
        switch mood {
        case .eating where dozing: flip([.doze1, .doze2], step: 0.9, repeats: .infinity, key: "loop")
        case .eating: blinkLoop(.eat, .blink)
        case .wantsBreak: flip([.wave1, .wave2], step: 0.4, repeats: .infinity, key: "loop")
        case .happy where bigHello: flip([.happy1, .happy2], step: 0.35, repeats: .infinity, key: "loop")
        case .happy: flip([.hi, .hi, .hi, .wave1], step: 0.4, repeats: .infinity, key: "loop")
        case .napping: flip([.nap1, .nap2], step: 0.8, repeats: .infinity, key: "loop")
        }
    }

    override func show(_ new: Mood) {
        guard new != mood else { return }
        mood = new
        applyPose()
        if new == .napping {
            flip([.yawn1, .yawn2, .yawn2, .stretch1, .curl, .curl], step: 0.6)     // yawns and stretches, then sleeps
        } else {
            burst()
            if new == .happy, bondLevel >= 2, !paused { tumble() }          // at bond level 2 it shows off a roll
        }
    }

    /// A moment for the current mood, a few seconds long, then back to its loop.
    override func burst() {
        guard !paused else { return }
        if dozing != deepFocus { applyPose() }        // just entered or left deep focus
        switch mood {
        case .eating where dozing:
            break                                     // sleeps on: no moments while you focus
        case .eating:
            if let t = temper, Int.random(in: 0..<3) == 0 {        // a third of its moments show today's mood
                switch t {
                case .sleepy: flip([.yawn1, .yawn2, .yawn2, .blink, .eat], step: 0.6)
                case .playful: flip([.giggle1, .giggle2, .giggle1, .eat], step: 0.3)
                case .grumpy: flip([.pout, .pout, .eat], step: 0.6)
                case .cuddly: flip([.pet, .pet, .eat], step: 0.6)
                case .curious: flip(cursorSide < 0 ? [.curiousL, .curiousL, .eat] : [.curiousR, .curiousR, .eat], step: 0.6)
                }
                return
            }
            switch Int.random(in: 0..<20) {
            case 0..<13: flip([.eat, .chomp, .eat, .chomp, .eat, .chomp], step: 0.35)
            case 13..<17:
                let look: [Frame] = cursorSide < 0 ? [.lookL, .lookL, .lookL, .eat] : cursorSide > 0 ? [.lookR, .lookR, .lookR, .eat]
                                  : [.lookL, .lookL, .eat, .lookR, .lookR, .eat]
                flip(look, step: 0.5)
            case 17: flip([.eat, .sneeze1, .sneeze1, .sneeze2, .sneeze2, .eat], step: 0.4)
            case 18:
                flip([.hiccup, .eat, .eat, .hiccup, .eat], step: 0.4)
                move("transform.translation.y", [0, 4, 0, 0, 0, 4, 0], 2)
            default: flip([.drop1, .drop2, .drop2, .drop1, .eat], step: 0.6)
            }
        case .wantsBreak:
            if waterTip {
                flip([.sip1, .sip2, .sip1, .sip2, .sip1], step: 0.6)
            } else {
                flip([.stretch1, .stretch2, .stretch1, .stretch2], step: 0.6)
            }
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        case .happy:
            move("transform.translation.y", lastBreakMinutes >= 30 ? [0, 9, 0, 7, 0, 5, 0] : [0, 5, 0], 1.2)
        case .napping:
            break
        }
    }

    /// A short scene for each moment the brain picks.
    override func cue(_ cue: Cue) {
        guard !paused else { return }
        switch cue {
        case .gaze: flip([.gaze, .gaze, .gaze, .gaze, .blink, .eat], step: 0.8)
        case .lookAtYou:
            flip([.eat, .wave1, .stretch1, .stretch2, .stretch1, .eat], step: 0.5)
            move("transform.translation.y", [0, 4, 0], 0.6)
        case .sip: flip([.sip1, .sip2, .sip1, .sip2, .eat], step: 0.6)
        case .sun: flip([.sun, .sun, .sun, .hi, .eat], step: 0.7)
        case .morning:
            flip([.hi, .hi, .happy1, .happy2, .happy1, .hi], step: 0.5)
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        case .sleepy: flip([.yawn1, .yawn2, .yawn2, .blink, .eat], step: 0.6)
        case .reunion:
            flip([.happy1, .happy2, .happy1, .happy2, .pet, .happy2, .happy1], step: 0.4)
            move("transform.translation.y", [0, 10, 0, 8, 0, 10, 0], 2)
        case .remind:                                                            // waves to get your attention
            flip([.wave1, .wave2, .wave1, .wave2, .wave1, .wave2, .hi, .hi], step: 0.35)
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        }
    }

    /// How it answers your mouse. The personality picks the reaction; this plays it.
    override func react(_ r: Reaction) {
        guard !paused else { return }
        switch r {
        case .pet: pet()
        case .highFive:
            flip([.hi5, .hi5, .hi5], step: 0.4)
            move("transform.translation.y", [0, 6, 0], 0.4)
        case .giggle:
            flip([.giggle1, .giggle2, .giggle1, .giggle2, .giggle1, .giggle2], step: 0.25)
            move("transform.rotation.z", [0, 0.06, -0.06, 0.06, -0.06, 0], 1.5)
        case .dizzy:
            flip([.dizzy, .dizzy, .dizzy, .dizzy, .dizzy], step: 0.4)
            tumble()
        case .shy:
            flip(Array(repeating: .shy, count: 10), step: 1)                     // hides its face for 10 seconds
        case .angry:                                                             // each tap restarts it, so it ends when the taps stop
            flip([.angry1, .angry2, .angry1, .angry2, .angry1, .angry2], step: 0.3)
            move("transform.translation.y", [0, 3, 0, 3, 0, 3, 0], 1.8)
        case .pout:
            flip([.pout, .pout, .pout, .pout], step: 0.5)
            move("transform.translation.x", [0, -3, 3, -3, 0], 0.5)
        case .hug:
            flip([.hug, .hug, .hug, .hug], step: 0.5)
            move("transform.scale.y", [0, -0.05, -0.05, 0.02, 0], 1.6)
            move("transform.scale.x", [0, 0.05, 0.05, -0.02, 0], 1.6)
        case .dangle:
            flip([.dangle1, .dangle2], step: 0.25, repeats: .infinity, key: "dangle")   // kicks its legs until you let go
        case .drop:
            face.removeAnimation(forKey: "dangle")
            move("transform.translation.y", [0, 8, 0, 3, 0], 0.6)
        case .dizzyDrop:
            face.removeAnimation(forKey: "dangle")
            flip([.dizzy, .dizzy, .dizzy, .dizzy], step: 0.5)
            move("transform.rotation.z", [0, 0.1, -0.1, 0.08, -0.08, 0], 2)
        case .curious:
            let f: Frame = cursorSide < 0 ? .curiousL : .curiousR
            flip([f, f, f, f], step: 0.5)
        case .grumble: flip([.grumble, .grumble, .grumble, .nap1], step: 0.6)    // one eye opens, then back to sleep
        case .wakeUp: flip([.yawn1, .yawn2, .yawn2, .blink, .eat], step: 0.6)
        case .cheer:
            flip([.cheer, .stretch2, .cheer, .stretch2], step: 0.4)
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        }
    }

    override func thinking() { flip([.think], step: 1, repeats: .infinity, key: "talk") }

    override func talking(_ on: Bool) {
        if on { flip([.talk1, .talk2], step: 0.18, repeats: .infinity, key: "talk") }
        else { face.removeAnimation(forKey: "talk") }
    }

    override func pet() {
        move("transform.scale.x", [0, 0.06, -0.02, 0], 0.5)
        move("transform.scale.y", [0, -0.06, 0.02, 0], 0.5)
        flip([.pet, .pet], step: 0.8)
    }

    override func tumble() {
        move("transform.rotation.z", [0, 0.4, 3.14, 5.9, 6.283], 1.2)
        flip([.oops, .oops], step: 1)
    }

    override func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p {
            let t = holder.convertTime(CACurrentMediaTime(), from: nil)
            holder.speed = 0
            holder.timeOffset = t
        } else {
            let t = holder.timeOffset
            holder.speed = 1
            holder.timeOffset = 0
            holder.beginTime = 0
            holder.beginTime = holder.convertTime(CACurrentMediaTime(), from: nil) - t
        }
    }

    /// Writes every frame, in both modes, over a matching background. Used by `--snapshot`.
    static func writeFrames(to dir: URL) {
        for dark in [true, false] {
            for f in Frame.allCases {
                let img = render(art[f]!, dark: dark)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: img.width, pixelsHigh: img.height, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.setFillColor(dark ? NSColor(white: 0.07, alpha: 1).cgColor : NSColor(white: 0.95, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("text-\(f)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
