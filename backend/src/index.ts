import { Hono } from 'hono'
import { authRoutes } from './routes/auth.js'
import { deviceRoutes } from './routes/devices.js'
import { apiKeyRoutes } from './routes/apiKeys.js'
import { pushRoutes } from './routes/push.js'

export const app = new Hono()

app.get('/api/health', (c) => c.json({ ok: true, service: 'nudge' }))

app.route('/api/v1/auth', authRoutes)
app.route('/api/v1/devices', deviceRoutes)
app.route('/api/v1/api-keys', apiKeyRoutes)
app.route('/api/v1/push', pushRoutes)

app.onError((err, c) => {
    console.error('unhandled', err)
    return c.json({ error: 'internal' }, 500)
})
