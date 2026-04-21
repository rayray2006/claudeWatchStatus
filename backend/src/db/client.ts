import { neon, neonConfig } from '@neondatabase/serverless'
import { drizzle } from 'drizzle-orm/neon-http'
import * as schema from './schema.js'

// Neon serverless driver — works over HTTP, suitable for Vercel serverless functions.
neonConfig.fetchConnectionCache = true

const databaseUrl = process.env.DATABASE_URL
if (!databaseUrl) {
    throw new Error('DATABASE_URL is not set')
}

const sql = neon(databaseUrl)
export const db = drizzle(sql, { schema })
export type Db = typeof db
