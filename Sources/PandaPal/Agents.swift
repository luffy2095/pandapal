import Foundation

/// Adds Bao's hooks to the coding agents on this Mac, and takes them out again. Each agent's settings keep
/// everything else, the file keeps its permissions, and the first change saves a copy beside it.
enum Agents {
    /// Who writes Bao's short line when an agent finishes: a title for the menu, and the summarizer file's text.
    static let summarizers: [(title: String, value: String)] = [
        ("Each agent's own model", ""),
        ("Claude Haiku", "claude haiku"),
        ("GPT-5.6 Luna, through Codex", "codex gpt-5.6-luna"),
        ("Gemini Flash, through Gemini CLI", "gemini gemini-2.5-flash"),
        ("None: only prompts and questions", "off"),
    ]

    static func summarizerFile(_ home: URL) -> URL { home.appendingPathComponent("Library/Application Support/PandaPal/summarizer") }

    /// The agents installed for this user, by the folders they keep their settings in.
    static func found(home: URL) -> [String] {
        [("Claude Code", ".claude"), ("Codex", ".codex"), ("opencode", ".config/opencode")]
            .filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.1).path) }.map(\.0)
    }

    /// Adds the hooks to every agent found, calling `bao` (PandaPal's executable), or takes them out when `bao` is nil.
    /// Returns the agents changed.
    static func connect(home: URL, bao: String?, summarizer: String) throws -> [String] {
        let agents = found(home: home)
        let command = { (agent: String) in bao.map { "\"\($0)\" --hook \(agent)" } }
        if agents.contains("Claude Code") {
            try edit(home.appendingPathComponent(".claude/settings.json"),
                     events: [("Notification", "permission_prompt|elicitation_dialog"), ("Stop", nil)], command: command("claude"))
        }
        if agents.contains("Codex") {
            try edit(home.appendingPathComponent(".codex/hooks.json"), events: [("Stop", nil), ("PermissionRequest", nil)],
                     command: command("codex"))
        }
        if agents.contains("opencode") {
            let plugin = home.appendingPathComponent(".config/opencode/plugins/bao.ts")
            if let bao {
                try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
                try opencodePlugin(bao).write(to: plugin, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: plugin)
            }
        }
        let file = summarizerFile(home)
        if bao != nil, !summarizer.isEmpty {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (summarizer + "\n").write(to: file, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
        return agents
    }

    /// Rewrites one agent's JSON settings with `merged`. A file that is not JSON is never touched.
    static func edit(_ file: URL, events: [(String, String?)], command: String?) throws {
        let fm = FileManager.default
        var json: [String: Any] = [:]
        var permissions: Any?
        if let data = fm.contents(atPath: file.path), !data.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
            }
            json = object
            permissions = try fm.attributesOfItem(atPath: file.path)[.posixPermissions]
            let backup = file.appendingPathExtension("pandapal-backup")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
        } else if command == nil {
            return
        }
        let out = try JSONSerialization.data(withJSONObject: merged(json, events: events, command: command),
                                             options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: file, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }   // settings can hold keys
    }

    /// `json` with Bao's hook for each event set to `command`, or taken out when `command` is nil. Other hooks stay.
    static func merged(_ json: [String: Any], events: [(String, String?)], command: String?) -> [String: Any] {
        var json = json
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for (event, matcher) in events {
            var groups: [[String: Any]] = (hooks[event] as? [[String: Any]] ?? []).compactMap { group in
                let all = group["hooks"] as? [[String: Any]] ?? []
                let others = all.filter { !isBao($0["command"] as? String ?? "") }
                if others.count == all.count { return group }
                var group = group
                group["hooks"] = others
                return others.isEmpty ? nil : group
            }
            if let command {
                var group: [String: Any] = ["hooks": [["type": "command", "command": command, "async": true]]]
                if let matcher { group["matcher"] = matcher }
                groups.append(group)
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        json["hooks"] = hooks.isEmpty ? nil : hooks
        return json
    }

    /// Bao's own hooks: this app's, and the hand-made script from before the menu item existed.
    static func isBao(_ command: String) -> Bool {
        (command.contains("PandaPal") && command.contains("--hook")) || command.contains("pandapal/hook.sh")
    }

    static func opencodePlugin(_ bao: String) -> String {
        #"""
        import type { Plugin } from "@opencode-ai/plugin"

        // Added by PandaPal: Bao says when opencode needs your permission. Finished turns stay quiet: opencode's
        // events carry no text to show.
        const BAO = "\#(bao)"

        export const Bao: Plugin = async ({ $, directory }) => ({
          event: async ({ event }) => {
            if (event.type !== "permission.asked" && event.type !== "permission.updated") return
            const props = (event as any).properties ?? {}
            const what = props.message ?? props.title ?? ""
            const name = (directory ?? "").split("/").pop()
            const text = `${name ? name + " · " : ""}opencode needs your permission${what ? ": " + what : ""}`
            try { await $`${BAO} --say ${text}`.quiet() } catch {}
          },
        })

        """#
    }
}
