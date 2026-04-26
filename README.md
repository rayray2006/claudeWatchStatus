# Cued

A standalone watchOS app that taps your wrist when your AI coding agent finishes a task or needs your approval. Hooks into Claude Code (or anything that can hit an HTTP endpoint), routes through a Vercel-hosted backend, and delivers via APNs.

```
Mac (Claude Code hook)
    │  curl POST /api/v1/push
    ▼
Vercel backend (this repo's `backend/`)
    │  HTTP/2 + JWT to APNs
    ▼
Apple Push Notification service
    │  delivery to paired/cellular watch
    ▼
watchOS app
    ├─ NSE updates state cache + complication
    └─ Main app (kept alive by HKWorkoutSession or
        WKExtendedRuntimeSession) plays your chosen haptic
```

## What you need to sideload this

This is **not a free-account sideload**. Required:

- **Paid Apple Developer account** ($99/yr) — needed for APNs key + Push Notifications + HealthKit entitlements (none of these are available to free Apple IDs)
- **Mac with Xcode 16+** (project is `WatchOS 11+`, Swift 6)
- **Apple Watch on watchOS 11+** paired to an iPhone running iOS 18+
- **Vercel account** (free tier is enough)
- **Postgres database** — Neon (free tier) is the easy path; any Postgres works
- **A domain or `*.vercel.app` subdomain** for the backend

## Architecture

```
ClaudeTap/                         iOS companion app (mostly stub; pairing UI lives on watch)
ClaudeTapWatch/                    Main watchOS app (UI, pairing, keep-alive, haptics)
ClaudeTapComplication/             Widget extension (complications + Smart Stack)
ClaudeTapNotificationService/      NSE — wakes for every push, writes cache + reloads widget
Shared/                            Constants, TapState, sprite art shared across targets
backend/                           Vercel/Hono server: pairing API, APNs JWT, push routing
project.yml                        XcodeGen config — regenerates ClaudeTap.xcodeproj
```

The watch app has two keep-alive mechanisms (Settings → Reliability):

- **Workout session** (`HKWorkoutSession.other`) — reliable indefinite background runtime, watch face shows green workout indicator
- **Extended runtime** (`WKExtendedRuntimeSession.physicalTherapy`) — lightweight, no UI intrusion, but limited to ~1 hour per session and the OS may suppress earlier

Both have on-watch logs (Settings → \[Workout|Runtime|Push\] log) for diagnosis without Xcode attached.

## Sideload setup

### 1. Apple Developer portal

Register **four** bundle IDs (replace `com.example.cued` with your prefix):

| Target | Suggested bundle ID | Capabilities |
|---|---|---|
| iOS app stub | `com.example.cued` | (none required) |
| Watch app | `com.example.cued.watchapp` | Push Notifications, App Groups, HealthKit |
| Widget extension | `com.example.cued.watchapp.widget` | App Groups |
| Notification Service | `com.example.cued.watchapp.notifservice` | App Groups |

Create an **App Group**: `group.com.example.cued`. Enable on watch app + widget + NSE.

Create an **APNs Auth Key** (developer.apple.com → Keys → +). Download the `.p8` file (only chance to download). Note the Key ID and your Team ID.

### 2. Backend

See `backend/README.md` for the full deployment walkthrough. Short version:

```bash
cd backend
npm install
cp .env.example .env.local       # fill in DATABASE_URL, APNS_KEY_ID,
                                 # APNS_TEAM_ID, APNS_PRIVATE_KEY,
                                 # APNS_ENV, BUNDLE_ID
npm run db:migrate
vercel --prod                    # deploy
```

Note your deployment URL (e.g., `https://yourname.vercel.app`).

### 3. Configure the watch app's backend URL

Edit `ClaudeTapWatch/BackendConfig.swift` so `baseURL` points at your Vercel deployment. Also update `watchBundleId` to match the bundle ID you registered for the watch target.

### 4. Update bundle IDs and team in `project.yml`

Find every line with `PRODUCT_BUNDLE_IDENTIFIER` (one per target) and replace `com.fm.claudetap` with your prefix. Update `DEVELOPMENT_TEAM` (10-char Team ID) on the watch target.

Same for `WKCompanionAppBundleIdentifier` in the watch app's Info.plist properties.

### 5. Build the watch app

```bash
brew install xcodegen   # if not installed
xcodegen                # regenerates ClaudeTap.xcodeproj from project.yml
open ClaudeTap.xcodeproj
```

