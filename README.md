# PandaPal

A panda that sits on your Mac's screen and looks after you on long screen days.

```
 ●   ●  ╽
 (●ᴥ●)ノ╪
 /(_)   ╿
```

It comes in two styles, switched from its menu. The **text panda** is the default: three lines of characters that follow macOS light and dark mode. The **kawaii panda** is a cartoon animation.

## How it behaves

It shows your needs as its own, and it never rewards screen time.

| Your need | When | The panda | Met by |
|---|---|---|---|
| Eye rest | every 20 minutes of screen time | gazes into the distance | looking away for 20 seconds |
| Movement | after 50 minutes without a break | asks for a break, slowly (below) | a break of 5 minutes or more |
| Water | about every 90 minutes | sips tea | a break |
| Daylight | once, between 12:00 and 15:00 | waves at the sun | a break of 15 minutes or more around midday |
| Wind-down | from 23:00 | yawns and gets sleepy | locking the screen |

**How it asks for a break.** It escalates slowly and steps back as soon as you take one:

1. At your next natural pause, 15 to 60 seconds without typing, it looks at you and stretches. No bubble.
2. Ten minutes later it waves with a "break?" bubble, and the menu has a suggestion.
3. Twenty minutes after that it sends one macOS notification. Then it stops asking.

It asks at most twice an hour, never interrupts mid-typing, and "Snooze for 1 hour" in its menu silences it for meetings.

**Bond.** It grows from care only: each break, every third eye rest, and locking the screen during the wind-down hour. Petting is a cute reaction and earns nothing. There are no streaks, the bond never drops, and higher bond unlocks behaviour, not points:

- From bond 10 it runs to greet you after every break.
- From bond 25 it also shows off a roll.

**Everyday life.** While you work it munches bamboo, blinks, and glances toward your pointer. Now and then it sneezes, hiccups or drops its bamboo, but never while it is asking for a break. After 25 minutes of focus it puts its bamboo down and curls up asleep beside it, so nothing moves while you work. It says good morning on your first visit before noon. While you are away it yawns, curls up and naps. After two days or more away it greets you with a big reunion.

**Personality.** It is curious, ticklish, a bit shy, sassy when pestered, a grump when woken, and quick to forgive.

**Mood of the day.** Each morning Bao picks a mood from how your last day went: curious on its first day; sleepy or grumpy after a late night or long stretches without a break; playful or cuddly after a day with plenty of breaks. It never repeats yesterday's mood when another fits. The mood tunes its rules (grumpy goes shy after 8 taps instead of 12 and pouts sooner, playful giggles at a double tap, cuddly hugs when tapped, curious notices your pointer more often, sleepy ignores it), a third of its idle moments show it, and its words carry it. A rule picks the mood, not the model: asked to choose, Apple's model contradicted the facts in 6 of 8 tries. The menu shows today's mood.

| You do | It does |
|---|---|
| tap | a pet: squish and a heart |
| double tap | high five `(●ᴥ●)ノ☆` |
| 3 quick taps | giggles `(≧ᴥ≦) hehe` |
| 8 taps in a few seconds | gets dizzy `(@ᴥ@)` |
| 12 taps in a minute | goes shy `(⁄ᴥ⁄)` for 10 seconds |
| keep tapping while it is shy | gets cutely angry `(ÒᴥÓ) ╬` and stomps until you stop |
| tap when its patience is low | pouts `(¬ᴥ¬) hmph` |
| press and hold | a hug `⊂(ᵔᴥᵔ)⊃ ♡`, which restores its patience |
| drag | dangles `\(°ᴥ°)/ wheee`; shake it and it is dizzy when dropped |
| pointer comes near | notices you `(◐ᴥ◐) ?` |
| swipe the pointer fast up and down over it | a tickle: giggles `(≧ᴥ≦) hehe` |
| tap while it naps | one eye opens `(-ᴥ•)`; 3 quick taps wake it |
| tap while it wants a break | cheers you on `\(●ᴥ●)/ go!` |

None of this earns bond. Its patience refills within a couple of minutes.

The kawaii style shows the four main moods, working, wanting a break, happy and napping, but not the smaller moments.

## Talk to it

Bao, the panda, talks through Apple's on-device model. It runs entirely on your Mac, with no network, no account and no API key. It needs macOS 26 or later with Apple Intelligence switched on.

