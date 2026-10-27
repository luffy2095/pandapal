import Foundation

// Simulates days at the app's real rhythm (a tick every 15 seconds) and checks every behaviour rule.
let cal = Calendar.current
func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

var b = Brain()
var cues: [Cue] = []
var notifies = 0

/// Present from `from` to `to`, ticking every 15 s with the given idle seconds.
func work(_ from: Date, _ to: Date, idle: Double = 5) {
    var t = from
    while t <= to {
        b.tick(now: t, idle: idle, locked: false)
        let (c, n) = b.decide(now: t, idle: idle)
        if let c { cues.append(c) }
        if n { notifies += 1 }
        t = t.addingTimeInterval(15)
    }
}
func lock(_ at: Date) { b.tick(now: at, idle: 0, locked: true) }

// 09:00 Monday: first sight of the day
work(time(2, 9), time(2, 9))
precondition(cues == [.morning], "good morning on the first sight of the day, got \(cues)")

// no eye-rest cue before 20 minutes; a gaze cue at 20 minutes
cues = []
work(time(2, 9, 0).addingTimeInterval(15), time(2, 9, 19))
precondition(!cues.contains(.gaze), "no eye-rest cue before 20 minutes")
work(time(2, 9, 20), time(2, 9, 20))
precondition(cues.contains(.gaze), "eye-rest cue at 20 minutes")

// a 25-second pause satisfies it
work(time(2, 9, 21), time(2, 9, 21), idle: 25)
precondition(b.memory.eyeRestsToday == 1, "a 20-second look away counts as an eye rest")

// keep working without pausing: due at 50 minutes, but it waits for a natural pause
cues = []
work(time(2, 9, 21).addingTimeInterval(15), time(2, 9, 51))
precondition(b.askLevel == 0 && b.mood(time(2, 9, 51)) == .eating, "no asking before a natural pause")
work(time(2, 9, 52), time(2, 9, 52), idle: 20)
precondition(cues.last == .lookAtYou && b.askLevel == 1, "at a pause it looks at you and stretches")
precondition(b.mood(time(2, 9, 52)) == .eating, "level 1 is silent")

// 10 minutes later: the bubble
work(time(2, 9, 52).addingTimeInterval(15), time(2, 10, 2))
precondition(b.askLevel == 2 && b.mood(time(2, 10, 2)) == .wantsBreak, "after 10 more minutes it shows the bubble")
precondition(!cues.contains(.gaze) || cues.lastIndex(of: .gaze)! < cues.lastIndex(of: .lookAtYou)!, "no other moments while asking")

// 20 minutes after that: exactly one notification, then it stops
work(time(2, 10, 2).addingTimeInterval(15), time(2, 10, 30))
precondition(notifies == 1 && b.askLevel == 3, "one notification, got \(notifies)")

// a 6-minute break: happy, bond +1, every need reset
let bondBefore = b.memory.bond
lock(time(2, 10, 31))
precondition(b.mood(time(2, 10, 36)) == .napping, "naps while you are away")
work(time(2, 10, 37), time(2, 10, 37))
precondition(b.memory.breaksToday == 1 && b.memory.bond == bondBefore + 1, "a break grows the bond")
precondition(b.lastBreakMinutes == 6 && b.askLevel == 0, "break length remembered, asking reset")
precondition(b.mood(time(2, 10, 37)) == .happy, "happy to see you")

// petting is cute but earns nothing
b.pet(time(2, 10, 38))
precondition(b.memory.bond == bondBefore + 1, "petting earns no bond")

// snooze silences the asking
b.snoozeUntil = time(2, 12)
work(time(2, 10, 38), time(2, 11, 40), idle: 20)
precondition(b.mood(time(2, 11, 40)) == .eating && b.askLevel == 0, "snoozed: no asking")

// midday at a pause: it looks at the sun
cues = []
b.snoozeUntil = nil
lock(time(2, 12, 0)); work(time(2, 12, 6), time(2, 12, 6))          // a short break resets the stretch
work(time(2, 12, 30), time(2, 12, 30), idle: 20)
precondition(cues.contains(.sun), "midday daylight cue at a pause, got \(cues)")

// wind-down: sleepy after 23:00, and locking then earns the night bonus
cues = []
lock(time(2, 22, 0)); work(time(2, 23, 0), time(2, 23, 10))
precondition(cues.contains(.sleepy), "sleepy at wind-down time")
let bondNight = b.memory.bond
lock(time(2, 23, 15))
precondition(b.memory.bond == bondNight + 1, "ending the night on time grows the bond")

