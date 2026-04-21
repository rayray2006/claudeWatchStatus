import { createHash, randomBytes } from 'node:crypto'

const KEY_PREFIX = 'sk_live_'
const KEY_RANDOM_BYTES = 32

export interface GeneratedApiKey {
    raw: string        // Shown to the user ONCE. We never store this.
    hash: string       // Stored in the DB for lookup on push.
    prefix: string     // First 12 chars of raw, for display in the UI.
}

/**
 * Generate a fresh API key. The raw value is shown to the user exactly once
 * during creation; only the sha256 hash is persisted.
 */
export function generateApiKey(): GeneratedApiKey {
    const raw =
        KEY_PREFIX +
        randomBytes(KEY_RANDOM_BYTES)
            .toString('base64')
            .replace(/=/g, '')
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
    return {
        raw,
        hash: hashApiKey(raw),
        prefix: raw.slice(0, 12),
    }
}

/** Hash a raw API key. High-entropy input → sha256 is sufficient (no bcrypt). */
export function hashApiKey(raw: string): string {
    return createHash('sha256').update(raw).digest('hex')
}

/** Extract a bearer token from an `Authorization: Bearer …` header. */
export function parseBearer(header: string | undefined | null): string | null {
    if (!header) return null
    const match = header.match(/^Bearer\s+(.+)$/i)
    return match ? match[1].trim() : null
}
