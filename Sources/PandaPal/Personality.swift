import Foundation

/// What your mouse did to the panda, as recognised by the view.
enum Gesture: Equatable { case tap, longPress, dragStart, dragEnd(shaken: Bool), hover, tickle }

/// How the panda answers.
enum Reaction: Equatable {
    case pet, highFive, giggle, dizzy, shy, angry, pout, hug, dangle, drop, dizzyDrop, curious, grumble, wakeUp, cheer
}

/// Bao's mood for the day. It tunes the rules below, and Apple's model speaks in it.
enum Temper: String, CaseIterable, Sendable {
    case playful, sleepy, grumpy, cuddly, curious

    /// Picked each morning from how your last day went; `day` varies it between days. A rule, not the model:
    /// asked to choose, the model picked a mood that contradicted the facts in 6 of 8 tries.
    static func pick(lastDayBreaks: Int, lastDayLongest: Int, lastDayEnd: Date?, yesterday: Temper?, day: Int,
                     calendar: Calendar = .current) -> Temper {
        guard let end = lastDayEnd else { return .curious }                    // a first day: getting to know you
        let hour = calendar.component(.hour, from: end)
        let strained = hour >= 23 || hour < 5 || lastDayLongest >= 90          // up late, or long stretches
        let easy = lastDayBreaks >= 4 && lastDayLongest < 60
        var options: [Temper] = strained ? [.sleepy, .grumpy] : easy ? [.playful, .cuddly] : [.curious, .playful, .cuddly]
        if options.count > 1, let yesterday { options.removeAll { $0 == yesterday } }
        return options[abs(day) % options.count]
    }
}

/// The panda's temper: curious, ticklish, a bit shy, a little sassy when pestered, grumpy when woken,
/// and quick to forgive. Pure logic with made-up times, so it can be tested. Nothing here earns bond:
/// playing with the panda is a moment of fun, never a reason to stay at the screen.
struct Personality {
    private(set) var patience = 1.0          // 0...1. Pestering drains it; it refills within a couple of minutes
    var temper: Temper?                      // today's mood; nil keeps the plain rules
    private var taps: [Date] = []
    private var shyUntil: Date?
    private var angryUntil: Date?
    private var lastHover: Date?
    private var lastTickle: Date?
    private var lastSeen: Date?

    mutating func react(_ g: Gesture, mood: Mood, now: Date) -> Reaction? {
        recover(now)
        switch g {
        case .tap:
            taps.append(now)
            taps = taps.filter { now.timeIntervalSince($0) < 60 }
            if (shyUntil.map { now < $0 } ?? false) || (angryUntil.map { now < $0 } ?? false) {
                shyUntil = nil                                                    // tapped while shy: cutely angry,
                angryUntil = now.addingTimeInterval(2)                            // and it stays so until the taps stop
                taps.removeAll()
                drain(0.05)
                return .angry
            }
            let quick = taps.filter { now.timeIntervalSince($0) < 1.2 }.count
            if mood == .napping { return quick >= 3 ? .wakeUp : .grumble }
            if taps.count >= (temper == .grumpy ? 8 : 12) {
                shyUntil = now.addingTimeInterval(10)
                taps.removeAll()
                drain(0.3)
                return .shy
            }
            if taps.filter({ now.timeIntervalSince($0) < 4 }).count >= 8 { drain(0.2); return .dizzy }
            if quick >= (temper == .playful ? 2 : 3) { return .giggle }
            if quick == 2, let prev = taps.dropLast().last, now.timeIntervalSince(prev) < 0.35 { return .highFive }
            if patience < (temper == .grumpy ? 0.6 : 0.4) { return .pout }
            return mood == .wantsBreak ? .cheer : temper == .cuddly ? .hug : .pet
        case .longPress:
            patience = 1                                                          // a hug fixes everything
            shyUntil = nil
            angryUntil = nil
            return .hug
        case .dragStart:
            return .dangle
        case .dragEnd(let shaken):
            if shaken { drain(0.1); return .dizzyDrop }
            return .drop
        case .tickle:                                                              // the pointer swiped fast up and down over it
            if mood == .napping { return .grumble }
            guard lastTickle.map({ now.timeIntervalSince($0) >= 2 }) ?? true else { return nil }
            lastTickle = now
            return .giggle
        case .hover:
            guard mood != .napping, temper != .sleepy,
                  lastHover.map({ now.timeIntervalSince($0) >= (temper == .curious ? 8 : 20) }) ?? true else { return nil }
            lastHover = now
            return .curious
        }
    }

    private mutating func drain(_ amount: Double) { patience = max(0, patience - amount) }

    /// Full patience again after about two minutes of peace.
    private mutating func recover(_ now: Date) {
        if let seen = lastSeen { patience = min(1, patience + now.timeIntervalSince(seen) / 120) }
        lastSeen = now
    }
}
