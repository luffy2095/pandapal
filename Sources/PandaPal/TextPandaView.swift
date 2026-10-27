import AppKit
import QuartzCore

/// The panda in text characters, three lines tall. It follows macOS light and dark mode: dark characters
/// with a white rim in light mode, light characters with a dark rim in dark mode, so it reads on any
/// background without a box. Every frame is drawn to an image once; the compositor swaps the images,
/// so the app does no work while the panda moves.
final class TextPandaView: PandaShell {
    enum Frame: CaseIterable {
        case eat, chomp, blink, lookL, lookR, sneeze1, sneeze2, hiccup, drop1, drop2,
             wave1, wave2, stretch1, stretch2, sip1, sip2, hi, happy1, happy2, yawn1, yawn2, curl, nap1, nap2, nap3, pet, oops,
             gaze, sun, hi5, giggle1, giggle2, dizzy, shy, angry1, angry2, pout, hug, dangle1, dangle2, curiousL, curiousR, grumble, cheer,
             talk1, talk2, calm, lookFar, shake1, shake2, tide1, tide2, tide3, juggle1, juggle2
    }

    /// Each frame, line by line. Raw strings keep the backslashes literal.
    static let art: [Frame: [String]] = [
        .eat:       [" ●   ●  ╽", " (●ᴥ●)ノ╪", " /(_)   ╿"],
        .chomp:     [" ●   ●  ╽", " (˘ᴥ˘)ノ╪", " /(_)   ╿"],
        .blink:     [" ●   ●  ╽", " (-ᴥ-)ノ╪", " /(_)   ╿"],
        .lookL:     [" ●   ●  ╽", " (◐ᴥ◐)ノ╪", " /(_)   ╿"],
        .lookR:     [" ●   ●  ╽", " (◑ᴥ◑)ノ╪", " /(_)   ╿"],
        .sneeze1:   [" ●   ●  ╽", " (>ᴥ<)ノ╪", " /(_)   ╿"],
        .sneeze2:   [" ●   ●  ╽", " (≧ᴥ≦)ノ╪", " /(_)   ╿"],
        .hiccup:    [" ●   ●  ╽ hic!", " (°ᴥ°)ノ╪", " /(_)   ╿"],
        .drop1:     [" ●   ●", " (●ᴥ●)ノ", " /(_) ═╪═"],
        .drop2:     [" ●   ●", " (°ᴥ°) !", " /(_) ═╪═"],
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
        .pet:       [" ●   ●", " (ᵔᴥᵔ)", #" /(_)\"#],
        .oops:      [" ●   ●", " (×ᴥ×)", #"  (_)\_"#],
        .gaze:      [" ●   ●  ╽", " (◔ᴥ◔)ノ╪", " /(_)   ╿"],       // eye rest: gazes into the distance
        .sun:       [" ●   ●  ☼", " (ᵔᴥᵔ)ノ", " /(_)"],            // daylight: waves at the sun
        .hi5:       [" ●   ●  ☆", " (●ᴥ●)ノ", " /(_)"],
        .giggle1:   [" ●   ●", " (≧ᴥ≦)", #" /(_)\"#],            // the laugh word is laid over it, a different one each time
        .giggle2:   [" ●   ●", " (>ᴥ<)", #" \(_)/"#],
        .dizzy:     [" ●   ●  ~", " (@ᴥ@)", "  (_)"],
        .shy:       [" ●   ●", " (⁄ᴥ⁄)", #" /(_)\"#],
        .angry1:    [" ●   ● ╬", " (ÒᴥÓ)", #" /(_)\"#],              // cutely angry: puffed up, stomping
        .angry2:    [" ●   ●  ╬", " (ÒᴥÓ)", #" \(_)/"#],
        .pout:      [" ●   ●  hmph", " (¬ᴥ¬)", "  (_)"],
        .hug:       [" ●   ●", "⊂(ᵔᴥᵔ)⊃", "  (_)"],
        .dangle1:   [" ●   ●  wheee", #"\(°ᴥ°)/"#, " (u u)"],
        .dangle2:   [" ●   ●  wheee", #"\(°ᴥ°)/"#, " (v v)"],
        .curiousL:  [" ●   ● ?", " (◐ᴥ◐)", #" /(_)\"#],
        .curiousR:  [" ●   ● ?", " (◑ᴥ◑)", #" /(_)\"#],
        .cheer:     [" ●   ●  go!", #"\(●ᴥ●)/"#, "  (_)"],
        .talk1:     [" ●   ●", " (●ᴥ●)", #" /(_)\"#],
        .talk2:     [" ●   ●", " (●o●)", #" /(_)\"#],
        .calm:      [" ●   ●", " (-ᴥ-)", #" /(_)\"#],                 // eyes closed: breathing, blinking
        .lookFar:   [" ●   ●  ~", " (◔ᴥ◔)", #" /(_)\"#],              // looking far away
        .shake1:    [" ●   ●", #"\(●ᴥ●)/"#, "  (_)"],                 // shaking out its paws
        .shake2:    [" ●   ●", #"/(●ᴥ●)\"#, "  (_)"],
        .tide1:     [" ●   ●", "~(ᵔᴥᵔ~)", "  (_)"],                // the tide dance: both arms flow over to the left,
        .tide2:     [" ●   ●", #"\(ᵔᴥᵔ)/"#, "  (_)"],              // up as the wave passes,
        .tide3:     [" ●   ●", "(~ᵔᴥᵔ)~", "  (_)"],                 // and over to the right
        .juggle1:   [" ●   ●  ╪", " (ᵔᴥᵔ)ノ ╪", " /(_)"],
        .juggle2:   [" ●   ●   ╪", " (ᵔᴥᵔ)ノ╪", " /(_)"],
    ]

    /// Frames where it lies on its side: the upright panda in `body` is drawn, then turned a quarter so its head
    /// rests on the left and its legs point right, and `over` (its z's) is drawn upright on top.
    static let asleep = [" ●   ●", " (-ᴥ-)", " (u u)"]
    static let lying: [Frame: (body: [String], over: [String])] = [
        .curl: ([" ●   ●", " (˘ᴥ˘)", " (u u)"], []),                    // lies down
        .nap1: (asleep, ["      z"]),
        .nap2: (asleep, ["      z z"]),
        .nap3: (asleep, ["      z z Z"]),
        .grumble: ([" ●   ●", " (-ᴥ•)", " (u u)"], ["      .."]),      // one eye opens
    ]

    static let font = NSFont(name: "Menlo-Regular", size: 22) ?? .monospacedSystemFont(ofSize: 22, weight: .regular)
    static let pad: CGFloat = 4            // room for the rim
    /// Words in a frame ("hi", "hehe", "wheee") are smaller than the panda, so they read as its voice.
    static let wordFont = NSFont(name: "Menlo-Regular", size: 16) ?? .monospacedSystemFont(ofSize: 16, weight: .regular)

    static func fill(_ c: Character, dark: Bool) -> NSColor {
        if "╽╪╿═".contains(c) { return NSColor(red: 0.30, green: 0.66, blue: 0.25, alpha: 1) }   // bamboo
        if c == "♡" { return NSColor(red: 0.98, green: 0.42, blue: 0.58, alpha: 1) }
        if c == "☼" || c == "☆" { return NSColor(red: 0.98, green: 0.68, blue: 0.10, alpha: 1) }
        if c == "⁄" { return NSColor(red: 0.98, green: 0.42, blue: 0.58, alpha: 1) }          // a blush
        if c == "╬" { return NSColor(red: 0.93, green: 0.26, blue: 0.26, alpha: 1) }          // an anger mark
        if c == "✿" { return NSColor(red: 0.98, green: 0.42, blue: 0.58, alpha: 1) }          // gifts
        if "★☾".contains(c) { return NSColor(red: 0.98, green: 0.68, blue: 0.10, alpha: 1) }
        if "♪♫".contains(c) { return NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1) }
        if c == "☘" { return NSColor(red: 0.30, green: 0.66, blue: 0.25, alpha: 1) }
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

    /// Bao's size from the menu: 0.75, 1 or 1.3. Everything is drawn at size 1 and the stage scales it.
    static var scale: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "pandaScale")
        return saved > 0 ? saved : 1
    }()
    /// Pixels per point in the frame images: Retina, and more when Bao is large, so text stays sharp.
    static var density: CGFloat { 2 * max(1, scale) }

    /// Draws every character centred in its own grid cell, like a terminal.
    static func render(_ lines: [String], dark: Bool) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * density), pixelsHigh: Int(size.height * density),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for rim in [true, false] {
            for (row, line) in lines.enumerated() {
                let y = size.height - pad - CGFloat(row + 1) * lineHeight
                // a word is two or more letters, maybe with "!"; it starts at its column, in the smaller font
                var inWord = Set<Int>()
                for r in line.ranges(of: #/[A-Za-z]{2,}!?/#) {
                    let start = line.distance(from: line.startIndex, to: r.lowerBound)
                    inWord.formUnion(start..<start + line[r].count)
                    var a = attributes("a", dark: dark, rim: rim)
                    a[.font] = wordFont
                    let x = pad + CGFloat(columns(String(line[..<r.lowerBound]))) * cellWidth
                    let lift = (lineHeight - NSLayoutManager().defaultLineHeight(for: wordFont)) / 2
                    NSAttributedString(string: String(line[r]), attributes: a).draw(at: NSPoint(x: x, y: y + lift))
                }
                var col = 0
                for (i, c) in line.enumerated() {
                    let span = wide.contains(c) ? 2 : 1
                    if c != " ", !inWord.contains(i) {
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

    /// One frame as an image: its lines, or the panda lying on its side.
    static func draw(_ f: Frame, dark: Bool) -> CGImage {
        guard let l = lying[f] else { return render(art[f]!, dark: dark) }
        // the upright panda fills columns 1 to 5 of the grid; take them with a little of the rim around them
        let body = render(l.body, dark: dark)
            .cropping(to: CGRect(x: (pad + cellWidth - 3) * density, y: 0, width: (5 * cellWidth + 6) * density, height: size.height * density))!
        let w = CGFloat(body.width) / density, h = CGFloat(body.height) / density
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * density), pixelsHigh: Int(size.height * density),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: density, y: density)
        ctx.draw(render(l.over, dark: dark), in: CGRect(origin: .zero, size: size))
        ctx.translateBy(x: pad + h / 2, y: w / 2)                     // turned, it is h wide and w tall, on the ground
        ctx.rotate(by: .pi / 2)
        ctx.draw(body, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    let holder = CALayer()        // bottom anchor: hops, squish, tumble
    let face = CALayer()
    let giftLayer = CALayer()     // today's gift, on the ground beside the panda; it stays put while the panda moves
    let sayLayer = CALayer()      // a word it says for a moment, such as its laugh, laid over the frame
    static let laughs = ["hehe", "haha", "hihi", "teehee", "hoho", "ehehe"]
    private var words: [String: CGImage] = [:]
    private var cache: [Frame: CGImage] = [:]
    private var dark = false
    /// Draws a frame the first time it is needed; rare frames such as the sneeze cost nothing until then.
    private func image(_ f: Frame) -> CGImage {
        if let img = cache[f] { return img }
        let img = Self.draw(f, dark: dark)
        cache[f] = img
        return img
    }
    private var paused = false
    private var dozing = false    // asleep on its side during deep focus, so it never distracts you
    private(set) var mood: Mood = .eating

    var deepFocus: Bool { mood == .eating && focusMinutes >= 25 }

    /// The top of the face "(●ᴥ●)", which fills columns 1 to 5 of the grid.
    override var headPoint: NSPoint { NSPoint(x: (Self.pad + 3.5 * Self.cellWidth) * Self.scale, y: bounds.maxY - Self.pad * Self.scale) }

    /// Everything Bao draws, at size 1, scaled to its size as one piece.
    let stage = CALayer()

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: NSSize(width: Self.size.width * Self.scale, height: Self.size.height * Self.scale)))
        wantsLayer = true
        stage.anchorPoint = .zero
        stage.bounds = CGRect(origin: .zero, size: Self.size)
        stage.position = .zero
        stage.setAffineTransform(CGAffineTransform(scaleX: Self.scale, y: Self.scale))
        layer!.addSublayer(stage)
        holder.bounds = CGRect(origin: .zero, size: Self.size)
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.position = CGPoint(x: Self.size.width / 2, y: 0)
        stage.addSublayer(holder)
        for l in [face, giftLayer, sayLayer] {
            l.frame = holder.bounds
            l.contentsScale = Self.density
        }
        holder.addSublayer(face)
        stage.addSublayer(giftLayer)
        sayLayer.opacity = 0
        stage.addSublayer(sayLayer)
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
        words = [:]
        applyPose()
        showGift()
    }

    override var gift: Gift? { didSet { if gift != oldValue { showGift() } } }

    /// The gift in the free bottom-right corner of the grid.
    private func showGift() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        giftLayer.contents = gift.map { Self.render(["", "", String(repeating: " ", count: 11) + String($0.symbol)], dark: dark) }
        CATransaction.commit()
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
        case .eating: base = dozing ? .nap1 : .eat
        case .wantsBreak: base = .wave1
        case .happy: base = bigHello ? .happy1 : .hi
        case .napping: base = .nap1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.contents = image(base)
        CATransaction.commit()
        switch mood {
        case .eating where dozing: flip([.nap1, .nap2, .nap3], step: 0.9, repeats: .infinity, key: "loop")
        case .eating: blinkLoop(.eat, .blink)
        case .wantsBreak: flip([.wave1, .wave2], step: 0.4, repeats: .infinity, key: "loop")
        case .happy where bigHello: flip([.happy1, .happy2], step: 0.35, repeats: .infinity, key: "loop")
        case .happy: flip([.hi, .hi, .hi, .wave1], step: 0.4, repeats: .infinity, key: "loop")
        case .napping: flip([.nap1, .nap2, .nap3], step: 0.8, repeats: .infinity, key: "loop")
        }
    }

    override func show(_ new: Mood) {
        guard new != mood else { return }
        mood = new
        applyPose()
        if new == .napping {
            flip([.yawn1, .yawn2, .yawn2, .stretch1, .curl, .curl], step: 0.6)     // yawns and stretches, then lies down
        } else {
            burst()
            if new == .happy, bondLevel >= 2, !paused { tumble() }          // at bond level 2 it shows off a roll
        }
    }

    /// A moment for the current mood, a few seconds long, then back to its loop.
    override func burst() {
        guard !paused, !breathing else { return }
        if dozing != deepFocus { applyPose() }        // just entered or left deep focus
        switch mood {
        case .eating where dozing:
            break                                     // sleeps on: no moments while you focus
        case .eating:
            if let t = temper, Int.random(in: 0..<3) == 0 {        // a third of its moments show today's mood
                switch t {
                case .sleepy: flip([.yawn1, .yawn2, .yawn2, .blink, .eat], step: 0.6)
                case .playful:
                    flip([.giggle1, .giggle2, .giggle1, .eat], step: 0.3)
                    laugh(0.9)
                case .grumpy: flip([.pout, .pout, .eat], step: 0.6)
                case .cuddly: flip([.pet, .pet, .eat], step: 0.6)
                case .curious: flip(cursorSide < 0 ? [.curiousL, .curiousL, .eat] : [.curiousR, .curiousR, .eat], step: 0.6)
                }
                return
            }
            switch Int.random(in: 0..<23) {
            case 0..<13: flip([.eat, .chomp, .eat, .chomp, .eat, .chomp], step: 0.35)
            case 13..<17:
                let look: [Frame] = cursorSide < 0 ? [.lookL, .lookL, .lookL, .eat] : cursorSide > 0 ? [.lookR, .lookR, .lookR, .eat]
                                  : [.lookL, .lookL, .eat, .lookR, .lookR, .eat]
                flip(look, step: 0.5)
            case 17:
                flip([.eat, .sneeze1, .sneeze1, .sneeze2, .sneeze2, .eat], step: 0.4)
                sneezeSpray(after: 1.2)
            case 19: bubble()
            case 20: leaf()
            case 21: butterfly()
            case 18:
                flip([.hiccup, .eat, .eat, .hiccup, .eat], step: 0.4)
                move("transform.translation.y", [0, 4, 0, 0, 0, 4, 0], 2)
            default: flip([.drop1, .drop2, .drop2, .drop1, .eat], step: 0.6)
            }
        case .wantsBreak:                             // acts out the break idea it suggested
            switch tipAct {
            case .stretch: flip([.stretch1, .stretch2, .stretch1, .stretch2], step: 0.6)
            case .gaze: flip([.lookFar, .lookFar, .lookFar, .lookFar, .calm], step: 0.8)
            case .sip: flip([.sip1, .sip2, .sip1, .sip2, .sip1], step: 0.6)
            case .sun: flip([.sun, .sun, .sun, .hi], step: 0.7)
            case .shoulders:
                flip([.stretch1, .talk1, .stretch1, .talk1], step: 0.5)
                move("transform.rotation.z", [0, 0.06, 0, -0.06, 0], 2)
            case .neck:
                flip([.calm, .calm, .calm, .calm], step: 0.6)
                move("transform.rotation.z", [0, 0.14, 0, -0.14, 0], 2.4)
            case .wrists:
                flip([.shake1, .shake2, .shake1, .shake2, .shake1, .shake2, .shake1, .shake2], step: 0.15)
                move("transform.translation.x", [0, -2, 2, -2, 2, -2, 2, 0], 1.2)
            case .palms: flip([.shy, .shy, .shy, .shy, .hi], step: 0.8)
            case .blink: flip([.calm, .talk1, .calm, .talk1, .calm, .talk1], step: 0.5)
            case .walk:
                flip([.wave1, .wave2, .wave1, .wave2, .wave1, .wave2], step: 0.3)
                move("transform.translation.x", [0, -8, 0, 8, 0], 1.8)
            case .breathe: breathe(cycles: 1)
            case .reach:
                flip([.stretch2, .stretch2, .stretch2, .talk1], step: 0.6)
                move("transform.scale.y", [0, 0.08, 0.08, 0], 2.4)
            case .snack: flip([.eat, .chomp, .eat, .chomp, .eat, .chomp], step: 0.35)
            }
            if ![.breathe, .neck, .wrists, .walk].contains(tipAct) { move("transform.translation.y", [0, 6, 0, 6, 0], 1.2) }
        case .happy:
            move("transform.translation.y", lastBreakMinutes >= 30 ? [0, 9, 0, 7, 0, 5, 0] : [0, 5, 0], 1.2)
        case .napping:
            break
        }
    }

    /// A short scene for each moment the brain picks.
    override func cue(_ cue: Cue) {
        guard !paused, !breathing else { return }
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
        if breathing { stopBreathing() }                  // a tap ends the breathing
        switch r {
        case .pet: pet()
        case .highFive:
            flip([.hi5, .hi5, .hi5], step: 0.4)
            sparkles()
            move("transform.translation.y", [0, 6, 0], 0.4)
        case .giggle:
            laugh(1.5)
            flip([.giggle1, .giggle2, .giggle1, .giggle2, .giggle1, .giggle2], step: 0.25)
            move("transform.rotation.z", [0, 0.06, -0.06, 0.06, -0.06, 0], 1.5)
        case .dizzy:
            flip([.dizzy, .dizzy, .dizzy, .dizzy, .dizzy], step: 0.4)
            dizzyStars(2)
            tumble()
        case .shy:
            flip(Array(repeating: .shy, count: 10), step: 1)                     // hides its face for 10 seconds
        case .angry:                                                             // each tap restarts it, so it ends when the taps stop
            flip([.angry1, .angry2, .angry1, .angry2, .angry1, .angry2], step: 0.3)
            steam()
            move("transform.translation.y", [0, 3, 0, 3, 0, 3, 0], 1.8)
        case .pout:
            flip([.pout, .pout, .pout, .pout], step: 0.5)
            move("transform.translation.x", [0, -3, 3, -3, 0], 0.5)
        case .hug:
            floatHearts()
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
            dizzyStars(2)
        case .curious:
            let f: Frame = cursorSide < 0 ? .curiousL : .curiousR
            flip([f, f, f, f], step: 0.5)
        case .grumble: flip([.grumble, .grumble, .grumble, .nap1], step: 0.6)    // one eye opens, then back to sleep
        case .wakeUp: flip([.yawn1, .yawn2, .yawn2, .blink, .eat], step: 0.6)
        case .dance: tideDance()
        case .cheer:
            flip([.cheer, .stretch2, .cheer, .stretch2], step: 0.4)
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        }
    }

    /// A surprise after care or play.
    override func treat(_ t: Treat) {
        guard !paused else { return }
        switch t {
        case .heart:
            flip([.pet, .happy1, .pet, .happy1, .happy1], step: 0.4)
            floatHearts()
            move("transform.translation.y", [0, 6, 0, 6, 0], 1.2)
        case .gift:
            flip([.happy1, .happy2, .happy1, .happy2], step: 0.35)
            move("transform.translation.y", [0, 8, 0], 0.6)
            let a = CABasicAnimation(keyPath: "opacity")              // the gift appears beside it
            a.fromValue = 0
            a.toValue = 1
            a.duration = 1
            giftLayer.add(a, forKey: "appear")
        case .trick(.wave):
            flip([.wave1, .wave2, .wave1, .wave2, .hi], step: 0.35)
            move("transform.translation.y", [0, 5, 0], 0.5)
        case .trick(.roll):
            flip([.happy1, .happy1, .happy2], step: 0.4)
            move("transform.rotation.z", [0, 0.4, 3.14, 5.9, 6.283], 1.2)
        case .trick(.spin):                                             // turns all the way round on the spot
            flip([.hi, .happy1, .happy1, .hi], step: 0.3)
            move("transform.scale.x", [0, -1, -2, -1, 0], 1.2)
        case .trick(.dance):
            tideDance()
        case .trick(.juggle):
            flip([.juggle1, .juggle2, .juggle1, .juggle2, .juggle1, .juggle2, .hi], step: 0.3)
        }
    }

    override func talking(_ on: Bool) {
        if on { flip([.talk1, .talk2], step: 0.18, repeats: .infinity, key: "talk") }
        else { face.removeAnimation(forKey: "talk") }
    }

    /// A little symbol that pops in, moves through `path`, and fades. The compositor runs it, and the layer removes
    /// itself after, so a moment like this costs no CPU while it plays.
    private struct Mote {
        var text: String, size: CGFloat, color: NSColor, path: [CGPoint]
        var delay = 0.0, duration = 1.4, spin: CGFloat = 0, scales: [CGFloat] = [0.3, 1.15, 1], flap = false
    }

    private func motes(_ list: [Mote]) {
        guard !paused else { return }
        let root = stage
        var made: [CALayer] = []
        CATransaction.begin()
        CATransaction.setCompletionBlock { made.forEach { $0.removeFromSuperlayer() } }
        let now = root.convertTime(CACurrentMediaTime(), from: nil)
        for m in list {
            let l = CATextLayer()
            l.string = m.text
            l.font = NSFont.systemFont(ofSize: m.size)
            l.fontSize = m.size
            l.foregroundColor = m.color.cgColor
            l.alignmentMode = .center
            l.contentsScale = (window?.backingScaleFactor ?? 2) * Self.scale
            l.bounds = CGRect(x: 0, y: 0, width: m.size * CGFloat(m.text.count + 1), height: m.size * 1.3)
            l.position = m.path[0]
            l.opacity = 0
            root.addSublayer(l)
            made.append(l)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = m.path.map { NSValue(point: $0) }
            move.calculationMode = .cubic
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.12, 0.75, 1]
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = m.scales
            var all: [CAAnimation] = [move, fade, grow]
            if m.spin != 0 {
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.byValue = m.spin
                all.append(turn)
            }
            if m.flap {                                                      // wings open and close
                let f = CAKeyframeAnimation(keyPath: "transform.scale.x")
                f.values = [1, 0.35, 1]
                f.duration = 0.3
                f.repeatCount = Float(m.duration / 0.3)
                all.append(f)
            }
            let g = CAAnimationGroup()
            g.animations = all
            g.duration = m.duration
            g.beginTime = now + m.delay
            g.fillMode = .backwards
            l.add(g, forKey: "mote")
        }
        CATransaction.commit()
    }

    /// A point on the panda's grid: `col` columns from the left, `y` points up from the bottom.
    private func at(_ col: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: Self.pad + col * Self.cellWidth, y: y) }

    /// One big heart and three small ones rise beside its head and fade.
    private func floatHearts() {
        let pink = Self.fill("♡", dark: dark)
        let hearts: [(CGFloat, CGFloat, CGFloat, Double, CGFloat)] = [(30, 8.8, 24, 0, 0), (15, 7.2, 16, 0.15, -6),
                                                                      (13, 11.4, 30, 0.3, 6), (11, 10.2, 20, 0.5, 2)]
        motes(hearts.map { size, col, y, delay, drift in
            Mote(text: "♥", size: size, color: pink, path: [at(col, y), at(col, y + 34).applying(.init(translationX: drift, y: 0))], delay: delay)
        })
    }

    /// Three stars circle its head, a turn and a half.
    private func dizzyStars(_ seconds: Double) {
        let gold = Self.fill("☆", dark: dark), c = at(3.5, 69)
        motes((0..<3).map { k in
            let path = (0...12).map { i -> CGPoint in
                let a = Double(i) / 8 * 2 * .pi + Double(k) * 2 * .pi / 3
                return CGPoint(x: c.x + 26 * cos(a), y: c.y + 6 * sin(a))
            }
            return Mote(text: "✦", size: 11, color: gold, path: path, duration: seconds, scales: [0.6, 1, 1])
        })
    }

    /// Little steam puffs rise from its ears.
    private func steam() {
        let grey = NSColor(white: 0.6, alpha: 1)
        motes([(1.0, -12.0, 0.0), (5.0, 14.0, 0.25), (1.0, -10.0, 0.5), (5.0, 12.0, 0.75)].map { col, drift, delay in
            Mote(text: "☁", size: 13, color: grey, path: [at(col, 64), at(col, 72).applying(.init(translationX: drift, y: 0))],
                 delay: delay, duration: 0.8, scales: [0.5, 1, 1.3])
        })
    }

    /// Droplets spray from its nose in little arcs and fall.
    func sneezeSpray(after delay: Double) {
        let blue = NSColor(red: 0.45, green: 0.72, blue: 0.98, alpha: 1), nose = at(3.5, 38)
        motes([-34.0, -18, 18, 34, 48].enumerated().map { i, dx in
            let peak = CGPoint(x: nose.x + dx * 0.5, y: nose.y + 10 + CGFloat(i % 2) * 6)
            return Mote(text: "•", size: 9, color: blue, path: [nose, peak, CGPoint(x: nose.x + dx, y: nose.y - 14)],
                        delay: delay, duration: 0.7, scales: [0.6, 1, 0.8])
        })
    }

    /// A burst of sparkles from its raised paw.
    private func sparkles() {
        let gold = Self.fill("☆", dark: dark), paw = at(8.5, 60)
        motes((0..<6).map { i in
            let a = Double(i) / 6 * 2 * .pi + 0.3
            return Mote(text: "✦", size: 9, color: gold, path: [paw, CGPoint(x: paw.x + 16 * cos(a), y: paw.y + 12 * sin(a))],
                        duration: 0.6, scales: [0.3, 1.2, 0.6])
        })
    }

    /// It blows a bubble that grows, drifts up, and pops into specks.
    func bubble() {
        flip([.talk2, .talk2, .talk2, .eat, .eat], step: 0.5)
        let blue = NSColor(red: 0.45, green: 0.72, blue: 0.98, alpha: 1), end = at(8, 62)
        motes([Mote(text: "○", size: 14, color: blue, path: [at(3.5, 36), at(6, 50), end], duration: 1.8, scales: [0.2, 1, 1.8])]
              + (0..<4).map { i in
                  let a = Double(i) / 4 * 2 * .pi + 0.6
                  return Mote(text: "•", size: 7, color: blue, path: [end, CGPoint(x: end.x + 14 * cos(a), y: end.y + 10 * sin(a))],
                              delay: 1.6, duration: 0.4, scales: [1, 1, 0.6])
              })
    }

    /// A bamboo leaf drifts down beside it, and it watches it fall.
    func leaf() {
        flip([.lookR, .lookR, .lookR, .lookR, .lookR, .eat], step: 0.7)
        let green = Self.fill("╪", dark: dark)
        motes([Mote(text: "❦", size: 14, color: green, path: [at(12, 84), at(10.5, 62), at(12, 42), at(10, 22), at(11, 6)],
                    duration: 3.6, spin: 2.5, scales: [1, 1, 1])])
    }

    /// One of its laughs beside its ear for `seconds`, a different one each time.
    private func laugh(_ seconds: Double) {
        guard !paused else { return }
        let word = Self.laughs.randomElement()!
        let image = words[word] ?? Self.render(["        " + word], dark: dark)
        words[word] = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sayLayer.contents = image
        CATransaction.commit()
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 1, 1, 0]
        a.keyTimes = [0, 0.08, 0.85, 1]
        a.duration = seconds
        sayLayer.add(a, forKey: "say")
    }

    /// Breathing together: its body swells as you breathe in for 4 seconds, holds for 4, and settles as you breathe
    /// out for 4, with the word beside it. At the end it is happy with you.
    private var breathEnd: Date?
    private var breathing: Bool { breathEnd.map { Date() < $0 } ?? false }

    override func breathe(cycles: Int) {
        guard !paused, cycles > 0 else { return }
        let cycle = 12.0, total = cycle * Double(cycles)
        breathEnd = Date().addingTimeInterval(total)
        face.removeAnimation(forKey: "burst")
        flip([.calm], step: total, key: "breathe")
        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [0, 0.08, 0.08, 0]
        swell.keyTimes = (0...3).map { NSNumber(value: Double($0) / 3) }
        swell.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
        swell.isAdditive = true
        swell.duration = cycle
        swell.repeatCount = Float(cycles)
        holder.add(swell, forKey: "breathe")
        let said = CAKeyframeAnimation(keyPath: "contents")
        said.values = ["in", "hold", "out"].map { word in words[word] ?? Self.render(["        " + word], dark: dark) }
        said.keyTimes = (0...3).map { NSNumber(value: Double($0) / 3) }
        said.calculationMode = .discrete
        said.duration = cycle
        said.repeatCount = Float(cycles)
        let shown = CABasicAnimation(keyPath: "opacity")
        shown.fromValue = 1
        shown.toValue = 1
        shown.duration = total
        sayLayer.add(said, forKey: "breathe")
        sayLayer.add(shown, forKey: "breatheShown")
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self, self.breathEnd != nil, !self.breathing else { return }
            self.breathEnd = nil
            if cycles > 1 { self.flip([.hi, .hi, .happy1], step: 0.5); self.floatHearts() }
        }
    }

    private func stopBreathing() {
        breathEnd = nil
        face.removeAnimation(forKey: "breathe")
        holder.removeAnimation(forKey: "breathe")
        sayLayer.removeAnimation(forKey: "breathe")
        sayLayer.removeAnimation(forKey: "breatheShown")
    }

    /// The tide: both arms flow over to one side, up, and over to the other, three times, while it sways and notes rise.
    func tideDance() {
        let steps: [Frame] = [.tide2, .tide1, .tide2, .tide3, .tide2, .tide1, .tide2, .tide3, .tide2, .tide1, .tide2, .tide3, .tide2]
        flip(steps + [.hi], step: 0.35)
        // one value per frame, so it leans the way its arms flow: left with the left tide, right with the right
        let lean: [CGFloat] = [0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, 0, 0]
        move("transform.translation.x", lean.map { $0 * 4 }, 0.35 * Double(lean.count - 1))
        move("transform.rotation.z", lean.map { -$0 * 0.05 }, 0.35 * Double(lean.count - 1))
        let purple = Self.fill("♪", dark: dark)
        motes([("♪", 9.0, 0.3), ("♫", 11.0, 1.7), ("♪", 9.5, 3.1)].map { note, col, delay in
            Mote(text: note, size: 14, color: purple, path: [at(col, 34), at(col + 0.6, 52), at(col, 72)], delay: delay, duration: 1.4)
        })
    }

    /// A butterfly flutters in, rests between its ears while it wonders, and flies off.
    func butterfly() {
        flip([.lookR, .lookR, .curiousR, .curiousR, .curiousR, .curiousR, .lookR, .eat], step: 0.6)
        let orange = NSColor(red: 0.95, green: 0.58, blue: 0.2, alpha: 1)
        motes([Mote(text: "ƸӜƷ", size: 12, color: orange,
                    path: [at(14, 40), at(11.5, 58), at(8.5, 50), at(5.5, 74), at(3.2, 70), at(3.0, 69), at(3.3, 70), at(6, 77), at(10, 70), at(15, 77)],
                    duration: 4.8, scales: [1, 1, 1], flap: true)])
    }

    override func pet() {
        move("transform.scale.x", [0, 0.06, -0.02, 0], 0.5)
        move("transform.scale.y", [0, -0.06, 0.02, 0], 0.5)
        flip([.pet, .pet], step: 0.8)
        floatHearts()
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

    /// Writes every frame, and each gift beside the panda, in both modes, over a matching background. Used by `--snapshot`.
    static func writeFrames(to dir: URL) {
        let gifts = Gift.allCases.map { g in
            ("gift-\(g)", art[.eat]!.enumerated().map { $0 == 2 ? $1.padding(toLength: 11, withPad: " ", startingAt: 0) + String(g.symbol) : $1 })
        }
        for dark in [true, false] {
            for (f, img) in Frame.allCases.map({ ("\($0)", draw($0, dark: dark)) }) + gifts.map({ ($0.0, render($0.1, dark: dark)) }) {
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