In Xcode:
- Select each target → Signing & Capabilities tab → set your Team
- For the watch target, ensure the four capabilities are listed (Push Notifications, App Groups, HealthKit, Background Modes with `remote-notification`, `physical-therapy`, `workout-processing`)
- Plug in your iPhone (the watch installs through it), select your watch as the run destination, ⌘R to build and install

### 6. Pair

On the watch, Cued will show a 6-character code on first launch. Open the URL printed in the watch app on any device (or just `https://yourname.vercel.app/p`) and enter the code. The backend creates an API key bound to your watch and shows it once — copy it.

### 7. Wire the Mac hook

In `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "curl -sS -H 'Authorization: Bearer YOUR_API_KEY' -H 'content-type: application/json' -d '{\"status\":\"thinking\"}' https://yourname.vercel.app/api/v1/push >/dev/null 2>&1 &"
      }]
    }],
    "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "curl -sS -H 'Authorization: Bearer YOUR_API_KEY' -H 'content-type: application/json' -d '{\"status\":\"working\"}' https://yourname.vercel.app/api/v1/push >/dev/null 2>&1 &" }]}],
    "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "curl -sS -H 'Authorization: Bearer YOUR_API_KEY' -H 'content-type: application/json' -d '{\"status\":\"done\"}' https://yourname.vercel.app/api/v1/push >/dev/null 2>&1 &" }]}],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "curl -sS -H 'Authorization: Bearer YOUR_API_KEY' -H 'content-type: application/json' -d '{\"status\":\"approval\"}' https://yourname.vercel.app/api/v1/push >/dev/null 2>&1 &" }]},
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "curl -sS -H 'Authorization: Bearer YOUR_API_KEY' -H 'content-type: application/json' -d '{\"status\":\"approval\"}' https://yourname.vercel.app/api/v1/push >/dev/null 2>&1 &" }]}
    ]
  }
}
```

Test: run any Claude command. You should feel a haptic when it finishes (assuming Cued is open or keep-alive is on).

## Day-to-day use

**Wear-and-go reliability:** open Cued → Settings → flip on **Workout session**. Watch face shows the green workout glyph; haptics fire reliably for hours. Higher battery drain. Recommended for active coding sessions.

**Lightweight mode:** **Extended runtime** toggle. No watch face indicator, less battery, but only lasts ~1 hour per app open. Re-open the app to reset.

**Don't want either?** Leave both off. Haptics still fire when the app is foreground or recently used; you'll miss notifications when the watch is sitting idle.

## Diagnosis

Three on-watch logs in Settings → Reliability:

- **Workout log** — HKWorkoutSession lifecycle (start, state changes, errors)
- **Runtime log** — WKExtendedRuntimeSession lifecycle (start, expire, invalidate-with-reason)
- **Push log** — every push delivery + haptic outcome (foreground/background/complication, played/skipped/debounced)

Combined they tell you exactly which mechanism is in what state and whether pushes are reaching the haptic call.

## Customization

- **Sprite art:** `Shared/ClaudeSprites.swift` is generated by `server/sprite-gen.py`. Each state (idle, thinking, working, done, approval) is a 256×256 RGBA byte stream. Run the script to regenerate after editing.
- **Haptics:** 26 options in Settings → Haptics → \[state\]. Defined in `ClaudeTapWatch/HapticChoice.swift`. Add new sequenced patterns with `playSequence([(WKHapticType, delayMs), ...])`.
- **Idle timeout** for extended-runtime keep-alive: `KeepAliveManager.idleTimeout` (default 30 min).

## Limitations

- **Free Apple ID sideload doesn't work** (no APNs/HealthKit on free accounts).
- **`WKExtendedRuntimeSession` chain pattern is broken** by Apple's "app must be active" rule (Code=3 from `start()` in background). We don't try to chain — each session expires after 1 hour and you must re-open the app to get a new one.
- **`HKWorkoutSession` is App-Store-rejection-bait for non-fitness apps**. Apple has explicitly stated this in dev forums. Sideload-only.
- **AirPods connected suppresses background haptics.** watchOS routes notification audio to the buds and intentionally drops the wrist tap. No workaround.

## License

Personal project. Use at your own risk. Apple's App Store guidelines explicitly prohibit `HKWorkoutSession` use for non-fitness apps; this repo is intended for personal sideload only.
