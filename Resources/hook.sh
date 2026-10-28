#!/bin/sh
# Coding-agent hook: Bao (PandaPal) says what just happened, starting with a short name for the session.
#   turn finished:  a small model reads the agent's last reply and writes a short line, or NONE when you
#                   are not needed (needed: finished work, a question for you, a failure). NONE, no bubble.
#   needs you:      the agent's own message (a permission prompt or a question)
# Agents run it as `PandaPal --hook claude|codex`, with the event JSON on stdin; "Connect coding agents…" in
# Bao's menu adds those hooks.
[ -n "$BAO_SUMMARY" ] && exit 0     # the summary call below is a Claude session too: never summarize it
BAO=${BAO:?run it through PandaPal --hook}
CLAUDE=$(command -v claude || echo "$HOME/.local/bin/claude")
agent=${1:-claude}
input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty"; }

# Who writes the line: "<tool> [model]" in the summarizer file, for example "codex gpt-5.6-luna", "claude haiku",
# "gemini gemini-2.5-flash", "opencode <provider/model>" or "off". "Connect coding agents…" sets it. Default: the
# agent's own maker, so a reply goes back to the company that wrote it.
read -r tool model 2>/dev/null < "$HOME/Library/Application Support/PandaPal/summarizer"
tool=${tool:-$agent}
ASK="You write one line for Bao, a desktop panda that tells a user when a coding agent needs them. The input is the \
agent's last reply. If the reply finishes work the user waited for, asks the user for a decision or input, or reports \
a failure, write its main point in at most 12 words: what happened or what the agent needs. Leave out details such as \
times, counts and reasons. Otherwise write NONE. Write only that line, as plain text."
# 60 s at most: a tool that waits for a login must never hang the hook
limit() { BAO_SUMMARY=1 perl -e 'alarm 60; exec @ARGV' "$@"; }
# claude: about 3 s and 800 tokens, with no tools, MCP servers, hooks, CLAUDE.md, memory or saved session
summary() {
  reply=$(head -c 6000)
  case "$tool" in
    claude) printf '%s' "$reply" | limit env CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 "$CLAUDE" -p \
              --model "${model:-haiku}" --effort low --tools "" --strict-mcp-config --disable-slash-commands \
              --no-session-persistence --settings '{"disableAllHooks":true}' --system-prompt "$ASK" ;;
    codex) limit codex exec --ephemeral --skip-git-repo-check -s read-only -m "${model:-gpt-5.6-luna}" \
             -c model_reasoning_effort=low "$ASK

Reply:
$reply" ;;
    # NO_BROWSER: a missing Gemini login never opens a login page
    gemini) limit env NO_BROWSER=true gemini -m "${model:-gemini-2.5-flash}" -p "$ASK

Reply:
$reply" ;;
    opencode) limit opencode run ${model:+-m "$model"} "$ASK

Reply:
$reply" ;;
  esac 2>/dev/null </dev/null | perl -pe 's/\e\[[0-9;]*m//g' | grep -vix 'none\.\{0,1\}' | grep . | tail -n 1
}
# whole words, at most 3 of them and 24 characters
short() { awk '{ out = ""; for (i = 1; i <= NF && i <= 3; i++) { w = (out == "" ? $i : out " " $i); if (length(w) > 24) break; out = w }
                 print (out == "" ? substr($1, 1, 24) : out) }'; }

case "$agent" in
  claude)
    transcript=$(field .transcript_path)
    case "$(field .hook_event_name)" in
      Notification) text=$(field .message) ;;
      Stop)
        text=$(field .last_assistant_message)
        if [ -z "$text" ] && [ -f "$transcript" ]; then
          text=$(tail -n 400 "$transcript" |
            jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty')
        fi
        [ -z "$text" ] || text=$(printf '%s\n' "$text" | summary)
        ;;
    esac
    # the title you gave the session with /rename, else the one Claude Code gave it
    if [ -f "$transcript" ]; then
      name=$(grep '"type":"custom-title"' "$transcript" | tail -1 | jq -r '.customTitle // empty')
      [ -n "$name" ] || name=$(grep '"type":"ai-title"' "$transcript" | tail -1 | jq -r '.aiTitle // empty')
    fi
    ;;
  codex)
    case "$(field .hook_event_name)" in
      Stop) text=$(field .last_assistant_message); [ -z "$text" ] || text=$(printf '%s\n' "$text" | summary) ;;
      PermissionRequest)
        what=$(field .tool_input.description)
        [ -n "$what" ] || what=$(field .tool_name)
        text="Codex needs your permission${what:+: $what}"
        ;;
    esac
    # the thread name Codex keeps for the session
    sid=$(field .session_id)
    [ -n "$sid" ] && name=$(grep "\"id\":\"$sid\"" ~/.codex/session_index.jsonl 2>/dev/null | tail -1 | jq -r '.thread_name // empty')
    ;;
esac

[ -n "$text" ] || exit 0
if [ -z "$name" ]; then name=$(field .cwd); name=${name##*/}; fi     # else its folder
name=$(printf '%s' "$name" | short)
"$BAO" --say "${name:+$name · }$text"
