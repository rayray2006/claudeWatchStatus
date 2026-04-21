# Nudge backend

The push-relay backend for Nudge (App Store release). Receives state pushes
from users' Macs and forwards them to their registered Apple Watch devices
via APNs.

## Tech

- Node.js 20+ on Vercel serverless functions
- Hono for routing
- Neon Postgres + Drizzle ORM
- `jose` for JWT (Apple Sign-In verification, session tokens, APNs JWTs)

## Deployment (first-time)

### 1. Apple Developer portal

You need a paid Apple Developer account ($99/yr).

Register these bundle IDs at `https://developer.apple.com/account/resources/identifiers/list`:

- `com.fm.claudetap` (iOS app)
- `com.fm.claudetap.watchapp` (watchOS app)
- `com.fm.claudetap.watchapp.widget` (complication)
- `com.fm.claudetap.watchapp.notifservice` (NSE)

On each, enable the **Push Notifications** capability (both dev + prod).

Generate an **APNs Auth Key** at `https://developer.apple.com/account/resources/authkeys/list`.
Download the `.p8` file — you only get it once. Note the Key ID.

Note your Team ID from the top-right of the developer portal.

### 2. Neon Postgres

Sign up at https://neon.tech (free tier is plenty).
Create a project called `nudge`. Copy the connection string (the `DATABASE_URL` value).

### 3. Vercel

Sign up at https://vercel.com, connect your GitHub account, import this repo.
Set the project root to `backend/`.

### 4. Environment variables

In the Vercel project settings → Environment Variables, add:

| Name | Value | Notes |
|------|-------|-------|
| `DATABASE_URL` | Neon connection string | `?sslmode=require` appended |
| `SESSION_SECRET` | `openssl rand -base64 48` | random 32+ byte secret |
| `APNS_KEY_ID` | from step 1 | 10-char identifier |
| `APNS_TEAM_ID` | from step 1 | 10-char identifier |
| `APNS_PRIVATE_KEY` | full `.p8` file contents | include BEGIN/END lines |
| `APNS_ENV` | `production` | or `sandbox` for dev tokens |
| `BUNDLE_ID` | `com.fm.claudetap.watchapp` | watch app bundle id |
| `APPLE_AUDIENCE` | `com.fm.claudetap` | iOS app bundle id (SIWA `aud` field) |

Add these to **Production**, **Preview**, and **Development** environments.

### 5. First deploy

```
cd backend
vercel link
vercel env pull .env.local        # pulls the vars you set above
npm install
npm run db:migrate                # applies migrations/0000_init.sql to Neon
vercel --prod
```

After `vercel --prod`, you'll get a URL like `https://nudge-xxx.vercel.app`.
The `/v1/*` routes are served from there.

## Local development

```
npm install
cp .env.example .env.local
# fill in .env.local with local or Neon dev credentials
npm run db:migrate
npm run dev            # starts `vercel dev` at localhost:3000
```

## API

All routes under `/v1`.

### Auth (iOS/Watch)

| Route | Method | Auth | Notes |
|-------|--------|------|-------|
| `/v1/auth/apple` | POST | none | Body `{ identityToken }`. Returns `{ sessionToken }`. |
| `/v1/auth/account` | DELETE | session | Permanently deletes user + cascade. |

### Devices (iOS/Watch, session-auth)

| Route | Method | Notes |
|-------|--------|-------|
| `/v1/devices` | POST | Body `{ apnsToken, bundleId, environment }`. Idempotent upsert. |
| `/v1/devices` | GET | List user's devices. |
| `/v1/devices/:id` | DELETE | Mark inactive. |

### API keys (iOS, session-auth)

| Route | Method | Notes |
|-------|--------|-------|
| `/v1/api-keys` | POST | Body `{ label? }`. Returns `{ key }` ONCE. |
| `/v1/api-keys` | GET | List (prefix + metadata only). |
| `/v1/api-keys/:id` | DELETE | Revoke. |

### Push (Mac hook, api-key-auth)

| Route | Method | Notes |
|-------|--------|-------|
| `/v1/push` | POST | Body `{ status }`. Forwards to all active devices. |

## Testing without the apps

Once deployed, you can manually create a user + key via SQL in Neon's console,
then curl the push endpoint. Simpler path: wait until the iOS app is built to
go through the real flow.

## Structure

```
backend/
├── api/[[...route]].ts          # Vercel entry; forwards everything to Hono
├── src/
│   ├── index.ts                 # Hono app
│   ├── db/{client,schema,migrate}.ts
│   ├── auth/{apple,session,apiKey}.ts
│   ├── apns/{jwt,push}.ts
│   ├── routes/{auth,devices,apiKeys,push}.ts
│   └── middleware/{sessionAuth,apiKeyAuth}.ts
├── migrations/0000_init.sql
└── vercel.json                  # rewrites /v1/* → /api/v1/*
```
