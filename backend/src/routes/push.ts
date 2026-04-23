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
        })
        .from(devices)
        .where(and(eq(devices.id, deviceId), eq(devices.isActive, true)))
        .limit(1)

    const device = rows[0]
    if (!device) {
        return c.json({ delivered: 0, invalidated: 0, warning: 'no_active_device' })
    }

    const env = device.environment === 'production' ? 'production' : 'sandbox'

    // Routing decision:
    //   - done/approval: send via the PushKit complication channel ONLY when
    //     a complication token is registered. This wakes the watch app from
    //     deep suspension so its haptic fires reliably. No regular alert
    //     push — that would be a duplicate.
    //   - All other states (or done/approval before complication is set up):
    //     regular alert push so the NSE updates the cache.
    const useComplication = ATTENTION.has(status) && !!device.complicationToken && !level
    let result = useComplication
        ? await sendComplicationPush(
            { token: device.complicationToken!, bundleId: device.bundleId, environment: env },
            status,
        )
        : await sendPush(
            { token: device.apnsToken, bundleId: device.bundleId, environment: env },
            status,
            level,
        )

    if (!result.ok && !isPermanentFailure(result)) {
        // One retry for transient errors.
        await new Promise((r) => setTimeout(r, 500))
        result = useComplication
            ? await sendComplicationPush(
                { token: device.complicationToken!, bundleId: device.bundleId, environment: env },
                status,
            )
            : await sendPush(
                { token: device.apnsToken, bundleId: device.bundleId, environment: env },
                status,
                level,
            )
    }

    // Fallback: complication push hit a permanent failure (often "no
    // complication on active face"). Fall through to the regular alert path
    // so the user still gets *something*. Don't loop again on regular failure.
    if (useComplication && isPermanentFailure(result)) {
        result = await sendPush(
            { token: device.apnsToken, bundleId: device.bundleId, environment: env },
            status,
            level,
        )
    }

    if (result.ok) {
        db.update(devices)
            .set({ lastPushedAt: new Date() })
            .where(eq(devices.id, device.id))
            .execute()
            .catch(() => {/* ignore */})
        return c.json({ delivered: 1, invalidated: 0 })
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
