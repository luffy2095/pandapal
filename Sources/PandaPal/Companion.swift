import Foundation
import FoundationModels

/// What Bao can do when you ask in the chat. The app carries it out; `--ask` only prints it.
enum Act: Sendable, Equatable { case snooze(minutes: Int), focus(minutes: Int), remind(String, at: Date), weather, day }

/// One of Bao's abilities as the model sees it. Arguments arrive as raw generated content, because this
/// toolchain has no @Generable macro.
struct BaoTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @MainActor @Sendable (GeneratedContent) async throws -> String
    func call(arguments: GeneratedContent) async throws -> String { try await run(arguments) }
}

/// Bao's voice, from Apple's on-device model. Everything runs on this Mac: no network, no account, and
/// nothing is saved. One model call per message: the model talks, and calls a tool when you ask it to do something.
@MainActor
final class Companion {
    static var available: Bool { SystemLanguageModel.default.isAvailable }

    /// The chat. Kept to three sentences: this small model repeats or mangles any rule it is given.
    static let chatPersona = """
    You are Bao, a cute panda who lives on the user's Mac and keeps them company.
    Chat like a kind, cheerful friend: short and natural, usually one to three sentences. Answer questions, facts and maths from what you know.
    Use a tool only when the user asks you to do that thing, and never say you did something without it. Questions, even about focus or numbers, you just answer.
    Be honest, and never make things up about the user.
    """

    /// Bao's own short lines at its moments, in the speech bubble.
    static let linePersona = """
    You are Bao, a cute panda who lives on the user's Mac. Say one short, warm line, under 20 words, for the moment described. No emoji.
    """

