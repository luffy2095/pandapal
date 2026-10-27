import Foundation

/// How Bao acts out a break idea while it waits for you.
enum TipAct: Equatable { case stretch, gaze, sip, sun, shoulders, neck, wrists, palms, blink, walk, breathe, reach, snack }

/// One break idea: what Bao says, and how it shows it.
struct Tip { let text: String; let act: TipAct }

/// Bao's own words, written by hand. Each moment picks one at random, so it rarely repeats itself.
enum Words {
    static let tips = [
        Tip(text: "Stand up and stretch with me.", act: .stretch),
        Tip(text: "Look at something far away for 20 seconds.", act: .gaze),
        Tip(text: "Drink some water. I'm having bamboo.", act: .sip),
        Tip(text: "Step outside for a minute of daylight.", act: .sun),
        Tip(text: "Roll your shoulders. Pandas roll everything.", act: .shoulders),
        Tip(text: "Tilt your head slowly, left, then right.", act: .neck),
        Tip(text: "Shake out your hands and wrists.", act: .wrists),
        Tip(text: "Close your eyes and rest them under your palms.", act: .palms),
        Tip(text: "Blink slowly ten times.", act: .blink),
        Tip(text: "Take a short walk. I'll guard the desk.", act: .walk),
        Tip(text: "Breathe with me: in for four, hold, out for four.", act: .breathe),
        Tip(text: "Reach your arms up high, then let them drop.", act: .reach),
        Tip(text: "Have a snack. Bamboo counts.", act: .snack),
    ]

    /// The next break idea after `i`: water when it is due, daylight only by day, and otherwise each in turn.
    static func nextTip(after i: Int, waterDue: Bool, hour: Int) -> Int {
        if waterDue, let water = tips.firstIndex(where: { $0.act == .sip }) { return water }
        var j = i
        repeat { j = (j + 1) % tips.count } while tips[j].act == .sip || (tips[j].act == .sun && !(8..<18).contains(hour))
        return j
    }

    static let back = ["Welcome back!", "That was a good break.", "Yay, you took a break!", "Fresh eyes! Nice.",
                       "You're back! I kept your seat warm."]
    static let morning = ["Good morning!", "Morning! Bamboo for breakfast again.", "Hi! Let's have a gentle day."]
    static let mood: [Temper: String] = [
        .playful: "Good morning! I feel playful today.", .sleepy: "Mmm… morning. I'm a bit sleepy today.",
        .grumpy: "Morning. I'm a little grumpy today. Hmph.", .cuddly: "Good morning! I feel cuddly today.",
        .curious: "Good morning! I'm curious about everything today.",
    ]
    static let late = ["It's late. The rest can wait until tomorrow.", "Bedtime soon? I'm getting sleepy.",
                       "Let's both rest. Tomorrow is another day."]
    static let reunion = ["You're back! I missed you so much!", "There you are! It's been days!"]
    static func gift(_ g: Gift) -> String { "I found a little \(g.rawValue) for you!" }
    static func trick(_ t: Trick) -> String { "I learned a new trick: \(t.rawValue)!" }
    static func newGift(_ g: Gift) -> String { "Now I can find you a \(g.rawValue) sometimes!" }

    /// What a script sent with `--say`, made fit for the bubble: one line, no control characters, at most 200
    /// characters. nil when nothing is left to say.
    static func said(_ raw: String) -> String? {
        let line = raw.replacingOccurrences(of: "\n", with: " ").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(line)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}
