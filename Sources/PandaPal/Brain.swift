import Foundation

enum Mood { case eating, wantsBreak, happy, napping }

/// One-off moments the brain asks the panda to play.
enum Cue: Equatable, Hashable { case gaze, lookAtYou, sip, sun, morning, sleepy, reunion, remind, news }

/// Moments Bao starts that you may answer or ignore. Bao learns how often you answer each, and does the ignored ones less.
enum Nudge: String { case line, gaze }

struct Settings {
    var stretchMinutes: Double = 50      // screen time before it starts asking for a break
    var breakMinutes: Double = 5         // away this long is a real break
    var idleSeconds: Double = 120        // no input this long means you stepped away
    var eyeRestMinutes: Double = 20      // the 20-20-20 rule: every 20 minutes...
    var eyeRestSeconds: Double = 20      // ...look away for 20 seconds
    var waterMinutes: Double = 90
    var escalateMinutes: Double = 10     // ask level 1 -> 2 (the "break?" bubble)
    var notifyMinutes: Double = 20       // ask level 2 -> 3 (one notification)
    var maxAsksPerHour = 2
    var windDownHour = 23
    var reunionHours: Double = 48
}

/// The only thing saved to disk: counts and dates. No app names, no window titles, no history, and nothing you type.
struct Memory: Codable {
    var bond = 0
    var day = ""
    var breaksToday = 0
    var longestStretchMinutes = 0
    var eyeRestsToday = 0
    var morningDay = ""
    var daylightDay = ""
    var nightBonusDay = ""
    var lastSeen: Date?
    var lastDayBreaks = 0               // a summary of the last day you were here, for picking Bao's mood
    var lastDayLongest = 0
    var lastDayEnd: Date?
    var temper = ""                     // Bao's mood today, and the day it was picked
    var temperDay = ""
    var gifts: [String: Int] = [:]      // how many of each gift Bao has found for you
    var giftToday = ""                  // the gift beside Bao today
    var playTreats = 0                  // surprises from play today, at most 3
    var answers: [String: Double] = [:] // how often you answer each kind of nudge, from 0 to 1

    init() {}

    /// Older files lack the newer fields; missing fields take their defaults instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bond = try c.decodeIfPresent(Int.self, forKey: .bond) ?? 0
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        breaksToday = try c.decodeIfPresent(Int.self, forKey: .breaksToday) ?? 0
        longestStretchMinutes = try c.decodeIfPresent(Int.self, forKey: .longestStretchMinutes) ?? 0
        eyeRestsToday = try c.decodeIfPresent(Int.self, forKey: .eyeRestsToday) ?? 0
        morningDay = try c.decodeIfPresent(String.self, forKey: .morningDay) ?? ""
        daylightDay = try c.decodeIfPresent(String.self, forKey: .daylightDay) ?? ""
        nightBonusDay = try c.decodeIfPresent(String.self, forKey: .nightBonusDay) ?? ""
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        lastDayBreaks = try c.decodeIfPresent(Int.self, forKey: .lastDayBreaks) ?? 0
        lastDayLongest = try c.decodeIfPresent(Int.self, forKey: .lastDayLongest) ?? 0
        lastDayEnd = try c.decodeIfPresent(Date.self, forKey: .lastDayEnd)
        temper = try c.decodeIfPresent(String.self, forKey: .temper) ?? ""
        temperDay = try c.decodeIfPresent(String.self, forKey: .temperDay) ?? ""
        gifts = try c.decodeIfPresent([String: Int].self, forKey: .gifts) ?? [:]
        giftToday = try c.decodeIfPresent(String.self, forKey: .giftToday) ?? ""
        playTreats = try c.decodeIfPresent(Int.self, forKey: .playTreats) ?? 0
        answers = try c.decodeIfPresent([String: Double].self, forKey: .answers) ?? [:]
    }
}

/// Pure behaviour: no UI, no clock of its own, so a test can run a whole day with made-up times.
///
/// Rules it keeps: it never rewards screen time (bond comes from breaks, eye rests, ending the night on time,
/// and at most 3 surprises a day from play); it asks for a break only at a natural pause and escalates slowly,
/// at most `maxAsksPerHour` times an hour; it never guilt-trips; it reads only presence, idle time and the clock.
struct Brain {
    var settings = Settings()
    var memory = Memory()
    var calendar = Calendar.current
    var snoozeUntil: Date? {
        didSet { if snoozeUntil != nil { askLevel = 0; levelSince = nil } }
    }
    private(set) var lastBreakMinutes: Double = 0
    private(set) var stretchStart: Date?
    private(set) var awaySince: Date?
    private(set) var happyUntil: Date?
    private(set) var lastEyeRest: Date?
    private(set) var lastWater: Date?
    private(set) var askLevel = 0            // 0 none, 1 looked at you, 2 bubble, 3 notified
    private(set) var levelSince: Date?
    private var askTimes: [Date] = []
    private var lastCue: [Cue: Date] = [:]
    private var reunion = false
    private(set) var careDue = false        // a break or an eye rest just happened; its surprise waits until you are back
    private var lastPlayTreat: Date?
    private var gazeAt: Date?               // Bao gazed to suggest an eye rest and is waiting to see if you take one