- **Chat:** move the pointer over the panda and click the "talk?" bubble above its head. You can also click one of its own lines to answer it, or choose "Talk to Bao…" in the menu. Replies type out while its mouth moves. Closing the chat ends the conversation, and nothing is saved.
- **What it can do:** ask it anything, and it answers from what the model knows. It can also set a reminder ("remind me to call mom at 7"), start a focus session ("I need to focus for 45 minutes"), pause its break reminders ("stop bugging me for an hour"), tell you how your day is going, and open the Weather app. Bao delivers reminders herself: at the time, she waves and says it in her bubble, which stays until you click it, and the end of a focus session works the same way. If nobody can see her then (the panda is hidden, a full-screen app covers it, or the screen is locked), a macOS notification carries the reminder instead, so none is missed. Reminders wait in the saved file, so a restart keeps them; if PandaPal is not running at the time, she says it when it next starts. Each action shows a ✓ line under the reply that says exactly what was done and when, or a ✗ line if it could not be done. It cannot look up live things such as weather, news or prices, because it runs offline.
- **Speed:** each message is one call to the model. Bao's actions are tools the model calls by itself during that call, at most one per reply. The model starts loading when you open the chat, so the first reply is the slowest. Reminders and the end of a focus session are macOS notifications, so they still arrive if PandaPal quits.
- **Its own words:** after you come back from a break, when it asks for one, on your first visit in the morning, and late at night, it says a short line in a speech bubble. At most four an hour, and never while the chat is open.
- **What it knows:** what you type, plus your name if you say "my name is …" (kept only until the chat closes), plus, when you ask about your day, your screen time since the last break, today's breaks and eye rests, and your bond. It cannot see your screen, apps or files.
- **How it speaks:** in the chat, two to four sentences that answer first. In its bubble, one short line. Each ends with exactly one face that the app chooses from its mood. It never pushes more screen time, sends you to bed late at night, and if you say you feel low it suggests reaching out to someone you trust. It is a friend, not a therapist.
- **Test it from the terminal:** `open -n -W --stdout out.txt build/PandaPal.app --args --ask "hi" "remind me to stretch in 10 minutes"` asks each message in one chat and prints the replies, their timing and any action, without doing the action. `--ask --moment "The user just came back from a break."` asks for a bubble line. It goes through `open` because macOS lets apps use the model, and a plain terminal process may be refused.

## Using it

- **Click** the panda to pet it.
- **Drag** it anywhere. It remembers the spot.
- **Tap, double-tap, tap fast, press and hold, drag, shake, or hover** for its personality: see the table below.
- **Hover** over it and click "talk?" to chat.
- **Right-click** it, or click 🐼 in the menu bar, for the menu: talk to Bao, today's breaks and eye rests, snooze reminders for an hour, switch style, hide the panda, quit.

## Build and run

Needs macOS 26 or later and the Xcode command line tools with the macOS 26 SDK or newer (Swift 6.2+). It builds with `swiftc` directly, not the Swift package manager, because the package manager in Command Line Tools 27.0 cannot build manifests on this Mac.

```sh
./build.sh                      # runs the behaviour test, then builds build/PandaPal.app
open build/PandaPal.app
```

The first build downloads Lottie, about 55 MB, into `Vendor/`, and checks it against the checksum Airbnb publishes. To start PandaPal at login: System Settings, General, Login Items, then add `build/PandaPal.app`.

## Privacy

- It reads three things: whether the screen is locked or asleep, how many seconds since the last key or mouse event, and the clock. During its moments it also reads where the pointer is, to glance that way, and keeps nothing. It never sees what you type, which app you use, or what is on screen.
- It needs no permissions and makes no network connections. Bao's words come from Apple's on-device model, so they are generated on this Mac too. Chats are kept in memory only while the chat is open.
- The only permission it may ask for is notifications, once, the first time it sends its break notification or a reminder you asked for.
- It saves one small file, `~/Library/Application Support/PandaPal/memory.json`: bond, today's date, today's breaks and eye rests, longest stretch today, which daily moments already happened, when it last saw you, the same counts for your last day, today's mood, and any reminders you asked for, each deleted once Bao says it.

## Saving power

- Animations play in short moments, then the panda holds still, which costs nothing.
- Breathing runs at a low frame rate.
- Everything pauses while the panda is covered, hidden, or the screen is locked.

Measured on macOS 27, Apple silicon, 2026-10-26, panda visible and working, 3-minute averages, with the full behaviour engine ticking every 15 seconds:

| Style | PandaPal CPU | Memory footprint |
|---|---|---|
| Text panda | 0.056% | 17 MB |
| Kawaii panda | 0.34% | 20 MB |

The app is 10 MB, almost all of it the Lottie framework the kawaii panda needs.

The window compositor's share is not measured yet. It needs `powermetrics` on an otherwise idle screen.

## Art

The text panda needs no art files. Each frame is three lines in Menlo, drawn to an image once at launch, and the frames live in `Sources/PandaPal/TextPandaView.swift`.

- "Panda Waving" by Bhaskar Wary and "Sleep Panda" by Zakaria Harry Utomo, from [LottieFiles](https://lottiefiles.com), under the Lottie Simple License. That licence allows free and commercial use and modification. Attribution is optional, and the credit also appears in the app's menu.
- PandaPal changes them at load time: the waving paw is held still while the panda works, the sleeping panda's background square is removed, and its Zs are navy instead of white.
- Played with [lottie-ios](https://github.com/airbnb/lottie-ios), Apache 2.0.

## Files

- `Sources/PandaPal/Brain.swift`: needs, the break escalation, bond and daily rhythm, with no UI, so a test can run a whole day with made-up times.
- `Sources/PandaPal/Personality.swift`: how it reacts to taps, holds, drags and hovers.
- `Sources/PandaPal/Companion.swift`: Bao's voice from Apple's on-device model.
- `Sources/PandaPal/Bubbles.swift`: the speech-bubble shape, and the talk invite, Bao's lines and the chat that use it.
- `Sources/PandaPal/PandaShell.swift`: what both styles share: petting, dragging, the menu.
- `Sources/PandaPal/TextPandaView.swift`: the text panda and its frames.
- `Sources/PandaPal/PandaView.swift`: the kawaii panda, played with Lottie.
- `Sources/PandaPal/main.swift`: the menu bar, the floating window, system events and the saved file.
- `Tests/main.swift`: the behaviour and personality tests, run by `build.sh`.
- `Art/`: the two animations.
- `./build/PandaPal.app/Contents/MacOS/PandaPal --snapshot <dir>` renders a few frames to PNG, to check the art without a screen.
