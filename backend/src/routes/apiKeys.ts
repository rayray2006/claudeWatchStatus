import { Hono } from 'hono'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '../db/client.js'
import { apiKeys } from '../db/schema.js'
import { generateApiKey } from '../auth/apiKey.js'
import { requireSession } from '../middleware/sessionAuth.js'

export const apiKeyRoutes = new Hono()
apiKeyRoutes.use('*', requireSession)

/** POST /v1/api-keys — create a new API key. Returns the raw key ONCE. */
apiKeyRoutes.post('/', async (c) => {
    const userId = c.get('userId')

    let body: { label?: string } = {}
    try {
        body = await c.req.json()
    } catch {
        /* optional body */
    }

    const key = generateApiKey()
    const inserted = await db
        .insert(apiKeys)
        .values({
            userId,
            keyHash: key.hash,
            keyPrefix: key.prefix,
            label: body.label?.trim() || null,
        })
        .returning({ id: apiKeys.id, createdAt: apiKeys.createdAt })

    return c.json({
        id: inserted[0].id,
        key: key.raw,            // shown once
        prefix: key.prefix,
        createdAt: inserted[0].createdAt,
    })
})

/** GET /v1/api-keys — list active keys (never returns raw values). */
apiKeyRoutes.get('/', async (c) => {
    const userId = c.get('userId')
    const rows = await db
        .select({
            id: apiKeys.id,
            prefix: apiKeys.keyPrefix,
            label: apiKeys.label,
            createdAt: apiKeys.createdAt,
            lastUsedAt: apiKeys.lastUsedAt,
        })
        .from(apiKeys)
        .where(and(eq(apiKeys.userId, userId), isNull(apiKeys.revokedAt)))
    return c.json({ keys: rows })
})

/** DELETE /v1/api-keys/:id — revoke. */
apiKeyRoutes.delete('/:id', async (c) => {
    const userId = c.get('userId')
    const id = c.req.param('id')
    await db
        .update(apiKeys)
        .set({ revokedAt: new Date() })
        .where(and(eq(apiKeys.id, id), eq(apiKeys.userId, userId)))
    return c.json({ ok: true })
})
