import type { MiddlewareHandler } from 'hono'
import { parseBearer } from '../auth/apiKey.js'
import { verifySessionToken } from '../auth/session.js'

declare module 'hono' {
    interface ContextVariableMap {
        userId: string
    }
}

export const requireSession: MiddlewareHandler = async (c, next) => {
    const token = parseBearer(c.req.header('authorization'))
    if (!token) {
        return c.json({ error: 'missing_session_token' }, 401)
    }
    try {
        const { userId } = await verifySessionToken(token)
        c.set('userId', userId)
    } catch {
        return c.json({ error: 'invalid_session_token' }, 401)
    }
    await next()
}
