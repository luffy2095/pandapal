import AppKit
import Lottie
import QuartzCore

/// The on-screen panda. Art: "Panda Waving" by Bhaskar Wary and "Sleep Panda" by Zakaria Harry Utomo,
/// from LottieFiles under the Lottie Simple License. Animations play in short moments and stop in
/// between, so the screen is still most of the time and costs nothing.
final class PandaView: PandaShell {
    static let size = NSSize(width: 170, height: 170)
    static let idleRate = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)

    let holder = CALayer()                 // bottom anchor: breathing, squish, hops; tumble rotates it
    let art: LottieAnimationLayer
    let heart = CATextLayer(), bubble = CATextLayer()
    let calm: LottieAnimation?             // working: paw held still, tongue still pops out
    let wave: LottieAnimation?             // the full waving animation
    let sleep: LottieAnimation?

    private var paused = false
    private(set) var mood: Mood = .eating

    init(frame: NSRect, engine: RenderingEngineOption = .automatic) {
        wave = Self.load("working")
        calm = Self.load("working", freeze: "Hand")
        // drop its solid blue background square; navy Zs stay visible on light desktops
        sleep = Self.load("sleeping", hide: "BG Outlines", textColor: [0.05, 0.05, 0.45])
        art = LottieAnimationLayer(animation: calm, configuration: LottieConfiguration(renderingEngine: engine))
        super.init(frame: frame)
        wantsLayer = true
        build()
        startIdle()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Loads an animation from the app's Resources, or from ./Art when run from the repo.
    /// `freeze` names a layer whose animated transform is pinned to its first keyframe; `hide` a layer to drop.
    static func load(_ name: String, freeze: String? = nil, hide: String? = nil, textColor: [Double]? = nil) -> LottieAnimation? {
        let candidates = [Bundle.main.url(forResource: name, withExtension: "json"),
                          URL(fileURLWithPath: "Art/\(name).json")]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              var data = try? Data(contentsOf: url) else { return nil }
        if freeze != nil || hide != nil || textColor != nil, var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var layers = json["layers"] as? [[String: Any]] {
            layers.removeAll { hide != nil && $0["nm"] as? String == hide }
            for i in layers.indices where textColor != nil && layers[i]["ty"] as? Int == 5 {
                if var t = layers[i]["t"] as? [String: Any], var d = t["d"] as? [String: Any], var ks = d["k"] as? [[String: Any]] {
                    for j in ks.indices { if var st = ks[j]["s"] as? [String: Any] { st["fc"] = textColor; ks[j]["s"] = st } }
                    d["k"] = ks; t["d"] = d; layers[i]["t"] = t
                }
            }
            for i in layers.indices where layers[i]["nm"] as? String == freeze {
                if var ks = layers[i]["ks"] as? [String: Any] {
                    for (key, value) in ks {
                        guard var prop = value as? [String: Any], prop["a"] as? Int == 1,
                              let first = (prop["k"] as? [[String: Any]])?.first, let s = first["s"] else { continue }
                        prop["a"] = 0
                        prop["k"] = (s as? [Any]).flatMap { $0.count == 1 ? $0[0] : $0 } ?? s
                        ks[key] = prop
                    }
                    layers[i]["ks"] = ks
                }
            }
            json["layers"] = layers
            data = (try? JSONSerialization.data(withJSONObject: json)) ?? data
        }
        return try? LottieAnimation.from(data: data)
    }

    private func build() {
        let base = layer!
        holder.bounds = CGRect(origin: .zero, size: Self.size)
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.position = CGPoint(x: Self.size.width / 2, y: 0)
        base.addSublayer(holder)

        // The art is 1080 x 1080. Draw it at that size and scale the layer down to fit.
        art.bounds = CGRect(x: 0, y: 0, width: 1080, height: 1080)
        art.position = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        art.setAffineTransform(CGAffineTransform(scaleX: Self.size.width / 1080, y: Self.size.height / 1080))
        art.isGeometryFlipped = true          // Lottie draws y-down, as on iOS
        holder.addSublayer(art)
        fitArt()
        art.currentFrame = 0

        let pink = NSColor(red: 1, green: 0.5, blue: 0.62, alpha: 1)
        text(heart, "♥", CGRect(x: 70, y: 140, width: 30, height: 30), size: 24, color: pink)
        text(bubble, "break?", CGRect(x: 0, y: 140, width: 60, height: 22), size: 12, color: NSColor(white: 0.1, alpha: 1))
        bubble.backgroundColor = NSColor.white.cgColor
        bubble.cornerRadius = 9
        bubble.borderColor = NSColor(white: 0.8, alpha: 1).cgColor
        bubble.borderWidth = 1
        holder.addSublayer(bubble)
        holder.addSublayer(heart)
    }

    /// The bare Lottie layer leaves its inner animation layer centred on (0, 0). Centre it on the art.
    /// Run again after every animation change, because Lottie replaces that inner layer.
    private func fitArt() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in art.sublayers ?? [] { l.position = CGPoint(x: art.bounds.midX, y: art.bounds.midY) }
        CATransaction.commit()
    }

    private func text(_ l: CATextLayer, _ s: String, _ frame: CGRect, size: CGFloat, color: NSColor) {
        l.string = s
        l.frame = frame
        l.fontSize = size
        l.foregroundColor = color.cgColor
        l.alignmentMode = .center
        l.contentsScale = 2
        l.opacity = 0
    }

    // MARK: motion

    private func animate(_ l: CALayer, _ key: String, _ values: [CGFloat], _ duration: Double,
                         repeats: Float = 1, additive: Bool = true, idle: Bool = false) {
        let a = CAKeyframeAnimation(keyPath: key)
        a.values = values
        a.duration = duration
        a.repeatCount = repeats
        a.isAdditive = additive
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if idle { a.preferredFrameRateRange = Self.idleRate }
        l.add(a, forKey: (idle ? "idle " : "burst ") + key)
    }

    /// Gentle breathing while working. The sleeping art already breathes, so it gets none.
    func startIdle() {
        if mood == .napping {
            holder.removeAnimation(forKey: "idle transform.scale.y")
        } else {
            animate(holder, "transform.scale.y", [0, 0.015, 0], 3.4, repeats: .infinity, idle: true)
        }
    }

    /// Switches the art for a mood and plays its moment.
    override func show(_ new: Mood) {
        guard new != mood else { return }
        mood = new
        art.stop()
        art.animation = new == .napping ? sleep : (new == .eating ? calm : wave)
        fitArt()
        art.currentFrame = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.opacity = new == .wantsBreak ? 1 : 0
        CATransaction.commit()
        startIdle()
        if new == .napping, !paused { art.play(fromFrame: 0, toFrame: 120, loopMode: .loop) }
        burst()
    }

    /// A moment for the current mood, then stillness until the next one.
    override func burst() {
        guard !paused else { return }
        switch mood {
        case .eating:
            art.play(fromFrame: 30, toFrame: 125, loopMode: .playOnce)            // the tongue pops out twice
        case .wantsBreak:
            art.play(fromFrame: 0, toFrame: 150, loopMode: .repeat(2))
            animate(holder, "transform.translation.y", [0, 7, 0, 7, 0], 1.3)
            animate(bubble, "transform.scale", [0, 0.1, 0, 0.1, 0], 1.3)
        case .happy:
            art.animationSpeed = 1.5
            art.play(fromFrame: 0, toFrame: 150, loopMode: .playOnce) { [weak self] _ in self?.art.animationSpeed = 1 }
            animate(holder, "transform.translation.y", [0, 9, 0, 6, 0], 0.9)
            floatUp(heart)
        case .napping:
            break                                                                  // the sleep loop runs on its own
        }
    }

    override func pet() {
        animate(holder, "transform.scale.x", [0, 0.08, -0.03, 0], 0.5)            // squish
        animate(holder, "transform.scale.y", [0, -0.07, 0.03, 0], 0.5)
        floatUp(heart)
        if mood == .eating, !paused { art.play(fromFrame: 36, toFrame: 60, loopMode: .playOnce) }   // cheeky tongue
    }

    /// Clumsy: rolls over.
    /// The cartoon panda has fewer moves, so reactions map onto the ones it has.
    override func react(_ r: Reaction) {
        switch r {
        case .pet, .highFive, .giggle, .hug, .cheer, .curious: pet()
        case .dizzy, .dizzyDrop: tumble()
        default: break
        }
    }

    override func tumble() {
        animate(holder, "transform.rotation.z", [0, 0.5, 3.14, 5.8, 6.283], 1.2)
    }

    private func floatUp(_ l: CALayer) {
        animate(l, "transform.translation.y", [0, 24], 1.4)
        animate(l, "opacity", [0, 1, 1, 0], 1.4, additive: false)
    }

    /// Stops all motion while nobody can see the panda.
    override func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p {
            art.pause()
            let t = holder.convertTime(CACurrentMediaTime(), from: nil)
            holder.speed = 0
            holder.timeOffset = t
        } else {
            let t = holder.timeOffset
            holder.speed = 1
            holder.timeOffset = 0
            holder.beginTime = 0
            holder.beginTime = holder.convertTime(CACurrentMediaTime(), from: nil) - t
            if mood == .napping { art.play(fromFrame: 0, toFrame: 120, loopMode: .loop) }
        }
    }

    // MARK: previews without a screen

    /// Renders one frame of one animation to a PNG at 3x, on a light background. Needs the main-thread engine.
    func writePNG(_ animation: LottieAnimation?, frame: AnimationFrameTime, to url: URL) {
        art.animation = animation
        fitArt()
        art.currentFrame = frame
        art.forceDisplayUpdate()
        let scale: CGFloat = 3
        let w = Int(Self.size.width * scale), h = Int(Self.size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(NSColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        layer!.render(in: ctx)
        if let img = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
