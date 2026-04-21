import { Hono } from 'hono'
import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { users } from '../db/schema.js'
import { verifyAppleIdentityToken } from '../auth/apple.js'
import { issueSessionToken } from '../auth/session.js'
import { requireSession } from '../middleware/sessionAuth.js'

export const authRoutes = new Hono()

/** POST /v1/auth/apple — exchange an Apple identity token for a session. */
authRoutes.post('/apple', async (c) => {
    let body: { identityToken?: string }
    try {
        body = await c.req.json()
    } catch {
        return c.json({ error: 'invalid_body' }, 400)
    }
    if (!body.identityToken) {
        return c.json({ error: 'missing_identity_token' }, 400)
    }

    const audience = process.env.APPLE_AUDIENCE
    if (!audience) {
        return c.json({ error: 'server_misconfigured' }, 500)
    }

    let identity
    try {
        identity = await verifyAppleIdentityToken(body.identityToken, audience)
    } catch {
        return c.json({ error: 'apple_verification_failed' }, 401)
    }

    // Upsert user on apple_sub.
    const existing = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.appleSub, identity.sub))
        .limit(1)

    let userId: string
    if (existing[0]) {
        userId = existing[0].id
    } else {
        const inserted = await db
            .insert(users)
            .values({ appleSub: identity.sub })
            .returning({ id: users.id })
        userId = inserted[0].id
    }

    const session = await issueSessionToken({ userId })
    return c.json({ sessionToken: session })
})

/** DELETE /v1/auth/account — permanently delete. Cascades to devices + keys. */
authRoutes.delete('/account', requireSession, async (c) => {
    const userId = c.get('userId')
    await db.delete(users).where(eq(users.id, userId))
    return c.json({ ok: true })
})

/**
 * POST /v1/auth/dev — DEV-ONLY backdoor. Enabled only when env var
 * `ALLOW_DEV_AUTH=true`. Lets clients without Sign In with Apple (e.g. free
 * provisioning or local test harnesses) obtain a session token linked to a
 * deterministic `dev-<name>` user. MUST be disabled before App Store submission.
 */
authRoutes.post('/dev', async (c) => {
    if (process.env.ALLOW_DEV_AUTH !== 'true') {
        return c.json({ error: 'dev_auth_disabled' }, 403)
    }

    let body: { name?: string } = {}
    try { body = await c.req.json() } catch { /* optional */ }

    const rawName = (body.name ?? 'local').toString().toLowerCase()
    const safeName = rawName.replace(/[^a-z0-9-]/g, '').slice(0, 32) || 'local'
    const appleSub = `dev-${safeName}`

    const existing = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.appleSub, appleSub))
        .limit(1)

    let userId: string
    if (existing[0]) {
        userId = existing[0].id
    } else {
        const inserted = await db
            .insert(users)
            .values({ appleSub })
            .returning({ id: users.id })
        userId = inserted[0].id
    }

    const session = await issueSessionToken({ userId })
    return c.json({ sessionToken: session, userId, appleSub })
})
