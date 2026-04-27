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

The watch app keeps itself alive in the background via `WKExtendedRuntimeSession.physicalTherapy` (Settings → Reliability → "Keep app alive"). Lightweight, no watch face UI intrusion, but Apple caps each session at 1 hour and won't let us chain new ones from the background — re-open the app to start a fresh session.

Two on-watch logs (Settings → \[Runtime|Push\] log) for diagnosis without Xcode attached.

## Sideload setup

### 1. Apple Developer portal

Register **four** bundle IDs (replace `com.example.cued` with your prefix):

| Target | Suggested bundle ID | Capabilities |
|---|---|---|
| iOS app stub | `com.example.cued` | (none required) |
| Watch app | `com.example.cued.watchapp` | Push Notifications, App Groups |
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
- For the watch target, ensure the capabilities are listed (Push Notifications, App Groups, Background Modes with `remote-notification` and `physical-therapy`)
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

**Open Cued → Settings → flip on "Keep app alive"** at the start of an active coding session. You get up to 1 hour of background coverage from that moment. Re-open the app to extend.

**Don't want it on?** Leave it off. Haptics still fire when the app is foreground or recently used; deep-suspended pushes will be missed.

## Diagnosis

Two on-watch logs in Settings → Reliability:

- **Runtime log** — `WKExtendedRuntimeSession` lifecycle (start, expire, invalidate-with-reason)
- **Push log** — every push delivery + haptic outcome (foreground/background/complication, played/skipped/debounced)

Combined they tell you exactly what state the keep-alive is in and whether pushes are reaching the haptic call.

## Customization

- **Sprite art:** `Shared/ClaudeSprites.swift` is generated by `server/sprite-gen.py`. Each state (idle, thinking, working, done, approval) is a 256×256 RGBA byte stream. Run the script to regenerate after editing.
- **Haptics:** 26 options in Settings → Haptics → \[state\]. Defined in `ClaudeTapWatch/HapticChoice.swift`. Add new sequenced patterns with `playSequence([(WKHapticType, delayMs), ...])`.
- **Idle timeout** for extended-runtime keep-alive: `KeepAliveManager.idleTimeout` (default 30 min).

## Limitations

- **Free Apple ID sideload doesn't work** (no APNs on free accounts).
- **`WKExtendedRuntimeSession` chain pattern is broken** by Apple's "app must be active" rule (Code=3 from `start()` in background). We don't try to chain — each session expires after 1 hour and you must re-open the app to get a new one.
- **`WKExtendedRuntimeSession.physicalTherapy` for non-PT apps is technically against App Store guidelines** but Apple's enforcement is inconsistent at Beta App Review. Internal TestFlight (no review) is fine; External TestFlight or App Store submission carries real rejection risk.
- **AirPods connected suppresses background haptics.** watchOS routes notification audio to the buds and intentionally drops the wrist tap. No workaround.

## TestFlight (Internal — for sharing with friends/team)

Internal TestFlight has **no Beta App Review** and tolerates the keep-alive setup as-is. Up to 100 testers, all of whom must be members of your App Store Connect team (you invite them by email).

### One-time setup

1. **App Store Connect** → My Apps → +→ **New App**. Pick the iOS app's bundle ID (`com.example.cued`). watchOS app and extensions ship as part of the iOS app's bundle — no separate App Store Connect app for the watch app.
2. Fill in the required metadata: name, primary language, SKU, user access. You don't need screenshots/description for internal TestFlight.
3. **Users and Access** → invite the people you want as Internal Testers. They need an Apple ID and access to your App Store Connect team. They install the **TestFlight** app on their iPhone.

### Per-build

1. In Xcode, select the **ClaudeTap** scheme and **Any iOS Device (arm64)** as the destination.
2. Bump build number in `project.yml` (or in Xcode's General tab) — every upload needs a unique build number for the same version.
3. **Product → Archive**. Wait for the archive to build. Organizer window opens.
4. Click **Distribute App** → **TestFlight & App Store** → **Upload**. Pick automatic signing options unless you have a specific reason not to.
5. Upload completes (~1-2 min). The build appears in App Store Connect under TestFlight after a few minutes of processing.
6. App Store Connect → TestFlight tab → click your build → fill in the **Encryption** export-compliance question (we use only standard HTTPS/APNs, so "no proprietary encryption" / Apple's exempt categories applies). The build flips to "Ready to Test."
7. Internal testers get notified automatically. They tap the build in TestFlight and install. The watch app installs to their watch via their paired iPhone.

### What testers get

Each tester:
- Installs Cued on their iPhone via TestFlight
- watchOS app auto-installs to their paired Apple Watch
- Opens the watch app, sees a 6-character pairing code
- Goes to your backend's `/p` page, enters code, gets an API key
- Wires the API key into their `~/.claude/settings.json` hooks
- Done — their watch now taps for their Claude Code activity

Each tester pairs through your backend, gets their own API key bound to their watch token. Your APNs key signs all their pushes; your Vercel/Postgres handles them all.

### External TestFlight is not recommended for this app

External (public link, up to 10,000) requires Beta App Review per build. Apple has been explicit in dev forums that `WKExtendedRuntimeSession.physicalTherapy` for non-PT use risks rejection. You'd either need to strip the keep-alive (drop reliability) or accept the rejection risk. Internal TestFlight is the realistic distribution path.

## License

Personal project. Use at your own risk. App Store distribution would likely fail review due to the keep-alive use of `WKExtendedRuntimeSession.physicalTherapy`; this repo is intended for personal sideload and Internal TestFlight only.
