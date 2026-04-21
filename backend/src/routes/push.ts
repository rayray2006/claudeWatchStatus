import { Hono } from 'hono'
import { and, eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { devices } from '../db/schema.js'
import { requireApiKey } from '../middleware/apiKeyAuth.js'
import { isPermanentFailure, sendPush, type Status } from '../apns/push.js'

export const pushRoutes = new Hono()

const VALID_STATES: ReadonlySet<Status> = new Set(['idle', 'working', 'done', 'approval'])

/** POST /v1/push — Mac hook entry point. Forwards state to all user's devices. */
pushRoutes.post('/', requireApiKey, async (c) => {
    const userId = c.get('apiKeyUserId')

    let body: { status?: string }
    try {
        body = await c.req.json()
    } catch {
        return c.json({ error: 'invalid_body' }, 400)
    }

    const status = body.status as Status
    if (!VALID_STATES.has(status)) {
        return c.json({ error: 'invalid_status' }, 400)
    }

    const targets = await db
        .select({
            id: devices.id,
            apnsToken: devices.apnsToken,
            bundleId: devices.bundleId,
            environment: devices.environment,
        })
        .from(devices)
        .where(and(eq(devices.userId, userId), eq(devices.isActive, true)))

    if (targets.length === 0) {
        return c.json({ delivered: 0, invalidated: 0, warning: 'no_active_devices' })
    }

    let delivered = 0
    let invalidated = 0
    const errors: string[] = []

    await Promise.all(
        targets.map(async (d) => {
            const env = d.environment === 'production' ? 'production' : 'sandbox'
            const result = await sendPush(
                { token: d.apnsToken, bundleId: d.bundleId, environment: env },
                status,
            )

            if (result.ok) {
                delivered++
                db.update(devices)
                    .set({ lastPushedAt: new Date() })
                    .where(eq(devices.id, d.id))
                    .execute()
                    .catch(() => {/* ignore */})
                return
            }

            errors.push(`${result.httpStatus}:${result.reason ?? 'unknown'}`)
            if (isPermanentFailure(result)) {
                invalidated++
                db.update(devices)
                    .set({ isActive: false })
                    .where(eq(devices.id, d.id))
                    .execute()
                    .catch(() => {/* ignore */})
                return
            }

            // Transient: retry once after 500ms.
            await new Promise((r) => setTimeout(r, 500))
            const retry = await sendPush(
                { token: d.apnsToken, bundleId: d.bundleId, environment: env },
                status,
            )
            if (retry.ok) {
                delivered++
            } else {
                errors.push(`retry:${retry.httpStatus}:${retry.reason ?? 'unknown'}`)
                if (isPermanentFailure(retry)) {
                    invalidated++
                    db.update(devices)
                        .set({ isActive: false })
                        .where(eq(devices.id, d.id))
                        .execute()
                        .catch(() => {/* ignore */})
                }
            }
        }),
    )

    return c.json({ delivered, invalidated, errors })
})
