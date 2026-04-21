import { Hono } from 'hono'
import { and, eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { devices } from '../db/schema.js'
import { requireSession } from '../middleware/sessionAuth.js'

export const deviceRoutes = new Hono()

deviceRoutes.use('*', requireSession)

/** POST /v1/devices — register or refresh a watch device token. */
deviceRoutes.post('/', async (c) => {
    const userId = c.get('userId')

    let body: { apnsToken?: string; bundleId?: string; environment?: string }
    try {
        body = await c.req.json()
    } catch {
        return c.json({ error: 'invalid_body' }, 400)
    }

    const apnsToken = (body.apnsToken ?? '').trim().toLowerCase()
    const bundleId = (body.bundleId ?? '').trim()
    const environment = body.environment === 'production' ? 'production' : 'sandbox'

    if (!/^[0-9a-f]{64}$/.test(apnsToken)) {
        return c.json({ error: 'invalid_apns_token' }, 400)
    }
    if (!bundleId) {
        return c.json({ error: 'missing_bundle_id' }, 400)
    }

    // Upsert on (user_id, apns_token).
    const existing = await db
        .select({ id: devices.id })
        .from(devices)
        .where(and(eq(devices.userId, userId), eq(devices.apnsToken, apnsToken)))
        .limit(1)

    if (existing[0]) {
        await db
            .update(devices)
            .set({
                bundleId,
                environment,
                isActive: true,
                updatedAt: new Date(),
            })
            .where(eq(devices.id, existing[0].id))
        return c.json({ id: existing[0].id, created: false })
    }

    const inserted = await db
        .insert(devices)
        .values({ userId, apnsToken, bundleId, environment })
        .returning({ id: devices.id })

    return c.json({ id: inserted[0].id, created: true })
})

/** GET /v1/devices — list active devices for the user. */
deviceRoutes.get('/', async (c) => {
    const userId = c.get('userId')
    const rows = await db
        .select({
            id: devices.id,
            bundleId: devices.bundleId,
            environment: devices.environment,
            updatedAt: devices.updatedAt,
            lastPushedAt: devices.lastPushedAt,
            isActive: devices.isActive,
        })
        .from(devices)
        .where(eq(devices.userId, userId))
    return c.json({ devices: rows })
})

/** DELETE /v1/devices/:id — soft-remove (mark inactive). */
deviceRoutes.delete('/:id', async (c) => {
    const userId = c.get('userId')
    const id = c.req.param('id')
    await db
        .update(devices)
        .set({ isActive: false })
        .where(and(eq(devices.id, id), eq(devices.userId, userId)))
    return c.json({ ok: true })
})
