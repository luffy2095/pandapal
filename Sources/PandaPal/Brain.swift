import Foundation

enum Mood { case eating, wantsBreak, happy, napping }

/// One-off moments the brain asks the panda to play.
enum Cue: Equatable, Hashable { case gaze, lookAtYou, sip, sun, morning, sleepy, reunion, remind }

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

/// A reminder Bao says herself when its time comes. Kept in the saved file until she has said it.
struct Reminder: Codable, Equatable {
    var text: String
    var at: Date
}

/// The only thing saved to disk. No app names, no window titles, no history, and no typing except the
/// reminders you ask Bao for, each kept only until she says it.
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
    var reminders: [Reminder] = []

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
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
    }
}

/// Pure behaviour: no UI, no clock of its own, so a test can run a whole day with made-up times.
///
/// Rules it keeps: it never rewards screen time (bond comes only from breaks, eye rests and ending the
/// night on time); it asks for a break only at a natural pause and escalates slowly, at most
/// `maxAsksPerHour` times an hour; it never guilt-trips; it reads only presence, idle time and the clock.
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

    var bondLevel: Int { memory.bond >= 25 ? 2 : memory.bond >= 10 ? 1 : 0 }

    /// Call every 15 seconds and on lock, unlock, sleep and wake. Returns true when `memory` changed.
    @discardableResult
    mutating func tick(now: Date, idle: TimeInterval, locked: Bool) -> Bool {
        var changed = rollDay(now)
        if !locked && idle < settings.idleSeconds {
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
            if idle >= settings.eyeRestSeconds, let last = lastEyeRest {
                if now.timeIntervalSince(last) >= settings.eyeRestMinutes * 60 {   // it was due: a real eye rest
                    memory.eyeRestsToday += 1
                    if memory.eyeRestsToday % 3 == 0 { memory.bond += 1 }
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
    mutating func decide(now: Date, idle: TimeInterval) -> (cue: Cue?, notify: Bool) {
        guard awaySince == nil, stretchStart != nil else { return (nil, false) }
        let pause = idle >= 15 && idle < 60              // a natural pause: you stopped typing for a moment
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
        if let last = lastEyeRest, now.timeIntervalSince(last) >= settings.eyeRestMinutes * 60, cooled(.gaze, 5, now) {
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

    /// When a reminder asked for in the chat fires: in `inMinutes`, or at the next `hour`:`minute`.
    /// An hour from 1 to 11 may be read off a 12-hour clock, so "at 7" said at 17:30 means 19:00 today.
    static func reminderDate(hour: Int?, minute: Int?, inMinutes: Int?, now: Date, calendar: Calendar = .current) -> Date? {
        if let n = inMinutes, n > 0 { return now.addingTimeInterval(Double(n) * 60) }
        guard let h = hour, (0...23).contains(h) else { return nil }
        let m = min(max(minute ?? 0, 0), 59)
        let today = (h >= 1 && h < 12 ? [h, h + 12] : [h])
            .compactMap { calendar.date(bySettingHour: $0, minute: m, second: 0, of: now) }
            .filter { $0 > now }.min()
        return today ?? calendar.date(bySettingHour: h, minute: m, second: 0, of: calendar.date(byAdding: .day, value: 1, to: now)!)
    }

    /// Reminders whose time has come, taken out so that each is said once.
    mutating func takeDue(_ now: Date) -> [Reminder] {
        let due = memory.reminders.filter { $0.at <= now }
        memory.reminders.removeAll { $0.at <= now }
        return due
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

    /// Petting is a cute reaction only. It earns no bond, so the panda never rewards more screen time.
    mutating func pet(_ now: Date) { happyUntil = now.addingTimeInterval(60) }

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
        return true
    }
}
