import Foundation

/// A trick Bao can do. More unlock as bond grows.
enum Trick: String, CaseIterable { case wave, roll, spin, dance, juggle }

/// A small gift Bao finds for you. It sits beside Bao for the rest of the day, and the menu counts your collection.
enum Gift: String, CaseIterable { case flower, note, star, clover, moon
    var symbol: Character { ["✿", "♪", "★", "☘", "☾"][Self.allCases.firstIndex(of: self)!] }
}

/// A surprise. Care (a break, an eye rest) and play (petting, tickles, a chat) can bring one.
enum Treat: Equatable { case trick(Trick), heart, gift(Gift) }

enum Unlock: Equatable { case trick(Trick), gift(Gift) }

/// Variable rewards: you never know which surprise comes, which keeps them fun. Pure logic, so it can be tested.
enum Rewards {
    /// What bond unlocks, in order, so there is always a next thing to look forward to. The roll at 25 is the
    /// roll Bao already showed off at bond level 2.
    static let ladder: [(bond: Int, unlock: Unlock)] = [
        (0, .trick(.wave)), (0, .gift(.flower)), (25, .trick(.roll)), (40, .trick(.spin)), (50, .gift(.note)),
        (65, .trick(.dance)), (80, .gift(.star)), (100, .trick(.juggle)), (125, .gift(.clover)), (160, .gift(.moon)),
    ]

    static func unlocked(_ bond: Int) -> [Unlock] { ladder.filter { $0.bond <= bond }.map(\.unlock) }
    static func next(_ bond: Int) -> (bond: Int, unlock: Unlock)? { ladder.first { $0.bond > bond } }
    static func newly(from old: Int, to new: Int) -> [Unlock] { ladder.filter { $0.bond > old && $0.bond <= new }.map(\.unlock) }

    /// `r` and `pick` are random numbers from 0 up to 1. After care: a gift 10% of the time, a heart 25%, else a
    /// trick. After play: a heart 25%, else a trick, and never a gift, so gifts stay the reward for care.
    static func roll(care: Bool, bond: Int, r: Double, pick: Double) -> Treat {
        let have = unlocked(bond)
        let tricks = have.compactMap { if case .trick(let t) = $0 { t } else { nil } }
        let gifts = have.compactMap { if case .gift(let g) = $0 { g } else { nil } }
        if care, r < 0.10 {
            // newer gifts are rarer: with three, the weights are 3, 2 and 1
            let weights = (0..<gifts.count).map { gifts.count - $0 }
            var left = pick * Double(weights.reduce(0, +))
            for (g, w) in zip(gifts, weights) {
                left -= Double(w)
                if left < 0 { return .gift(g) }
            }
            return .gift(gifts[0])
        }
        if r < (care ? 0.35 : 0.25) { return .heart }
        return .trick(tricks[min(Int(pick * Double(tricks.count)), tricks.count - 1)])
    }
}
