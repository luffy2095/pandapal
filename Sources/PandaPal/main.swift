import AppKit
@preconcurrency import UserNotifications

@MainActor
final class PandaApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var brain = Brain()
    var personality = Personality()
    let companion = Companion()
    var chat: ChatPanel?
    lazy var bubble: SpeechBubble = {
        let b = SpeechBubble()
        b.anchor = self.panel
        b.onClick = { [weak self] in self?.lineAnswered(); self?.answer(b.text) }     // click a line to answer it
        return b
    }()
    lazy var invite: TalkInvite = {
        let c = TalkInvite()
        c.anchor = self.panel
        c.bubble.onClick = { [weak self] in self?.invite.orderOut(nil); self?.openChat() }
        c.bubble.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        return c
    }()
    var breaksSeen = -1                 // to notice a break that just ended
    var reminderShown: Date?            // a reminder bubble waiting for your click, and how often it has waved since
    var reminderNudges = 0
    var replying = false                // Bao is answering in the chat
    var momentUntil = Date.distantPast  // Bao is playing a moment until then, and "talk?" waits
    var lineWaiting = false             // one of Bao's own lines is showing: will you answer it?
    var bondSeen = -1                   // to notice a new unlock
    var screenLocked = false
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
    let tips = [
        "Stand up and stretch with the panda.",
        "Look at something far away for 20 seconds.",
        "Drink some water. Panda is having bamboo.",
        "Step outside for a minute of daylight.",
        "Roll your shoulders. Pandas roll everything.",
    ]

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
        if let saved = UserDefaults.standard.string(forKey: "pandaOrigin") {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panda.frame.width - 20, y: screen.minY + 8))
        }
        if !UserDefaults.standard.bool(forKey: "pandaHidden") { panel.orderFrontRegardless() }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPause),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        refreshPause()
    }

    func install(_ body: PandaShell) {
        panda = body
        panel.setContentSize(body.frame.size)
        panel.contentView = body
        body.onGesture = { [weak self] g in self?.gesture(g) }
        body.onHoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        body.contextMenu = menu
        body.onMoment = { [weak self] seconds in self?.momentStarted(seconds) }
    }


    /// Animations run only while someone can see the panda.
    @objc func refreshPause() {
        guard let panel else { return }
        panda.setPaused(!panel.isVisible || !panel.occlusionState.contains(.visible) || screenLocked || asleep)
    }

    /// Every 25 seconds: a longer moment, but only if someone can see the panda.
    func live() {
        guard panel.isVisible, panel.occlusionState.contains(.visible), !(screenLocked || asleep) else { return }
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
        let before = brain.mood(now)
        if brain.tick(now: now, idle: idle, locked: screenLocked || asleep) { save() }
        let (cue, notify) = brain.decide(now: now, idle: idle)
        let treat = brain.takeTreat(idle: idle, r: .random(in: 0..<1), pick: .random(in: 0..<1))   // after a break or eye rest
        if let treat { save() }
        let mood = brain.mood(now)
        if mood == .wantsBreak && before != .wantsBreak {
            // water when it is due, otherwise the next of the other tips
            let water = tips.firstIndex { $0.contains("water") }!
            tip = brain.waterDue(now) ? water : (tip + 1 == water ? tip + 2 : tip + 1) % tips.count
        }
        if mood == .eating, clumsyUntil.map({ now >= $0 }) ?? true, Int.random(in: 0..<40) == 0 {
            clumsyUntil = now.addingTimeInterval(60)
            if panel?.occlusionState.contains(.visible) == true { panda.tumble() }
        }
        panda.focusMinutes = brain.stretchMinutes(now)
        panda.lastBreakMinutes = brain.lastBreakMinutes
        panda.waterTip = tips[tip].contains("water")
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
            var moment = "The user just came back from a \(Int(brain.lastBreakMinutes))-minute break."
            if case .gift(let g)? = treat { moment += " You found a little \(g.rawValue) for them, and you give it to them now." }
            say(moment)
        } else if mood == .wantsBreak, before != .wantsBreak {
            say("You want the user to take a break now. Suggest this: \(tips[tip])", optional: false)
        }
        if brain.memory.temperDay != brain.memory.day {
            pickTemper(greet: cue == .morning)                 // once a day, and its first words come in that mood
        } else if cue == .morning {
            say("It is the user's first visit today. Say good morning.")
        }
        let due = brain.takeDue(now)
        if !due.isEmpty { deliver(due, now); save() }
        if let shown = reminderShown {                       // an unclicked reminder waves again each minute, 3 times at most
            if !bubble.isVisible || reminderNudges >= 3 {
                reminderShown = nil
            } else if now.timeIntervalSince(shown) >= 60 * Double(reminderNudges + 1), canBeSeen {
                bubble.nudge()
                panda.cue(.remind)
                reminderNudges += 1
            }
        }
        switch cue {
        case .sleepy?: say("It is late at night. Encourage the user to wrap up and sleep.", optional: false)
        case .reunion?: say("The user is back after days away. You missed them.")
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
        if Companion.available {
            menu.addItem(withTitle: "Talk to Bao…", action: #selector(openChat), keyEquivalent: "").target = self
        } else {
            menu.addItem(NSMenuItem(title: "Talk to Bao (needs Apple Intelligence)", action: nil, keyEquivalent: ""))
        }
        if let until = brain.snoozeUntil, now < until {
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            menu.addItem(withTitle: "Break reminders snoozed until \(time). Resume", action: #selector(resume), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Snooze break reminders for 1 hour", action: #selector(snooze), keyEquivalent: "").target = self
        }
        let hidden = UserDefaults.standard.bool(forKey: "pandaHidden")
        menu.addItem(withTitle: hidden ? "Show panda on screen" : "Hide panda from screen", action: #selector(toggleHidden), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PandaPal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func pet() { gesture(.tap) }

    /// Your mouse, through the panda's personality. Affection makes it happy for a minute; none of it earns bond.
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
            say("You just learned a new trick: \(t.rawValue). Tell the user proudly.", optional: false)
        case .gift(let g):
            say("From now on you can find a new kind of gift for the user: a \(g.rawValue). Tell them, excited.", optional: false)
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
    @objc func snooze() { brain.snoozeUntil = Date().addingTimeInterval(3600); update() }
    @objc func resume() { brain.snoozeUntil = nil; update() }

    /// The one break notification at the top of the escalation, and the backup for a reminder nobody could see.
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

    // MARK: companion

    /// What Bao knows: the time and its own world. Never apps, files or screen contents.
    func context() -> String {
        let now = Date()
        let clock = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        let doing: [Mood: String] = [.eating: "munching bamboo", .wantsBreak: "waiting for the user to take a break",
                                     .happy: "happy", .napping: "napping"]
        return "It is \(clock). The user has been at the screen \(Int(brain.stretchMinutes(now))) minutes without a break. "
             + "Breaks today: \(brain.memory.breaksToday). Eye rests today: \(brain.memory.eyeRestsToday). "
             + "Bao is \(doing[brain.mood(now)]!). Bond: \(brain.memory.bond)."
             + (brain.memory.temper.isEmpty ? "" : " Today Bao feels \(brain.memory.temper).")
    }

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

    /// "talk?" steps aside while Bao plays a moment, and comes back after the last one if the pointer is still there.
    func momentStarted(_ seconds: Double) {
        let until = Date().addingTimeInterval(seconds)
        guard until > momentUntil else { return }
        momentUntil = until
        invite.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, let panel = self.panel, Date() >= self.momentUntil, panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.hoverChanged(true)
        }
    }

    /// "talk?" appears above Bao while the pointer is on the panda or on the bubble, and goes as soon as it is on neither.
    func hoverChanged(_ inside: Bool) {
        guard inside else {
            // hide once the pointer is off both the panda and the bubble; checked a moment later, because moving
            // up from the panda into the bubble leaves the one before it enters the other
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let p = NSEvent.mouseLocation
                if self.panel?.frame.contains(p) != true, !self.invite.frame.contains(p) { self.invite.orderOut(nil) }
            }
            return
        }
        guard Companion.available, chat?.isVisible != true, !bubble.isVisible, panel != nil, Date() >= momentUntil else { return }
        invite.show(head: head())
        DispatchQueue.main.async { [weak self] in _ = self?.chatPanel() }   // after the bubble is on screen
    }

    func answer(_ line: String) {
        openChat()
        companion.heard(line)
        chat?.set(line)
    }

    /// The chat window, made once. The first focus of its text field takes macOS about a second (measured 1.1 to 2.5 s),
    /// so the "talk?" bubble makes it early, while the window is still hidden.
    func chatPanel() -> ChatPanel {
        if let chat { return chat }
        let c = ChatPanel()
        c.anchor = panel
        c.onSend = { [weak self] text in self?.send(text) }
        NotificationCenter.default.addObserver(self, selector: #selector(chatClosed), name: NSWindow.willCloseNotification, object: c)
        NotificationCenter.default.addObserver(self, selector: #selector(chatLostFocus), name: NSWindow.didResignKeyNotification, object: c)
        c.makeFirstResponder(c.input)
        chat = c
        return c
    }

    @objc func openChat() {
        let c = chatPanel()
        companion.startChat(mood: Temper(rawValue: brain.memory.temper)) { [weak self] act in await self?.perform(act) ?? "" }
        invite.orderOut(nil)
        c.open(head: head(), reply: "Hi! Ask me anything, or ask me to remind you of something. (●ᴥ●)")
        NSApp.activate(ignoringOtherApps: true)
        c.makeKeyAndOrderFront(nil)
        c.makeFirstResponder(c.input)
        c.pop()
    }

    /// A click outside the chat closes it, unless Bao is still answering: then the reply waits there and waves.
    @objc func chatLostFocus() { if !replying { chat?.close() } }

    @objc func chatClosed() {
        companion.endChat()                   // the conversation is gone; nothing was saved
        panda.talking(false)
    }

    func send(_ text: String) {
        guard let chat else { return }
        chat.asked = text
        chat.set("…")
        panda.thinking()
        let sent = Date()
        replying = true
        Task { @MainActor in
            defer { replying = false }
            var started = false
            _ = await companion.reply(to: text, face: face()) { [weak self] partial in
                if !started { started = true; self?.panda.talking(true) }
                chat.set(partial)
            }
            panda.talking(false)
            if Date().timeIntervalSince(sent) >= 4 || !chat.isKeyWindow {     // you may have looked away: catch your eye
                chat.nudge()
                panda.cue(.remind)
            }
            play(Date())                                                      // a chat is play too
        }
    }

    /// A short line in a speech bubble for one of the panda's moments, unless the chat is open or nobody can see it.
    /// An `optional` line comes less often when you keep ignoring Bao's lines; break asks and bedtime are never optional.
    func say(_ moment: String, optional: Bool = true) {
        guard Companion.available, canBeSeen, chat?.isVisible != true else { return }
        if optional, !brain.wants(.line, r: .random(in: 0..<1)) { return }
        let ctx = context()
        Task { @MainActor in
            guard let line = await companion.line(for: moment, context: ctx, mood: personality.temper, face: face()) else { return }
            speak(line)
            lineWaiting = optional
        }
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

    /// Bao says due reminders herself: in the open chat, or waving in her bubble until you click it. When nobody
    /// can see her (hidden, under a full-screen app, screen locked), a notification carries them, so none is missed.
    func deliver(_ due: [Reminder], _ now: Date) {
        let text = due.map { r in
            now.timeIntervalSince(r.at) > 120 ? "(\(DateFormatter.localizedString(from: r.at, dateStyle: .none, timeStyle: .short))) \(r.text)" : r.text
        }.joined(separator: "\n")
        if let chat, chat.isVisible {
            chat.asked = nil
            chat.set(text + " " + face())
        } else if canBeSeen {
            panda.cue(.remind)
            speak(text + " " + face(), seconds: 3600)
            bubble.nudge()
            reminderShown = now
            reminderNudges = 0
        } else {
            sendNotification(text, title: "Bao's reminder", id: UUID().uuidString, sound: true)
        }
    }

    /// Once a day: Bao's mood, from how your last day went. Apple's model greets you in it.
    func pickTemper(greet: Bool) {
        let m = brain.memory
        let t = Temper.pick(lastDayBreaks: m.lastDayBreaks, lastDayLongest: m.lastDayLongest, lastDayEnd: m.lastDayEnd,
                            yesterday: Temper(rawValue: m.temper), day: Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0)
        brain.memory.temper = t.rawValue
        brain.memory.temperDay = brain.memory.day
        save()
        personality.temper = t
        panda.temper = t
        guard greet else { return }
        var lastTime = ""
        if let end = m.lastDayEnd {
            lastTime = " Last time the user took \(m.lastDayBreaks) breaks, their longest stretch was \(m.lastDayLongest) minutes, "
                     + "and they left at \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))."
        }
        say("It is the user's first visit today, and today you feel \(t.rawValue). Say good morning in that mood.\(lastTime)")
    }

    /// Does what Bao was asked in the chat, and returns what to tell the model.
    func perform(_ act: Act) async -> String {
        switch act {
        case .day:
            let now = Date()
            return "Screen time since the last break: \(Int(brain.stretchMinutes(now))) minutes. Breaks today: \(brain.memory.breaksToday). "
                 + "Eye rests today: \(brain.memory.eyeRestsToday). Longest time without a break today: \(brain.memory.longestStretchMinutes) minutes."
        case .snooze(let minutes):
            brain.snoozeUntil = Date().addingTimeInterval(Double(minutes) * 60)
            update()
        case .focus(let minutes):
            brain.snoozeUntil = Date().addingTimeInterval(Double(minutes) * 60)
            brain.memory.reminders.append(Reminder(text: "Focus time is up! Stand up and stretch for 5 minutes.", at: brain.snoozeUntil!))
            save()
            check(at: brain.snoozeUntil!)
            update()
        case .remind(let what, let at):
            brain.memory.reminders.append(Reminder(text: "Psst! Time to \(what).", at: at))
            save()
            check(at: at)
        case .weather:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather")
            else { return "✗ The Weather app is not on this Mac." }
            guard (try? await NSWorkspace.shared.openApplication(at: app, configuration: .init())) != nil
            else { return "✗ The Weather app did not open." }
        }
        return Companion.receipt(act)
    }

    /// Looks for due reminders at `date`, so a short one arrives on time, not at the next 15-second tick.
    func check(at date: Date) {
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        RunLoop.main.add(t, forMode: .common)
    }

    func save() {
        try? FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(brain.memory).write(to: store, options: .atomic)
    }
}

/// Shows notifications as banners even while PandaPal is the active app, as when the chat is open.
extension PandaApp: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--ask"), CommandLine.arguments.count > i + 1 {
    // Talks to Bao from the terminal: --ask "message" ["next message" ...] is one chat; actions are only printed.
    // --ask --moment "moment" ["context" ["mood"]] asks for one of its bubble lines.
    let args = Array(CommandLine.arguments[(i + 1)...])
    Task { @MainActor in
        let c = Companion()
        if args.first == "--moment", args.count > 1 {
            let context = args.count > 2 ? args[2] : "It is 15:20. The user has been at the screen 58 minutes without a break."
            let t = Date()
            let answer = await c.line(for: args[1], context: context, mood: args.count > 3 ? Temper(rawValue: args[3]) : nil)
            print(String(format: "[%.1fs] ", Date().timeIntervalSince(t)) + (answer ?? "(no answer)"))
            exit(0)
        }
        c.startChat { act in
            print("[act] \(act)")
            if case .day = act { return "Screen time since the last break: 30 minutes. Breaks today: 4. Eye rests today: 2. Longest time without a break today: 55 minutes." }
            return Companion.receipt(act)
        }
        for text in args {
            let t = Date()
            var first: Double?
            let answer = await c.reply(to: text) { _ in if first == nil { first = Date().timeIntervalSince(t) } }
            print("> \(text)\n" + String(format: "[first words %.1fs, done %.1fs] ", first ?? -1, Date().timeIntervalSince(t)) + answer + "\n")
        }
        exit(0)
    }
    RunLoop.main.run()
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