    var bondLevel: Int { memory.bond >= 25 ? 2 : memory.bond >= 10 ? 1 : 0 }

    /// Call every 15 seconds and on lock, unlock, sleep and wake. Returns true when `memory` changed. `busy`: a video
    /// is playing or a call is on, so you are at the screen even without typing: neither a break nor an eye rest.
    @discardableResult
    mutating func tick(now: Date, idle: TimeInterval, locked: Bool, busy: Bool = false) -> Bool {
        var changed = rollDay(now)
        if !locked && (idle < settings.idleSeconds || busy) {
            if let away = awaySince {
                let awayMinutes = now.timeIntervalSince(away) / 60
                if awayMinutes >= settings.breakMinutes {
                    memory.breaksToday += 1
                    memory.bond += 1                      // bond grows only from care, never from screen time
                    lastBreakMinutes = awayMinutes
                    stretchStart = now
                    happyUntil = now.addingTimeInterval(120)
                    lastEyeRest = now
                    lastWater = now
                    careDue = true
                    gazeAt = nil
                    askLevel = 0
                    levelSince = nil
                    if awayMinutes >= 15, (11..<16).contains(hour(now)) { memory.daylightDay = dayKey(now) }
                    if awayMinutes >= settings.reunionHours * 60 { reunion = true }
                    changed = true
                }
                awaySince = nil
            }
            if stretchStart == nil {                       // first sight of you since launch
                stretchStart = now
                lastEyeRest = now
                lastWater = now
                if let seen = memory.lastSeen, now.timeIntervalSince(seen) >= settings.reunionHours * 3600 { reunion = true }
            }
            if !busy, idle >= settings.eyeRestSeconds, let last = lastEyeRest {
                if now.timeIntervalSince(last) >= settings.eyeRestMinutes * 60 {   // it was due: a real eye rest
                    memory.eyeRestsToday += 1
                    if memory.eyeRestsToday % 3 == 0 { memory.bond += 1 }
                    careDue = true
                    if gazeAt != nil { answered(.gaze, true); gazeAt = nil }
                    changed = true
                }
                lastEyeRest = now
            }
            let minutes = Int(stretchMinutes(now))
            if minutes > memory.longestStretchMinutes { memory.longestStretchMinutes = minutes; changed = true }
            memory.lastSeen = now
        } else if awaySince == nil {
            awaySince = locked ? now : now.addingTimeInterval(-idle)
            if locked, hour(now) == settings.windDownHour, memory.nightBonusDay != dayKey(now) {
                memory.nightBonusDay = dayKey(now)        // ended the night on time
                memory.bond += 1
                changed = true
            }
        }
        return changed
    }

    /// Call right after `tick`. Picks at most one moment to play, and says whether to send the one notification.
    /// During a call it stays quiet. While a video plays there is no typing to pause, so any moment is a pause.
    mutating func decide(now: Date, idle: TimeInterval, watching: Bool = false, inCall: Bool = false) -> (cue: Cue?, notify: Bool) {
        guard awaySince == nil, stretchStart != nil, !inCall else { return (nil, false) }
        let pause = idle >= 15 && (idle < 60 || watching)   // a natural pause: you stopped typing for a moment
        let today = dayKey(now)
        if reunion { reunion = false; memory.morningDay = today; return (.reunion, false) }
        if memory.morningDay != today {
            memory.morningDay = today
            if (5..<12).contains(hour(now)) { return (.morning, false) }
        }

        var notify = false
        let snoozed = snoozeUntil.map { now < $0 } ?? false
        if !snoozed, stretchMinutes(now) >= settings.stretchMinutes {
            let since = levelSince.map { now.timeIntervalSince($0) / 60 } ?? 0
            switch askLevel {
            case 0 where pause:
                askLevel = 1; levelSince = now
                return (.lookAtYou, false)
            case 1 where since >= settings.escalateMinutes && canAsk(now):
                askLevel = 2; levelSince = now; askTimes.append(now)
            case 2 where since >= settings.notifyMinutes && canAsk(now):
                askLevel = 3; levelSince = now; askTimes.append(now); notify = true
            default: break
            }
        }
        guard askLevel < 2 else { return (nil, notify) }  // no other moments while it is asking

        let h = hour(now)
        if let at = gazeAt, now.timeIntervalSince(at) >= 120 { answered(.gaze, false); gazeAt = nil }
        // every 5 minutes while an eye rest is due, stretching to every 20 if you ignore it
        if let last = lastEyeRest, now.timeIntervalSince(last) >= settings.eyeRestMinutes * 60,
           cooled(.gaze, 5 / max(rate(.gaze), 0.25), now) {
            gazeAt = now
            return fire(.gaze, now)
        }
        if waterDue(now), pause, cooled(.sip, 30, now) { return fire(.sip, now) }
        if (12..<15).contains(h), memory.daylightDay != today, pause, cooled(.sun, 60, now) { return fire(.sun, now) }
        if h >= settings.windDownHour || h < 5, cooled(.sleepy, 10, now) { return fire(.sleepy, now) }
        return (nil, notify)
    }

