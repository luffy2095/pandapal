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
precondition(m.bond == 5 && m.eyeRestsToday == 0 && m.lastSeen == nil && m.temper == "", "older memory files still load")
let withReminders = #"{"bond":7,"reminders":[{"text":"Psst!","at":814776593}]}"#
precondition((try? JSONDecoder().decode(Memory.self, from: Data(withReminders.utf8)))?.bond == 7, "files from the chat version still load")


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
var w2 = Personality()
precondition(w2.react(.wave, mood: .eating, now: t0) == .dance, "waving the pointer at it: it dances")
precondition(w2.react(.wave, mood: .eating, now: t0.addingTimeInterval(2)) == nil
          && w2.react(.wave, mood: .eating, now: t0.addingTimeInterval(6)) == .dance, "one dance at a time, 5 seconds apart")
var sleeper = Personality()
precondition(sleeper.react(.wave, mood: .napping, now: t0) == nil, "asleep, it does not dance")
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

// a video or a call: you are at the screen even without typing
var v = Brain()
v.tick(now: time(7, 9), idle: 0, locked: false)
var vt = time(7, 9)
while vt <= time(7, 9, 30) { v.tick(now: vt, idle: 400, locked: false, busy: true); vt = vt.addingTimeInterval(15) }
v.tick(now: time(7, 9, 31), idle: 0, locked: false)
precondition(v.memory.breaksToday == 0 && v.memory.eyeRestsToday == 0 && v.stretchMinutes(time(7, 9, 31)) >= 31,
             "30 minutes of video is screen time, not a break or an eye rest")
var caller = Brain()
caller.tick(now: time(8, 9), idle: 0, locked: false)
caller.tick(now: time(8, 10), idle: 20, locked: false)
_ = caller.decide(now: time(8, 10), idle: 20)                                     // the morning hello is out of the way
caller.tick(now: time(8, 10), idle: 20, locked: false)
precondition(caller.decide(now: time(8, 10), idle: 20, inCall: true) == (nil, false), "quiet during a call")
precondition(caller.decide(now: time(8, 10), idle: 20).cue == .lookAtYou, "after the call it asks at the next pause")
var film = Brain()
film.tick(now: time(9, 9), idle: 0, locked: false)
_ = film.decide(now: time(9, 9), idle: 0)
film.tick(now: time(9, 10), idle: 300, locked: false, busy: true)
precondition(film.decide(now: time(9, 10), idle: 300).cue != .lookAtYou                  // 5 minutes without typing is no pause,
          && film.decide(now: time(9, 10), idle: 300, watching: true).cue == .lookAtYou, "but during a long video it may still ask")
print("presence ok")

// words a script hands Bao with --say: one tidy line, never empty, never huge
precondition(Words.said("  Build\nfinished!\u{07}  ") == "Build finished!", "newlines become spaces, control characters go")
precondition(Words.said(" \n\t ") == nil, "nothing to say: no bubble")
precondition(Words.said(String(repeating: "a", count: 500))?.count == 200, "at most 200 characters")
precondition(Temper.allCases.allSatisfy { Words.mood[$0] != nil }, "a good morning for every mood")
precondition(Words.tips[Words.nextTip(after: 0, waterDue: true, hour: 10)].act == .sip, "water first when it is due")
let evening = (0..<40).reduce(into: [Int]()) { seen, _ in seen.append(Words.nextTip(after: seen.last ?? 0, waterDue: false, hour: 21)) }
precondition(!evening.contains { [.sun, .sip].contains(Words.tips[$0].act) } && Set(evening).count == Words.tips.count - 2,
             "every idea in turn, no daylight in the evening, water only when due")
precondition((0..<40).reduce(into: [Int]()) { s, _ in s.append(Words.nextTip(after: s.last ?? 0, waterDue: false, hour: 12)) }
                .contains { Words.tips[$0].act == .sun }, "daylight around noon")
print("words ok")

// surprises: care can bring a gift, a heart or a trick; play brings no gifts and is capped
precondition(Rewards.roll(care: true, bond: 0, r: 0.05, pick: 0) == .gift(.flower), "a low roll after care is a gift")
precondition(Rewards.roll(care: true, bond: 0, r: 0.2, pick: 0) == .heart, "a middle roll after care is a heart")
precondition(Rewards.roll(care: true, bond: 0, r: 0.9, pick: 0.99) == .trick(.wave), "otherwise a trick Bao knows")
precondition(Rewards.roll(care: false, bond: 200, r: 0.05, pick: 0) == .heart, "play never brings a gift")
precondition(Rewards.roll(care: true, bond: 200, r: 0.05, pick: 0) == .gift(.flower)
          && Rewards.roll(care: true, bond: 200, r: 0.05, pick: 0.999) == .gift(.moon), "the newest gift is the rarest")
precondition(Rewards.unlocked(0).count == 2 && Rewards.newly(from: 24, to: 25) == [.trick(.roll)], "bond 25 unlocks the roll")
precondition(Rewards.next(25)?.bond == 40 && Rewards.next(200) == nil, "the next unlock is always shown until the last")

var care = Brain()
care.tick(now: time(5, 9), idle: 0, locked: false)
care.tick(now: time(5, 10), idle: 0, locked: true)
care.tick(now: time(5, 10, 10), idle: 0, locked: false)                       // back from a 10-minute break
precondition(care.takeTreat(idle: 30, r: 0.2, pick: 0) == nil, "the surprise waits until you are back at the keys")
precondition(care.takeTreat(idle: 0, r: 0.2, pick: 0) == .heart && care.memory.bond == 2, "a break, then a heart: bond 2")
precondition(care.takeTreat(idle: 0, r: 0.2, pick: 0) == nil, "one surprise per break")
let plays = [time(5, 11), time(5, 11, 10), time(5, 11, 40), time(5, 12, 20), time(5, 13)].map {
    care.played($0, chance: 0.1, r: 0.9, pick: 0) != nil }
