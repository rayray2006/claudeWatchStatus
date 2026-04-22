import { Hono } from 'hono'
import { pairRoutes } from './routes/pair.js'
import { pushRoutes } from './routes/push.js'

export const app = new Hono()

app.get('/api/v1/health', (c) => c.json({ ok: true, service: 'nudge' }))

app.route('/api/v1/pair', pairRoutes)
app.route('/api/v1/push', pushRoutes)

app.notFound((c) => {
    let path = '/'
    try { path = new URL(c.req.url).pathname } catch {/* URL parse failed; carry on */}
    return c.json({ error: 'not_found', path }, 404)
})
app.onError((err, c) => {
    console.error('unhandled', err)
    return c.json({ error: 'internal', message: (err as Error).message }, 500)
})
