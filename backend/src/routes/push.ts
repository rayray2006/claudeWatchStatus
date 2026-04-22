import { Hono } from 'hono'
import { and, eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { devices } from '../db/schema.js'
import { requireApiKey } from '../middleware/apiKeyAuth.js'
import { isPermanentFailure, sendPush, type InterruptionLevel, type Status } from '../apns/push.js'

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
