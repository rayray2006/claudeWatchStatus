import { Hono } from 'hono'
import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { devices } from '../db/schema.js'

export const deviceRoutes = new Hono()

/**
 * POST /api/v1/device/complication-token — the watch app hits this when
 * PushKit hands it a fresh token for the .complication push type. Authenticates
 * by APNs token (which the watch already knows natively, no API-key handoff
 * required) and updates the device record with the new complication token.
 *
 * Body: { apnsToken: string, complicationToken: string }
 */
deviceRoutes.post('/complication-token', async (c) => {
    let body: { apnsToken?: string; complicationToken?: string }
    try {
        body = await c.req.json()
    } catch {
        return c.json({ error: 'invalid_body' }, 400)
    }

    const apnsToken = (body.apnsToken ?? '').trim().toLowerCase()
    const complicationToken = (body.complicationToken ?? '').trim().toLowerCase()

    if (!/^[0-9a-f]{64}$/.test(apnsToken)) {
        return c.json({ error: 'invalid_apns_token' }, 400)
    }
    if (!/^[0-9a-f]{64,}$/.test(complicationToken)) {
        return c.json({ error: 'invalid_complication_token' }, 400)
    }

    const result = await db
        .update(devices)
        .set({ complicationToken, updatedAt: new Date() })
        .where(eq(devices.apnsToken, apnsToken))
        .returning({ id: devices.id })

    if (result.length === 0) {
        return c.json({ error: 'device_not_found' }, 404)
    }

    return c.json({ ok: true })
})
