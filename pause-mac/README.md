# Pause

A menu bar app for macOS that adds a moment of friction between an impulse and acting on it. It has four tools:

| Tool | What it does |
|---|---|
| **Speed bump** | When you open an app or website you've chosen, the screen dims and a breathing countdown starts. You type *why* you're opening it, then choose to open it for 5, 15 or 30 minutes, or **Never mind**. The wait grows each time you open it that day (10s, 15s, 20s… up to 60s). |
| **Block** | Stricter. The thing stays blocked, optionally only on a schedule (e.g. weekdays 9–5). Unlocking takes a 60-second wait and a detailed reason (40+ characters, at least 6 different real words). It only unlocks for 5 or 10 minutes. |
| **Urge log** | Press **⌥⌘U** anywhere to log "I feel an urge to ___" in two seconds, with how strong it was and whether you resisted. Every speed bump and block screen is logged too. The Urge log window shows when urges hit, what they're about, what you were doing at the time, and your resist rate. |
| **Where did my day go?** | Tracks which app (and which website, in supported browsers) is in front of you. It skips idle time but keeps counting while a video plays. It shows an hour-by-hour chart, intentional vs. distracting time, your longest focus stretch, how many times you switched apps or sites, and an end-of-day summary notification. |

Everything is stored as JSON in `~/Library/Application Support/Pause/` on your Mac. Nothing is sent anywhere.

## Build and run

Requires **macOS 13 Ventura or newer**, plus Xcode or the free Command Line Tools (`xcode-select --install`).

```bash
cd pause-mac
./build.sh --install     # builds Pause.app, copies it to /Applications, opens it
```

A pause icon (⏸) appears in the menu bar. The app has no Dock icon.

Prefer Xcode? Open the `pause-mac` folder in Xcode (File → Open, select `Package.swift`). The app still has to be launched from the built `Pause.app` bundle: notifications need a real bundle, and `swift run` won't show them.

Run the logic tests (needs full Xcode, because the Command Line Tools don't include XCTest):

```bash
swift test
```

## First-time setup

1. Click ⏸ → **Guards & settings**.
2. **Add app…** for the apps you open on autopilot, and type in websites (e.g. `reddit.com`, `youtube.com`). Choose *Speed bump* or *Block* for each one, and optionally limit it to certain hours and days.
3. The first time you use a browser, macOS asks: *"Pause wants to control Safari/Chrome."* Click **OK**. Without it, Pause can't see or guard websites. If you clicked *Don't Allow*, go to System Settings → Privacy & Security → Automation → Pause and turn the browser on.
4. Allow notifications when asked, for the end-of-day summary.
5. Turn on **Open Pause when I log in**. Guards only work while Pause is running.

## Things to know

- **Quitting Pause turns every guard off.** This is a speed bump for your impulses, not a lock you can't get around. It works by making the automatic path slower and more conscious. Removing a guard asks you to confirm first.
- **Browsers:** website tracking and guards work in Safari, Chrome, Arc, Brave, Edge and Vivaldi. **Firefox isn't supported** because it has no AppleScript support. Firefox time shows up as "Firefox" only.
- **Website detection can lag by up to ~2 seconds** after you navigate, because Pause checks the current tab every 2 seconds. Apps are caught the moment they come to the front.
- **"Never mind" on a website closes that tab.** On an app, it hides the app.
- **Rebuilding resets permissions.** The app is signed "ad-hoc" (no paid Apple developer account), so after each rebuild macOS may ask for the browser permission again.
- **Idle time:** after 3 minutes without keyboard or mouse input (adjustable), time stops counting, unless something is keeping the screen awake, like a video playing.
- **Default labels:** common sites and apps start out labelled Intentional or Distracting (e.g. YouTube and Reddit are Distracting, Xcode and Google Docs are Intentional). Everything else is Neutral. Click any label in the day report to change it.

## Project layout

```
Sources/PauseCore/    Plain Swift logic: models, guard rules, time tracking, reports, insights (unit tested)
Sources/Pause/        The macOS app: menu bar, guard screens, hotkey, windows, browser bridge
Tests/PauseCoreTests/ Tests for PauseCore
Resources/Info.plist  App bundle settings (menu-bar-only, browser permission text)
build.sh              Builds and signs Pause.app
```