// next morning: a new day resets today's counts, keeps the bond, says good morning
let breaksDay2 = b.memory.breaksToday, longestDay2 = b.memory.longestStretchMinutes, endDay2 = b.memory.lastSeen
cues = []
work(time(3, 8, 30), time(3, 8, 30))
precondition(b.memory.eyeRestsToday == 0 && b.memory.bond >= bondNight + 1, "new day: counts reset, bond kept")
precondition(cues.contains(.morning), "good morning again")
precondition(b.memory.lastDayBreaks == breaksDay2 && b.memory.lastDayLongest == longestDay2 && b.memory.lastDayEnd == endDay2,
             "a new day keeps a summary of the last one, for picking Bao's mood")

// three days away: a reunion
cues = []
lock(time(3, 9, 0)); work(time(6, 9, 0), time(6, 9, 0))
precondition(cues.first == .reunion, "a happy reunion after days away, got \(cues)")

// files saved by the older version still load
let old = #"{"bond":5,"day":"2026-10-26","breaksToday":1,"longestStretchMinutes":3}"#
let m = try! JSONDecoder().decode(Memory.self, from: Data(old.utf8))
precondition(m.bond == 5 && m.eyeRestsToday == 0 && m.lastSeen == nil && m.reminders.isEmpty && m.temper == "", "older memory files still load")

// reminders Bao says herself
var rb = Brain()
rb.memory.reminders = [Reminder(text: "Psst! Time to call mom.", at: time(2, 19)), Reminder(text: "Psst! Time to stretch.", at: time(2, 21))]
precondition(rb.takeDue(time(2, 18, 59)).isEmpty, "nothing before its time")
precondition(rb.takeDue(time(2, 19)).map(\.text) == ["Psst! Time to call mom."] && rb.memory.reminders.count == 1, "a due reminder is taken")
precondition(rb.takeDue(time(2, 19, 1)).isEmpty, "and said only once")


// ---- personality ----
var p = Personality()
let t0 = time(10, 14)
func tap(_ seconds: Double, _ mood: Mood = .eating) -> Reaction? { p.react(.tap, mood: mood, now: t0.addingTimeInterval(seconds)) }

// twelve taps, 0.3 s apart: the whole ladder of pestering
var ladder: [Reaction?] = []
for i in 0..<12 { ladder.append(tap(Double(i) * 0.3)) }
precondition(ladder[0] == .pet, "one tap is a pet")
precondition(ladder[1] == .highFive, "a quick second tap is a high five")
precondition(ladder[2] == .giggle && ladder[6] == .giggle, "quick taps tickle it")
precondition(ladder[7] == .dizzy && ladder[10] == .dizzy, "eight taps in a few seconds make it dizzy")
precondition(ladder[11] == .shy, "twelve taps in a minute make it shy, got \(ladder)")
precondition(tap(8) == .angry, "tapped while shy: it gets cutely angry")
precondition(tap(9) == .angry && tap(10.5) == .angry, "it stays angry while the taps keep coming")
precondition(tap(15) == .pout, "the taps stopped, so the anger is over; its patience is still low, so it pouts")
precondition(p.react(.longPress, mood: .eating, now: t0.addingTimeInterval(16)) == .hug, "press and hold is a hug")
precondition(p.patience == 1 && tap(20) == .pet, "a hug restores its patience")

var q = Personality()
_ = q.react(.tap, mood: .eating, now: t0)
for i in 0..<9 { _ = q.react(.tap, mood: .eating, now: t0.addingTimeInterval(2 + Double(i) * 0.3)) }
precondition(q.patience < 1, "pestering drains patience")
_ = q.react(.tap, mood: .eating, now: t0.addingTimeInterval(200))
precondition(q.patience == 1, "patience refills after a couple of minutes")

var n = Personality()
precondition(n.react(.tap, mood: .napping, now: t0) == .grumble, "a poke while napping: one eye opens")
precondition(n.react(.tap, mood: .napping, now: t0.addingTimeInterval(0.3)) == .grumble
          && n.react(.tap, mood: .napping, now: t0.addingTimeInterval(0.6)) == .wakeUp, "three quick pokes wake it")
var w = Personality()
precondition(w.react(.tap, mood: .wantsBreak, now: t0) == .cheer, "a tap while it wants a break: it cheers you on")