    /// The model sometimes adds faces, asides, emoji or a stock offer of more help. Strip them and end with one face.
    static func finish(_ text: String, face: String = "(ᵔᴥᵔ)") -> String {
        let stripped = text.replacingOccurrences(of: #"\([^()]{0,6}ᴥ[^()]{0,6}\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]|\*[^*]*\*|[\p{Extended_Pictographic}\p{Regional_Indicator}\x{FE0F}\x{200D}]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?:^|(?<=[.!?]))(\s*(Just )?(How else|What else|Let me know|let me know|Is there anything else|I'?m (always |still )?here (if|whenever|for|to)|How can I (help|assist)|Want me to|Anything (else )?I can)[^.?!]*[.?!]*)+$"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.isEmpty ? face : "\(stripped) \(face)"
    }

    /// Plain-language steering the app adds to the facts, because it knows the clock better than the model does.
    static func steer(_ context: String, hour: Int) -> String {
        hour >= 23 || hour < 5 ? context + " It is late at night, so Bao says the rest can wait until tomorrow." : context
    }

    /// The line the app adds under Bao's reply after doing `act`, so what was done is always stated exactly.
    static func receipt(_ act: Act) -> String {
        let clock = { (d: Date) in DateFormatter.localizedString(from: d, dateStyle: .none, timeStyle: .short) }
        let later = { (m: Int) in clock(Date().addingTimeInterval(Double(m) * 60)) }
        switch act {
        case .snooze(let m): return "✓ Break reminders paused until \(later(m))"
        case .focus(let m): return "✓ Focus session until \(later(m)), then a short break"
        case .remind(let what, let at):
            let left = at.timeIntervalSinceNow
            let when = left < 120 ? "in \(Int(left.rounded())) seconds" : "\(clock(at)) \(Calendar.current.isDateInToday(at) ? "today" : "tomorrow")"
            return "✓ Reminder: \(what), \(when)"
        case .weather: return "✓ Opened Weather"
        case .day: return ""
        }
    }

    /// Bao's tools. Durations come as a number and a unit copied from the user's words, so the model does no sums.
    static func tools(_ act: @escaping @MainActor @Sendable (Act) async -> String) -> [any Tool] {
        let int = DynamicGenerationSchema(type: Int.self), text = DynamicGenerationSchema(type: String.self)
        let unit = DynamicGenerationSchema(name: "Unit", anyOf: ["seconds", "minutes", "hours"])
        func schema(_ props: [DynamicGenerationSchema.Property]) -> GenerationSchema {
            try! GenerationSchema(root: DynamicGenerationSchema(name: "Arguments", properties: props), dependencies: [])
        }
        func seconds(_ a: GeneratedContent) -> Double? {
            guard let n = (try? a.value(Int?.self, forProperty: "amount")).flatMap({ $0 }) else { return nil }
            let u = (try? a.value(String?.self, forProperty: "unit")).flatMap { $0 } ?? "minutes"
            return Double(n) * (u == "hours" ? 3600 : u == "seconds" ? 1 : 60)
        }
        let length = [DynamicGenerationSchema.Property(name: "amount", description: "The number the user said", schema: int),
                      .init(name: "unit", schema: unit)]
        let minutes = { (a: GeneratedContent) in min(max(Int(((seconds(a) ?? 3600) / 60).rounded(.up)), 1), 480) }
        return [
            BaoTool(name: "set_reminder", description: "Remind the user about something later, after an amount of time or at a clock time.",
                    parameters: schema([
                        .init(name: "what", description: "What to remind them about", schema: text),
                        .init(name: "amount", description: "For 'in 30 seconds' or 'in 2 hours': the number", schema: int, isOptional: true),
                        .init(name: "unit", schema: unit, isOptional: true),
                        .init(name: "hour", description: "For a clock time: the hour, 0 to 23", schema: int, isOptional: true),
                        .init(name: "minute", description: "For a clock time: the minute", schema: int, isOptional: true),
                    ])) { a in
                let what = try a.value(String.self, forProperty: "what")
                let at: Date?
                if let s = seconds(a) { at = Date().addingTimeInterval(s) }
                else {
                    at = Brain.reminderDate(hour: (try? a.value(Int?.self, forProperty: "hour")).flatMap { $0 },
                                            minute: (try? a.value(Int?.self, forProperty: "minute")).flatMap { $0 }, inMinutes: nil, now: Date())
                }
                guard let at else { return "No time was given. Ask the user when." }
                return await act(.remind(what, at: at))
            },
            BaoTool(name: "start_focus", description: "Start a focus session, only when the user asks for one: Bao stays quiet for that long, then calls a short break.",
                    parameters: schema(length)) { a in await act(.focus(minutes: minutes(a))) },
            BaoTool(name: "pause_break_reminders", description: "Stop Bao's break reminders for a while.",
                    parameters: schema(length)) { a in await act(.snooze(minutes: minutes(a))) },
            BaoTool(name: "open_weather", description: "Open the Weather app. Bao cannot see the weather itself.",
                    parameters: schema([])) { _ in await act(.weather) },
            BaoTool(name: "screen_time_today", description: "Only when the user asks about their own screen time, breaks or eye rests today.",
                    parameters: schema([])) { _ in await act(.day) },
            BaoTool(name: "current_time", description: "The date, day and time now. Use it when the user asks what time, day or date it is.",
                    parameters: schema([])) { _ in Date().formatted(date: .complete, time: .shortened) },
        ]
    }

    private var chat: LanguageModelSession?
    private var tools: [any Tool] = []
    private var persona = Companion.chatPersona  // with today's mood added
    private var receipts: [String] = []         // what the tools did during the current reply
    private var opener: String?                 // a line Bao said in its bubble that the user clicked to answer
    private var lineTimes: [Date] = []
    private var busy = false

    /// Opens a conversation. It lives only in memory and ends when the chat closes. `perform` carries out acts.
    func startChat(mood: Temper? = nil, _ perform: @escaping @MainActor @Sendable (Act) async -> String) {
        guard Self.available else { return }
        persona = Self.chatPersona + (mood.map { "\nToday you feel \($0.rawValue), and it shows a little." } ?? "")
        tools = Self.tools { [weak self] act in
            guard act == .day || self?.receipts.isEmpty == true else { return "Already done. Do nothing else." }   // one action per reply:
            let result = await perform(act)                                                                      // the model sometimes
            if act != .day { self?.receipts.append(result) }                                                     // calls a second tool
            return result
        }
        chat = LanguageModelSession(tools: tools, instructions: persona)
        chat?.prewarm()                       // load the model now, so the first reply is not the slow one
    }

    func endChat() { chat = nil }

    /// The user clicked one of Bao's bubble lines to answer it.
    func heard(_ line: String) { opener = line }

    /// One model call: Bao's reply streams, calling `partial` with the text so far, and any tool it used adds a receipt.
    func reply(to text: String, face: String = "(ᵔᴥᵔ)", partial: @escaping (String) -> Void) async -> String {
        guard chat != nil else { return "(˘ᴥ˘) I'm a little sleepy, open the chat again?" }
        let prompt = opener.map { "(You just said: \"\($0)\")\n\n\(text)" } ?? text
        opener = nil
        receipts = []
        var failure = ""
        for attempt in 0..<2 {
            do {
                var said = ""
                for try await snapshot in chat!.streamResponse(to: prompt) {
                    said = snapshot.content
                    partial(said)
                }
                let done = ([Self.finish(said, face: face)] + receipts).joined(separator: "\n")
                partial(done)
                return done
            } catch {
                FileHandle.standardError.write(Data("companion error: \(error)\n".utf8))
                // the talk outgrew the model's memory, or the safety filter misfired: try once more in a fresh session
                if attempt == 0, Self.isFull(error) || Self.isUnsafe(error) {
                    chat = LanguageModelSession(tools: tools, instructions: persona)
                    continue
                }
                // macOS refused to run the model under critical memory pressure: ModelManagerError 1013 on older
                // systems, "Not executed due to current system state [CriticalMemoryPressure]" on macOS 27
                failure = Self.isUnsafe(error) ? "(•ᴥ•) I can't help with that one. Ask me something else?"
                        : ["Code=1013", "MemoryPressure"].contains(where: "\(error)".contains)
                        ? "(˘ᴥ˘) Your Mac is low on memory, so macOS paused my thinking. Close an app or two and ask again?"
                        : "(•ᴥ•) My thoughts got tangled. Can you ask again?"
                break
            }
        }
        partial(failure)
        return failure
    }

    private static func isFull(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
        if #available(macOS 27, *), case LanguageModelError.contextSizeExceeded = error { return true }
        return false
    }

    private static func isUnsafe(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.guardrailViolation = error { return true }
        if #available(macOS 27, *), case LanguageModelError.guardrailViolation = error { return true }
        return false
    }

    /// A short line for one of the panda's moments. At most four an hour, one at a time; nil when not now.
    func line(for moment: String, context: String, mood: Temper? = nil, face: String = "(ᵔᴥᵔ)") async -> String? {
        let now = Date()
        lineTimes = lineTimes.filter { now.timeIntervalSince($0) < 3600 }
        guard Self.available, !busy, lineTimes.count < 4 else { return nil }
        busy = true
        lineTimes.append(now)
        defer { busy = false }
        let session = LanguageModelSession(instructions: Self.linePersona + (mood.map { "\nToday you feel \($0.rawValue), and it shows in every line." } ?? ""))
        let hour = Calendar.current.component(.hour, from: Date())
        guard let text = try? await session.respond(to: "App facts: \(Self.steer(context, hour: hour))\nMoment: \(moment) Say one short line to the user.").content
        else { return nil }
        return Self.finish(text, face: face)
    }
}
