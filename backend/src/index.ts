import { Hono } from 'hono'
import { authRoutes } from './routes/auth.js'
import { deviceRoutes } from './routes/devices.js'
import { apiKeyRoutes } from './routes/apiKeys.js'
import { pushRoutes } from './routes/push.js'

// Routes live at /api/v1/* — matching Vercel's catch-all file `api/[[...route]].ts`.
// No vercel.json rewrites; users hit the full path directly.
export const app = new Hono()

// /api/health lives under the v1 catch-all so it's reachable (Vercel's
// catch-all only matches /api/v1/*).
app.get('/api/v1/health', (c) => c.json({ ok: true, service: 'nudge' }))

app.route('/api/v1/auth', authRoutes)
app.route('/api/v1/devices', deviceRoutes)
app.route('/api/v1/api-keys', apiKeyRoutes)
app.route('/api/v1/push', pushRoutes)

app.notFound((c) => c.json({ error: 'not_found', path: new URL(c.req.url).pathname }, 404))
app.onError((err, c) => {
    console.error('unhandled', err)
    return c.json({ error: 'internal', message: (err as Error).message }, 500)
})
