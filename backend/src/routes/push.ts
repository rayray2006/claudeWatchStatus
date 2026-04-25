import { Hono } from 'hono'
import { and, eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { devices } from '../db/schema.js'
import { requireApiKey } from '../middleware/apiKeyAuth.js'
import { isPermanentFailure, sendComplicationPush, sendPush, type InterruptionLevel, type Status } from '../apns/push.js'

const ATTENTION: ReadonlySet<Status> = new Set(['done', 'approval'])

export const pushRoutes = new Hono()

const VALID_STATES: ReadonlySet<Status> = new Set(['idle', 'thinking', 'working', 'done', 'approval'])
const VALID_LEVELS: ReadonlySet<InterruptionLevel> = new Set(['passive', 'active', 'time-sensitive', 'critical'])

/**
 * POST /v1/push — the Mac Claude Code hook hits this with an API key and a
 * state string. Every API key is scoped to a single device (1:1 pairing);
 * we look up the device and forward the push via APNs.
 */
pushRoutes.post('/', requireApiKey, async (c) => {
    const deviceId = c.get('apiKeyDeviceId')

    let body: { status?: string; level?: string }
    try {
        body = await c.req.json()
    } catch {
        return c.json({ error: 'invalid_body' }, 400)
    }

    const status = body.status as Status
    if (!VALID_STATES.has(status)) {
        return c.json({ error: 'invalid_status' }, 400)
    }

    let level: InterruptionLevel | undefined
    if (body.level) {
        if (!VALID_LEVELS.has(body.level as InterruptionLevel)) {
            return c.json({ error: 'invalid_level' }, 400)
        }
        level = body.level as InterruptionLevel
    }

    const rows = await db
        .select({
            id: devices.id,
            apnsToken: devices.apnsToken,
            complicationToken: devices.complicationToken,
            bundleId: devices.bundleId,
            environment: devices.environment,
            lastPushedAt: devices.lastPushedAt,
        })
        .from(devices)
        .where(and(eq(devices.id, deviceId), eq(devices.isActive, true)))
        .limit(1)

    const device = rows[0]
    if (!device) {
        return c.json({ delivered: 0, invalidated: 0, warning: 'no_active_device' })
    }

    const env = device.environment === 'production' ? 'production' : 'sandbox'

    // Routing for done/approval:
    //   1. Always send the regular alert push (NSE updates cache; system plays
    //      haptic when the watch is in a state to receive it; gives us a
    //      visible Notification Center entry).
    //   2. If the device has registered a PushKit complication token, ALSO
    //      send a complication wake push. This wakes the app from deep
    //      suspension via PKPushRegistry so the handler runs (and as a
    //      backstop the handler plays the user's chosen haptic, debounced
    //      against the regular push that just landed).
    // For idle/thinking/working: regular alert only — silent, just for cache.
    let result = await sendPush(
        { token: device.apnsToken, bundleId: device.bundleId, environment: env },
        status,
        level,
    )

    if (!result.ok && !isPermanentFailure(result)) {
        // One retry for transient errors.
        await new Promise((r) => setTimeout(r, 500))
        result = await sendPush(
            { token: device.apnsToken, bundleId: device.bundleId, environment: env },
            status,
            level,
        )
    }

    // PushKit complication wake — only spend a wake when the app is *likely*
    // deep-suspended. Heuristic: if the previous push happened within the
    // last 60s, the app is almost certainly still warm enough that
    // didReceiveRemoteNotification will fire on the regular alert path and
    // play the haptic — no wake needed. Outside that window, deep suspension
    // is plausible, so spend the wake to wake the app's PKPushRegistry
    // delegate. APNs returns 200 even when the watch can't deliver (no
    // complication on face), so we fire-and-forget.
    const WAKE_WARM_WINDOW_MS = 60_000
    const previousPushAt = device.lastPushedAt?.getTime() ?? 0
    const sinceLast = Date.now() - previousPushAt
    const appLikelyDeepSuspended = previousPushAt === 0 || sinceLast > WAKE_WARM_WINDOW_MS

    let wakeDecision: 'sent' | 'skipped_warm' | 'skipped_no_token' | 'skipped_not_attention' | 'skipped_level_override'
    if (!ATTENTION.has(status)) {
        wakeDecision = 'skipped_not_attention'
    } else if (!device.complicationToken) {
        wakeDecision = 'skipped_no_token'
    } else if (level) {
        wakeDecision = 'skipped_level_override'
    } else if (!appLikelyDeepSuspended) {
        wakeDecision = 'skipped_warm'
    } else {
        wakeDecision = 'sent'
        void sendComplicationPush(
            { token: device.complicationToken, bundleId: device.bundleId, environment: env },
            status,
        )
    }
    const sinceLastSec = previousPushAt === 0 ? null : Math.round(sinceLast / 1000)

    if (result.ok) {
        db.update(devices)
            .set({ lastPushedAt: new Date() })
            .where(eq(devices.id, device.id))
            .execute()
            .catch(() => {/* ignore */})
        return c.json({ delivered: 1, invalidated: 0, wake: wakeDecision, sinceLastSec })
    }

    if (isPermanentFailure(result)) {
        db.update(devices)
            .set({ isActive: false })
            .where(eq(devices.id, device.id))
            .execute()
            .catch(() => {/* ignore */})
        return c.json({ delivered: 0, invalidated: 1, error: result.reason })
    }

    return c.json({ delivered: 0, invalidated: 0, error: result.reason }, 502)
})
