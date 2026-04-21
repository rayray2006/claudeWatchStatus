import { Hono } from 'hono'
import { randomBytes } from 'node:crypto'
import { and, eq, gt, isNull } from 'drizzle-orm'
import { db } from '../db/client.js'
import { apiKeys, devices, pairCodes } from '../db/schema.js'
import { generateApiKey } from '../auth/apiKey.js'

export const pairRoutes = new Hono()

// Friendly alphabet — unambiguous chars only.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
const CODE_LENGTH = 6
const PAIR_TTL_SECONDS = 30 * 60

function randomCode(): string {
    const bytes = randomBytes(CODE_LENGTH)
    let s = ''
    for (let i = 0; i < CODE_LENGTH; i++) {
        s += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length]
    }
    return s
}

/**
 * POST /v1/pair — Watch kicks off pairing.
 * Body: { apnsToken, bundleId, environment }
 * Returns: { code, expiresAt }
 */
pairRoutes.post('/', async (c) => {
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

    // A single device shouldn't accumulate pending codes — invalidate any
    // existing unclaimed ones for this APNs token before issuing a new one.
    await db
        .update(pairCodes)
        .set({ expiresAt: new Date(0) })
        .where(and(eq(pairCodes.apnsToken, apnsToken), eq(pairCodes.claimed, false)))

    // Retry loop for the (tiny) chance of collision.
    for (let attempt = 0; attempt < 5; attempt++) {
        const code = randomCode()
        const expiresAt = new Date(Date.now() + PAIR_TTL_SECONDS * 1000)
        try {
            await db.insert(pairCodes).values({
                code,
                apnsToken,
                bundleId,
                environment,
                expiresAt,
            })
            return c.json({ code, expiresAt: expiresAt.toISOString() })
        } catch {
            // Likely a unique-constraint collision on code; try again.
            continue
        }
    }

    return c.json({ error: 'pair_code_generation_failed' }, 500)
})

/**
 * GET /v1/pair/:code — Watch polls this to detect claim completion.
 * Returns: { claimed: false } while pending, { claimed: true } once the web
 * flow has completed. Expired codes return 404.
 */
pairRoutes.get('/:code', async (c) => {
    const code = c.req.param('code').toUpperCase()
    const rows = await db
        .select({
            code: pairCodes.code,
            claimed: pairCodes.claimed,
            expiresAt: pairCodes.expiresAt,
        })
        .from(pairCodes)
        .where(eq(pairCodes.code, code))
        .limit(1)

    const row = rows[0]
    if (!row || row.expiresAt.getTime() < Date.now()) {
        return c.json({ error: 'not_found' }, 404)
    }

    return c.json({ claimed: row.claimed })
})

/**
 * POST /v1/pair/:code/claim — Web client completes the pairing.
 * On success: creates a device (upserting on apns_token), generates an API
 * key, binds both to the pair code, and returns the raw key ONCE.
 *
 * Returns: { key, keyPrefix, keyId, deviceId, pushUrl }
 */
pairRoutes.post('/:code/claim', async (c) => {
    const code = c.req.param('code').toUpperCase()
    const now = new Date()

    const pending = await db
        .select()
        .from(pairCodes)
        .where(and(eq(pairCodes.code, code), eq(pairCodes.claimed, false), gt(pairCodes.expiresAt, now)))
        .limit(1)

    const pair = pending[0]
    if (!pair) {
        return c.json({ error: 'invalid_or_expired' }, 404)
    }

    // Upsert device on apns_token.
    const existingDevice = await db
        .select({ id: devices.id })
        .from(devices)
        .where(eq(devices.apnsToken, pair.apnsToken))
        .limit(1)

    let deviceId: string
    if (existingDevice[0]) {
        deviceId = existingDevice[0].id
        await db
            .update(devices)
            .set({ bundleId: pair.bundleId, environment: pair.environment, isActive: true, updatedAt: now })
            .where(eq(devices.id, deviceId))
    } else {
        const inserted = await db
            .insert(devices)
            .values({
                apnsToken: pair.apnsToken,
                bundleId: pair.bundleId,
                environment: pair.environment,
            })
            .returning({ id: devices.id })
        deviceId = inserted[0].id
    }

    // Fresh API key for this pairing.
    const key = generateApiKey()
    const keyRow = await db
        .insert(apiKeys)
        .values({
            deviceId,
            keyHash: key.hash,
            keyPrefix: key.prefix,
            label: 'paired-' + code,
        })
        .returning({ id: apiKeys.id })

    await db
        .update(pairCodes)
        .set({ claimed: true, deviceId, apiKeyId: keyRow[0].id })
        .where(eq(pairCodes.code, code))

    const pushUrl = new URL('/api/v1/push', 'https://nudge-backend-psi.vercel.app').toString()

    return c.json({
        key: key.raw,
        keyPrefix: key.prefix,
        keyId: keyRow[0].id,
        deviceId,
        pushUrl,
    })
})