var d = Personality()
precondition(d.react(.dragStart, mood: .eating, now: t0) == .dangle, "picked up: it dangles")
precondition(d.react(.dragEnd(shaken: true), mood: .eating, now: t0.addingTimeInterval(2)) == .dizzyDrop, "shaken: dizzy")
precondition(d.react(.hover, mood: .eating, now: t0.addingTimeInterval(3)) == .curious, "the pointer comes near: curious")
precondition(d.react(.hover, mood: .eating, now: t0.addingTimeInterval(10)) == nil, "not curious again for 20 seconds")
precondition(d.react(.hover, mood: .napping, now: t0.addingTimeInterval(60)) == nil, "asleep: does not notice")
var k = Personality()
precondition(k.react(.tickle, mood: .eating, now: t0) == .giggle, "a fast up-and-down swipe tickles it")
precondition(k.react(.tickle, mood: .eating, now: t0.addingTimeInterval(1)) == nil, "one giggle at a time")
precondition(k.react(.tickle, mood: .eating, now: t0.addingTimeInterval(2.5)) == .giggle, "it can be tickled again")
precondition(k.react(.tickle, mood: .napping, now: t0.addingTimeInterval(10)) == .grumble, "tickled in its sleep: one eye opens")
// the mood of the day tunes the rules
var plain = Personality(), grumpy = Personality()
grumpy.temper = .grumpy
var plainTaps: [Reaction?] = [], grumpyTaps: [Reaction?] = []
for i in 0..<8 {
    plainTaps.append(plain.react(.tap, mood: .eating, now: t0.addingTimeInterval(Double(i) * 0.6)))
    grumpyTaps.append(grumpy.react(.tap, mood: .eating, now: t0.addingTimeInterval(Double(i) * 0.6)))
}
precondition(grumpyTaps[7] == .shy && plainTaps[7] != .shy, "a grumpy panda goes shy after 8 taps, not 12")
var playful = Personality()
playful.temper = .playful
_ = playful.react(.tap, mood: .eating, now: t0)
precondition(playful.react(.tap, mood: .eating, now: t0.addingTimeInterval(0.3)) == .giggle, "a playful panda giggles at a double tap")
var cuddly = Personality()
cuddly.temper = .cuddly
precondition(cuddly.react(.tap, mood: .eating, now: t0) == .hug, "a cuddly panda hugs when tapped")
var curious = Personality()
curious.temper = .curious
precondition(curious.react(.hover, mood: .eating, now: t0) == .curious
          && curious.react(.hover, mood: .eating, now: t0.addingTimeInterval(10)) == .curious, "a curious panda notices you more often")
var sleepy = Personality()
sleepy.temper = .sleepy
precondition(sleepy.react(.hover, mood: .eating, now: t0) == nil, "a sleepy panda does not notice the pointer")
let pick = { (breaks: Int, longest: Int, end: Date?, yesterday: Temper?, day: Int) in
    Temper.pick(lastDayBreaks: breaks, lastDayLongest: longest, lastDayEnd: end, yesterday: yesterday, day: day) }
precondition(pick(0, 0, nil, nil, 7) == .curious, "a first day: curious")
precondition([Temper.sleepy, .grumpy].contains(pick(1, 140, time(2, 1, 20), .playful, 7)), "up late after a long stretch: sleepy or grumpy")
precondition([Temper.playful, .cuddly].contains(pick(6, 45, time(2, 18, 30), .sleepy, 7)), "many short stretches: playful or cuddly")
precondition((0..<6).allSatisfy { pick(6, 45, time(2, 18, 30), .playful, $0) == .cuddly }, "never yesterday's mood when there is another")
precondition(pick(3, 70, time(2, 21), nil, 1) != pick(3, 70, time(2, 21), nil, 2), "the mood still changes between days")
print("personality ok")

// reminders asked for in the chat
let r = { (h: Int?, m: Int?, n: Int?, at: Date) in Brain.reminderDate(hour: h, minute: m, inMinutes: n, now: at) }
precondition(r(7, nil, nil, time(2, 17, 30)) == time(2, 19), "'at 7' at 17:30 means 19:00 today")
precondition(r(7, 0, nil, time(2, 6, 0)) == time(2, 7), "'at 7' at 06:00 means 07:00")
precondition(r(19, 15, nil, time(2, 20, 0)) == time(3, 19, 15), "a time already past today is tomorrow")
precondition(r(7, nil, nil, time(2, 23, 0)) == time(3, 7), "'at 7' late at night is tomorrow morning")
precondition(r(nil, nil, 20, time(2, 9)) == time(2, 9, 20), "in 20 minutes")
precondition(r(nil, nil, nil, time(2, 9)) == nil && r(25, 0, nil, time(2, 9)) == nil, "no usable time: no reminder")
print("reminders ok")

print("brain ok:\(cues.count) cues in the last scene, bond \(b.memory.bond), level \(b.bondLevel)")