precondition(plays == [true, false, true, true, false], "play surprises: 30 minutes apart and 3 a day, got \(plays)")
precondition(care.played(time(5, 14), chance: 0.5, r: 0.9, pick: 0) == nil, "most play brings no surprise")
care.tick(now: time(5, 15), idle: 0, locked: true)
care.tick(now: time(5, 15, 10), idle: 0, locked: false)
precondition(care.takeTreat(idle: 0, r: 0.05, pick: 0) == .gift(.flower) && care.memory.gifts["flower"] == 1
          && care.memory.giftToday == "flower", "a gift is kept and shown for the day")
care.tick(now: time(6, 9), idle: 0, locked: false)
precondition(care.memory.giftToday == "" && care.memory.playTreats == 0 && care.memory.gifts["flower"] == 1, "a new day: the collection stays")

// learning: ignored nudges get rarer, down to a floor; answers bring them back
var learn = Brain()
precondition(learn.wants(.line, r: 0.99), "a new Bao says every line")
for _ in 0..<6 { learn.answered(.line, false) }
precondition(!learn.wants(.line, r: 0.45) && learn.wants(.line, r: 0.3), "6 ignored lines: Bao speaks 38% of the time")
learn.answered(.line, true)
precondition(learn.wants(.line, r: 0.45), "an answer brings them back")
for _ in 0..<100 { learn.answered(.line, false) }
precondition(learn.wants(.line, r: 0.24), "ignored lines never stop: one time in four")
var eyes = Brain()
var gazes: [Date] = []
var at = time(9, 9)
while at <= time(9, 10) {                                                     // working on, never looking away
    eyes.tick(now: at, idle: 5, locked: false)
    if eyes.decide(now: at, idle: 5).cue == .gaze { gazes.append(at) }
    at = at.addingTimeInterval(15)
}
let gaps = zip(gazes.dropFirst(), gazes).map { $0.timeIntervalSince($1) }
precondition(gaps.count >= 2 && gaps[1] > gaps[0] && eyes.rate(.gaze) < 1, "ignored eye-rest nudges come less often, got \(gaps)")
print("rewards ok")


// Connecting agents: other settings and hooks stay, Bao's hook appears once, and disconnecting takes only Bao's out.
let claudeEvents: [(String, String?)] = [("Notification", "permission_prompt|elicitation_dialog"), ("Stop", nil)]
let rtk: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "rtk hook claude"]]]
let handMade: [String: Any] = ["hooks": [["type": "command", "command": "sh ~/.config/pandapal/hook.sh claude 2>/dev/null || true"]]]
let start: [String: Any] = ["model": "fable", "hooks": ["PreToolUse": [rtk], "Stop": [handMade]]]
let cmd = "\"/Applications/PandaPal.app/Contents/MacOS/PandaPal\" --hook claude"
let joined = Agents.merged(start, events: claudeEvents, command: cmd)
func baoHooks(_ j: [String: Any], _ event: String) -> [[String: Any]] {
    ((j["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []).filter {
        ($0["hooks"] as? [[String: Any]] ?? []).contains { Agents.isBao($0["command"] as? String ?? "") }
    }
}
precondition(joined["model"] as? String == "fable", "other settings stay")
precondition(((joined["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.count == 1, "other tools' hooks stay")
precondition(baoHooks(joined, "Stop").count == 1 && baoHooks(joined, "Notification").count == 1, "one Bao hook per event")
precondition(baoHooks(joined, "Notification")[0]["matcher"] as? String == "permission_prompt|elicitation_dialog", "matcher set")
precondition(!"\(joined)".contains("pandapal/hook.sh"), "the old hand-made hook is replaced")
let twice = Agents.merged(joined, events: claudeEvents, command: cmd)
precondition(baoHooks(twice, "Stop").count == 1, "connecting twice keeps one hook")
let gone = Agents.merged(twice, events: claudeEvents, command: nil)
precondition(baoHooks(gone, "Stop").isEmpty && (gone["hooks"] as? [String: Any])?["Stop"] == nil, "disconnect takes Bao's out")
precondition(((gone["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.count == 1, "and leaves the rest")
let shared: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "other-tool"],
                                                          ["type": "command", "command": cmd]]]]]]
let kept = Agents.merged(shared, events: [("Stop", nil)], command: nil)
precondition("\(kept)".contains("other-tool") && !"\(kept)".contains("--hook"), "a shared group keeps the other tool's hook")

// The file: permissions and a backup are kept, and a file that is not JSON is never overwritten.
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pandapal-test-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let settings = dir.appendingPathComponent("settings.json")
try! #"{"model": "fable", "env": {"KEY": "secret"}}"#.write(to: settings, atomically: true, encoding: .utf8)
try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
try! Agents.edit(settings, events: claudeEvents, command: cmd)
let mode = (try! FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as! NSNumber).intValue
precondition(mode == 0o600, "the settings file stays private, got \(String(mode, radix: 8))")
precondition(FileManager.default.fileExists(atPath: settings.path + ".pandapal-backup"), "a backup is saved")
let broken = dir.appendingPathComponent("broken.json")
try! "{ not json".write(to: broken, atomically: true, encoding: .utf8)
precondition((try? Agents.edit(broken, events: claudeEvents, command: cmd)) == nil, "a file that is not JSON fails")
precondition((try! String(contentsOf: broken, encoding: .utf8)) == "{ not json", "and stays as it was")
try? FileManager.default.removeItem(at: dir)
print("agents ok")

print("brain ok:\(cues.count) cues in the last scene, bond \(b.memory.bond), level \(b.bondLevel)")
