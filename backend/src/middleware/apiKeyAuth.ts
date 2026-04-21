import type { MiddlewareHandler } from 'hono'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '../db/client.js'
import { apiKeys } from '../db/schema.js'
import { hashApiKey, parseBearer } from '../auth/apiKey.js'

declare module 'hono' {
    interface ContextVariableMap {
        apiKeyUserId: string
        apiKeyId: string
    }
}

/**
 * Authenticates a request using a bearer API key. Looks up by sha256 hash,
 * updates last_used_at, and rejects revoked keys.
 */
export const requireApiKey: MiddlewareHandler = async (c, next) => {
    const raw = parseBearer(c.req.header('authorization'))
    if (!raw) {
        return c.json({ error: 'missing_api_key' }, 401)
    }

    const hash = hashApiKey(raw)
    const rows = await db
        .select({ id: apiKeys.id, userId: apiKeys.userId })
        .from(apiKeys)
        .where(and(eq(apiKeys.keyHash, hash), isNull(apiKeys.revokedAt)))
        .limit(1)

    const row = rows[0]
    if (!row) {
        return c.json({ error: 'invalid_api_key' }, 401)
    }

    c.set('apiKeyUserId', row.userId)
    c.set('apiKeyId', row.id)

    // Best-effort last-used stamp; don't block the request on it.
    db.update(apiKeys)
        .set({ lastUsedAt: new Date() })
        .where(eq(apiKeys.id, row.id))
        .execute()
        .catch(() => {/* ignore */})

    await next()
}