    func stretchMinutes(_ now: Date) -> Double {
        guard awaySince == nil, let start = stretchStart else { return 0 }
        return now.timeIntervalSince(start) / 60
    }

    func waterDue(_ now: Date) -> Bool {
        lastWater.map { now.timeIntervalSince($0) >= settings.waterMinutes * 60 } ?? false
    }

    func mood(_ now: Date) -> Mood {
        if let away = awaySince, now.timeIntervalSince(away) >= settings.breakMinutes * 60 { return .napping }
        if let until = happyUntil, now < until { return .happy }
        let snoozed = snoozeUntil.map { now < $0 } ?? false
        if !snoozed && askLevel >= 2 { return .wantsBreak }
        return .eating
    }

    /// Petting makes the panda happy for a minute. Any bond from play comes only through `played`, capped each day.
    mutating func pet(_ now: Date) { happyUntil = now.addingTimeInterval(60) }

    // MARK: surprises and learning

    /// The surprise for a break or eye rest, once you are back at the keys. nil when none is waiting.
    /// `r` and `pick` are random numbers from 0 up to 1.
    mutating func takeTreat(idle: TimeInterval, r: Double, pick: Double) -> Treat? {
        guard careDue, idle < 15 else { return nil }
        careDue = false
        return give(Rewards.roll(care: true, bond: memory.bond, r: r, pick: pick))
    }

    /// Petting, tickles and chat: a surprise one time in four, at most 3 a day and 30 minutes apart,
    /// so play is a moment of fun and never a reason to stay at the screen.
    mutating func played(_ now: Date, chance: Double, r: Double, pick: Double) -> Treat? {
        guard memory.playTreats < 3, chance < 0.25, lastPlayTreat.map({ now.timeIntervalSince($0) >= 1800 }) ?? true else { return nil }
        memory.playTreats += 1
        lastPlayTreat = now
        return give(Rewards.roll(care: false, bond: memory.bond, r: r, pick: pick))
    }

    private mutating func give(_ t: Treat) -> Treat {
        switch t {
        case .heart: memory.bond += 1
        case .gift(let g):
            memory.bond += 1
            memory.gifts[g.rawValue, default: 0] += 1
            memory.giftToday = g.rawValue
        case .trick: break
        }
        return t
    }

    /// Each answer moves the rate a quarter of the way to 1, each ignored nudge a quarter of the way to 0.
    mutating func answered(_ n: Nudge, _ yes: Bool) {
        let old = rate(n)
        memory.answers[n.rawValue] = old + 0.25 * ((yes ? 1 : 0) - old)
    }

    /// Starts at 1, so a new Bao is as chatty as before and learns from there.
    func rate(_ n: Nudge) -> Double { memory.answers[n.rawValue] ?? 1 }

    /// Whether to start an optional nudge now: always while you answer them, down to one time in four if you never do.
    func wants(_ n: Nudge, r: Double) -> Bool { r < 0.25 + 0.75 * rate(n) }

    // MARK: helpers

    private func canAsk(_ now: Date) -> Bool {
        askTimes.filter { now.timeIntervalSince($0) < 3600 }.count < settings.maxAsksPerHour
    }

    private func cooled(_ cue: Cue, _ minutes: Double, _ now: Date) -> Bool {
        lastCue[cue].map { now.timeIntervalSince($0) >= minutes * 60 } ?? true
    }

    private mutating func fire(_ cue: Cue, _ now: Date) -> (cue: Cue?, notify: Bool) {
        lastCue[cue] = now
        return (cue, false)
    }

    private func hour(_ d: Date) -> Int { calendar.component(.hour, from: d) }

    private func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private mutating func rollDay(_ now: Date) -> Bool {
        let day = dayKey(now)
        guard day != memory.day else { return false }
        if !memory.day.isEmpty {                       // keep a summary of the last day before clearing it
            memory.lastDayBreaks = memory.breaksToday
            memory.lastDayLongest = memory.longestStretchMinutes
            memory.lastDayEnd = memory.lastSeen
        }
        memory.day = day
        memory.breaksToday = 0
        memory.longestStretchMinutes = 0
        memory.eyeRestsToday = 0
        memory.giftToday = ""
        memory.playTreats = 0
        return true
    }
}
