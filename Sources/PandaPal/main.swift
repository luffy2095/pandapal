import AppKit
@preconcurrency import UserNotifications

/// The name of the signal `PandaPal --say "…"` sends to the running PandaPal.
let sayNotification = Notification.Name("dev.luffy2095.pandapal.say")

@MainActor
final class PandaApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var brain = Brain()
    var personality = Personality()
    lazy var bubble: SpeechBubble = {
        let b = SpeechBubble()
        b.anchor = self.panel
        b.onClick = { [weak self] in self?.lineAnswered() }     // click a line to put it away
        return b
    }()
    var breaksSeen = -1                 // to notice a break that just ended
    var pinned: String?                 // a message from a script that is showing in the bubble
    var pinTimer: Timer?
    var sayPort: CFMessagePort?                // while it waits for you to come back
    var lineWaiting = false             // one of Bao's own lines is showing: will you answer it?
    var lineTimes: [Date] = []          // its lines in the last hour, at most four
    var bondSeen = -1                   // to notice a new unlock
    var screenLocked = false
    var inCall = false                  // some app is using the camera or recording the microphone
    var asleep = false
    var clumsyUntil: Date?
    var tip = 0
    var timer: Timer?
    var lifeTimer: Timer?
    var panda: PandaShell = TextPandaView(frame: .zero)
    var panel: NSPanel!
    let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PandaPal/memory.json")

    let faces: [Mood: String] = [.eating: "🐼🎋", .wantsBreak: "🐼👋", .happy: "🐼💛", .napping: "🐼💤"]
    var tips: [String] { Words.tips.map(\.text) }

    func applicationDidFinishLaunching(_ note: Notification) {
        load()
        UNUserNotificationCenter.current().delegate = self
        menu.delegate = self
        item.menu = menu
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(lock), name: .init("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(unlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(heard(_:)), name: sayNotification, object: nil)
        // a private port, not a broadcast: other apps cannot read the words, and sandboxed apps cannot send any
        sayPort = CFMessagePortCreateLocal(nil, sayNotification.rawValue as CFString, { _, _, data, _ in
            // 2 KB is ample for 200 characters; a bigger message is cut before any work is done on it
            if let data { NotificationCenter.default.post(name: sayNotification, object: String(decoding: (data as Data).prefix(2048), as: UTF8.self)) }
            return nil
        }, nil, nil)
        if let sayPort { CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, sayPort, 0), .commonModes) }
        // every 15 s: often enough to catch a natural pause; tolerance lets macOS batch the wake-up
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        makePanel()
        let life = Timer(timeInterval: 25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.live() } }
        life.tolerance = 6
        RunLoop.main.add(life, forMode: .common)
        lifeTimer = life
        update()
    }

    /// A transparent floating panel holding the panda. Clicks on empty pixels pass through to whatever is behind.
    func makePanel() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: panda.frame.size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]   // not over full-screen apps
        install(panda)
        placePanda()
        NotificationCenter.default.addObserver(self, selector: #selector(placePanda),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "pandaHidden") { panel.orderFrontRegardless() }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPause),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        refreshPause()
    }

    /// Bao's spot from last time, unless no screen shows it any more (a monitor was unplugged): then the bottom right.
    @objc func placePanda() {
        let size = panel.frame.size
        let saved = UserDefaults.standard.string(forKey: "pandaOrigin").map { NSRect(origin: NSPointFromString($0), size: size) }
        if let saved, NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: saved.midX, y: saved.midY)) }) {
            panel.setFrameOrigin(saved.origin)
        } else if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 20, y: screen.minY + 8))
        }
    }

    func install(_ body: PandaShell) {
        panda = body
        panel.setContentSize(body.frame.size)
        panel.contentView = body
        body.onGesture = { [weak self] g in self?.gesture(g) }
        body.contextMenu = menu
    }

    /// Animations run only while someone can see the panda.
    @objc func refreshPause() {
        guard let panel else { return }
        panda.setPaused(!panel.isVisible || !panel.occlusionState.contains(.visible) || screenLocked || asleep)
    }

    /// Every 25 seconds: a longer moment, but only if someone can see the panda.
    func live() {
        guard panel.isVisible, panel.occlusionState.contains(.visible), !(screenLocked || asleep), !inCall else { return }
        let pointer = NSEvent.mouseLocation, middle = panel.frame.midX     // read only now, never tracked
        panda.cursorSide = abs(pointer.x - middle) < 40 ? 0 : (pointer.x < middle ? -1 : 1)
        panda.burst()
    }

    @objc func sleep() { asleep = true; update(); save(); refreshPause() }
    @objc func wake() { asleep = false; update(); refreshPause() }
    @objc func lock() { screenLocked = true; update(); save(); refreshPause() }
    @objc func unlock() { screenLocked = false; update(); refreshPause() }

    /// Seconds since the last key or mouse event. One system call; it never sees what you type.
    func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func update() {
        let now = Date()
        let idle = idleSeconds()
        inCall = Presence.inCall()
        if inCall, pinned != nil { bubble.hide(after: 0) }   // a script's message leaves before a screen is shared
        let watching = Presence.displayKeptAwake()
        // a call or a video is screen time even without typing; but after 45 minutes untouched you have probably
        // gone, as some tools (caffeinate, Amphetamine) keep the display awake all day
        let busy = (inCall || watching) && idle < 45 * 60
        let before = brain.mood(now)
        if brain.tick(now: now, idle: idle, locked: screenLocked || asleep, busy: busy) { save() }
        let (cue, notify) = brain.decide(now: now, idle: idle, watching: watching, inCall: inCall)
        let treat = brain.takeTreat(idle: idle, r: .random(in: 0..<1), pick: .random(in: 0..<1))   // after a break or eye rest
        if let treat { save() }
        let mood = brain.mood(now)
        if mood == .wantsBreak && before != .wantsBreak {
            tip = Words.nextTip(after: tip, waterDue: brain.waterDue(now), hour: Calendar.current.component(.hour, from: now))
        }
        if mood == .eating, clumsyUntil.map({ now >= $0 }) ?? true, Int.random(in: 0..<40) == 0 {
            clumsyUntil = now.addingTimeInterval(60)
            if panel?.occlusionState.contains(.visible) == true { panda.tumble() }
        }
        panda.focusMinutes = brain.stretchMinutes(now)
        panda.lastBreakMinutes = brain.lastBreakMinutes
        panda.tipAct = Words.tips[tip].act
        panda.bondLevel = brain.bondLevel
        let temper = Temper(rawValue: brain.memory.temper)
        personality.temper = temper
        panda.temper = temper
        panda.show(mood)
        panda.gift = Gift(rawValue: brain.memory.giftToday)
        if let cue, panel?.occlusionState.contains(.visible) == true { panda.cue(cue) }
        if let treat, canBeSeen { panda.treat(treat) }
        if lineWaiting, !bubble.isVisible {                 // the line faded and nobody answered it
            lineWaiting = false
            brain.answered(.line, false)
        }
        // its own words at its moments
        if breaksSeen >= 0, brain.memory.breaksToday > breaksSeen {
            if case .gift(let g)? = treat { say(Words.gift(g)) } else { say(Words.back.randomElement()!) }
        } else if mood == .wantsBreak, before != .wantsBreak {
            say(tips[tip], optional: false)
        }
        if brain.memory.temperDay != brain.memory.day {
            pickTemper(greet: cue == .morning)                 // once a day, and its good morning comes in that mood
        } else if cue == .morning {
            say(Words.morning.randomElement()!)
        }
        if pinned != nil, !bubble.isVisible { pinned = nil }   // the script's message went
        switch cue {
        case .sleepy?: say(Words.late.randomElement()!, optional: false)
        case .reunion?: say(Words.reunion.randomElement()!)
        default: break
        }
        breaksSeen = brain.memory.breaksToday
        celebrate()
        if notify { sendNotification(tips[tip]) }
        let title = isClumsy(now, mood) ? "🐼💫" : faces[mood]!
        if item.button?.title != title { item.button?.title = title }     // redraw the menu bar only on change
    }

    func isClumsy(_ now: Date, _ mood: Mood) -> Bool { mood == .eating && (clumsyUntil.map { now < $0 } ?? false) }

    func menuWillOpen(_ menu: NSMenu) {
        let now = Date()
        let mood = brain.mood(now)
        let line: String
        switch mood {
        case .eating: line = isClumsy(now, mood) ? "Oops. Panda tripped over its own paws." : (brain.stretchMinutes(now) >= 25 ? "Asleep on its side while you focus." : "Munching bamboo while you focus.")
        case .wantsBreak: line = "Panda wants to play. \(tips[tip])"
        case .happy: line = "Panda is happy to see you."
        case .napping: line = "Napping while you are away."
        }
        menu.removeAllItems()
        for text in [line,
                     "Screen time without a break: \(Int(brain.stretchMinutes(now))) min",
                     "Breaks today: \(brain.memory.breaksToday)",
                     "Eye rests today: \(brain.memory.eyeRestsToday)",
                     "Bond: \(brain.memory.bond)" + nextUnlock()] + (brain.memory.temper.isEmpty ? [] : ["Mood today: \(brain.memory.temper)"])
                     + (giftsFound().isEmpty ? [] : ["Gifts found: \(giftsFound())"]) {
            menu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pet the panda", action: #selector(pet), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Breathe with Bao (1 minute)", action: #selector(breathe), keyEquivalent: "").target = self
        if let until = brain.snoozeUntil, now < until {
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            menu.addItem(withTitle: "Break reminders snoozed until \(time). Resume", action: #selector(resume), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Snooze break reminders for 1 hour", action: #selector(snooze), keyEquivalent: "").target = self
        }
        let hidden = UserDefaults.standard.bool(forKey: "pandaHidden")
        menu.addItem(withTitle: hidden ? "Show panda on screen" : "Hide panda from screen", action: #selector(toggleHidden), keyEquivalent: "").target = self
        let sizes = NSMenu()
        for (name, scale) in [("Small", 0.75), ("Normal", 1.0), ("Large", 1.3)] {
            let choice = sizes.addItem(withTitle: name, action: #selector(resize(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = scale
            choice.state = TextPandaView.scale == CGFloat(scale) ? .on : .off
        }
        let size = menu.addItem(withTitle: "Size", action: nil, keyEquivalent: "")
        size.submenu = sizes
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PandaPal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func pet() { gesture(.tap) }
    @objc func breathe() { panda.breathe(cycles: 5) }

    /// Your mouse, through the panda's personality. Affection makes it happy for a minute.
    func gesture(_ g: Gesture) {
        let now = Date()
        if g == .hover, let panel {
            let pointer = NSEvent.mouseLocation
            panda.cursorSide = pointer.x < panel.frame.midX ? -1 : 1
        }
        guard let reaction = personality.react(g, mood: brain.mood(now), now: now) else { return }
        if [.pet, .hug, .highFive].contains(reaction) {
            brain.pet(now)
            update()
            if bubble.isVisible { lineAnswered() }          // petting Bao while it speaks answers it too
        }
        panda.react(reaction)
        if [.pet, .hug, .highFive, .giggle, .dance].contains(reaction) { play(now) }
    }

    /// Play sometimes brings a small surprise, shown once the reaction is over.
    func play(_ now: Date) {
        guard let t = brain.played(now, chance: .random(in: 0..<1), r: .random(in: 0..<1), pick: .random(in: 0..<1)) else { return }
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.panda.treat(t)
            self?.celebrate()
        }
    }

    /// Bond reached a new unlock: Bao shows off a new trick at once, or says it can find a new gift.
    func celebrate() {
        let bond = brain.memory.bond
        defer { bondSeen = bond }
        guard bondSeen >= 0, let u = Rewards.newly(from: bondSeen, to: bond).last else { return }
        switch u {
        case .trick(let t):
            if canBeSeen { panda.treat(.trick(t)) }
            say(Words.trick(t), optional: false)
        case .gift(let g):
            say(Words.newGift(g), optional: false)
        }
    }

    /// The menu names what the next unlock is, but not which one, so it stays a surprise.
    func nextUnlock() -> String {
        guard let n = Rewards.next(brain.memory.bond) else { return "" }
        if case .trick = n.unlock { return " (a new trick at \(n.bond))" }
        return " (a new gift at \(n.bond))"
    }

    func giftsFound() -> String {
        Gift.allCases.compactMap { g in brain.memory.gifts[g.rawValue].map { "\(g.symbol) \($0)" } }.joined(separator: "   ")
    }

    /// You answered Bao's own line: it will keep saying lines like it.
    func lineAnswered() {
        guard lineWaiting else { return }
        lineWaiting = false
        brain.answered(.line, true)
        save()
    }

    @objc func toggleHidden() {
        let hide = !UserDefaults.standard.bool(forKey: "pandaHidden")
        UserDefaults.standard.set(hide, forKey: "pandaHidden")
        if hide { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        refreshPause()
    }
    /// A new panda body at the chosen size, in the same spot.
    @objc func resize(_ choice: NSMenuItem) {
        guard let scale = choice.representedObject as? Double, CGFloat(scale) != TextPandaView.scale else { return }
        UserDefaults.standard.set(scale, forKey: "pandaScale")
        TextPandaView.scale = CGFloat(scale)
        install(TextPandaView(frame: .zero))
        update()
        refreshPause()
    }
    @objc func snooze() { brain.snoozeUntil = Date().addingTimeInterval(3600); update() }
    @objc func resume() { brain.snoozeUntil = nil; update() }

    /// The one break notification at the top of the escalation, and the backup for a message nobody could see.
    /// macOS asks for permission the first time.
    func sendNotification(_ body: String, title: String = "Your panda wants to play", id: String = "break", sound: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func applicationWillTerminate(_ note: Notification) { save() }

    func load() {
        if let data = try? Data(contentsOf: store), let memory = try? JSONDecoder().decode(Memory.self, from: data) {
            brain.memory = memory
        }
    }

    // MARK: words

    /// The face Bao ends a line with, from its mood and the hour.
    func face() -> String {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 23 || hour < 5 { return "(˘ᴥ˘)" }
        switch brain.mood(now) {
        case .happy: return "(ᵔᴥᵔ)"
        case .napping: return "(˘ᴥ˘)"
        default: return "(●ᴥ●)"
        }
    }

    /// The point above Bao's head, on screen, where every bubble's tail points.
    func head() -> NSPoint {
        NSPoint(x: panel.frame.minX + panda.headPoint.x, y: panel.frame.minY + panda.headPoint.y)
    }

    /// One of Bao's lines in its bubble: at most four an hour, only when someone can see it, never during a call,
    /// and never over a message a script sent. An `optional` line comes less often when you keep ignoring Bao's lines; break asks
    /// and bedtime are never optional.
    func say(_ text: String, optional: Bool = true) {
        let now = Date()
        lineTimes = lineTimes.filter { now.timeIntervalSince($0) < 3600 }
        guard canBeSeen, !inCall, lineTimes.count < 4, pinned == nil else { return }
        if optional, !brain.wants(.line, r: .random(in: 0..<1)) { return }
        lineTimes.append(now)
        speak("\(text) \(face())")
        lineWaiting = optional
    }

    /// Someone could see the panda right now.
    var canBeSeen: Bool {
        guard let panel else { return false }
        return panel.isVisible && panel.occlusionState.contains(.visible) && !screenLocked && !asleep
    }

    /// Bao's line in her bubble, mouth moving as it appears.
    func speak(_ line: String, seconds: Double = 9) {
        lineWaiting = false                   // a new line replaces the one waiting for an answer
        bubble.show(line, head: head(), seconds: seconds)
        Task { @MainActor in
            panda.talking(true)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            panda.talking(false)
        }
    }

    /// A script sent words with `PandaPal --say "…"`. Bao waves and says them. The bubble goes 15 seconds after you
    /// are at your Mac: at once if you are, or once you move the mouse or type if you were away. A click puts it away
    /// sooner. When nobody can see Bao, a notification carries the words instead.
    @objc func heard(_ note: Notification) {
        guard let raw = note.object as? String, let text = Words.said(raw) else { return }
        // in a call your screen may be shared; macOS keeps notifications off a shared screen by default
        guard canBeSeen, !Presence.inCall() else {
            sendNotification(text, title: "Bao says", id: UUID().uuidString, sound: true)
            return
        }
        let line = "\(text) \(face())"
        panda.cue(.remind)
        speak(line, seconds: 3600)
        bubble.nudge()
        pinned = line
        pinTimer?.invalidate()
        // once a second, only while the message waits: the first sign of you starts its last 15 seconds
        pinTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.pinned == line, self.bubble.isVisible else { timer.invalidate(); return }
                guard self.idleSeconds() < 2 else { return }
                timer.invalidate()
                self.bubble.hide(after: 15)
            }
        }
    }

    /// Once a day: Bao's mood, from how your last day went, and a good morning in that mood.
    func pickTemper(greet: Bool) {
        let m = brain.memory
        let t = Temper.pick(lastDayBreaks: m.lastDayBreaks, lastDayLongest: m.lastDayLongest, lastDayEnd: m.lastDayEnd,
                            yesterday: Temper(rawValue: m.temper), day: Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0)
        brain.memory.temper = t.rawValue
        brain.memory.temperDay = brain.memory.day
        save()
        personality.temper = t
        panda.temper = t
        if greet, let hello = Words.mood[t] { say(hello) }
    }

    func save() {
        try? FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(brain.memory).write(to: store, options: .atomic)
    }
}

/// Shows notifications as banners even while PandaPal is the active app.
extension PandaApp: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--say") {
    // `PandaPal --say "Build finished!"` hands the words to the running PandaPal, which says them, and exits.
    let text = CommandLine.arguments.dropFirst(i + 1).joined(separator: " ")
    guard Words.said(text) != nil else {
        FileHandle.standardError.write(Data("Usage: PandaPal --say \"what Bao should say\"\n".utf8))
        exit(2)
    }
    guard let port = CFMessagePortCreateRemote(nil, sayNotification.rawValue as CFString),
          CFMessagePortSendRequest(port, 0, Data(text.utf8) as CFData, 1, 0, nil, nil) == kCFMessagePortSuccess else {
        FileHandle.standardError.write(Data("PandaPal is not running.\n".utf8))
        exit(1)
    }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    // Renders every frame of the art to PNGs and exits: a way to check it without a screen.
    TextPandaView.writeFrames(to: URL(fileURLWithPath: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "."))
    exit(0)
}

// The program's entry point runs on the main thread; Swift 6.4 wants that said explicitly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = PandaApp()         // app.delegate is weak; this keeps it alive while the app runs
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
