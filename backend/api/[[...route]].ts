import { handle } from 'hono/vercel'
import { app } from '../src/index.js'

export const config = {
    runtime: 'nodejs',
    regions: ['iad1'],
}

export const GET = handle(app)
export const POST = handle(app)
export const DELETE = handle(app)
export const PUT = handle(app)
export const PATCH = handle(app)
