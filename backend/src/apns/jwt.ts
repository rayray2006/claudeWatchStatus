import { SignJWT, importPKCS8 } from 'jose'

/**
 * APNs authentication JWT. Cached for ~50 minutes — Apple allows up to one hour
 * of reuse, and invalidates older tokens.
 */

const CACHE_TTL_MS = 50 * 60 * 1000

interface CachedJwt {
    token: string
    issuedAt: number
}

let cached: CachedJwt | null = null

async function sign(): Promise<string> {
    const keyId = mustEnv('APNS_KEY_ID')
    const teamId = mustEnv('APNS_TEAM_ID')
    const privateKeyPem = mustEnv('APNS_PRIVATE_KEY')

    const key = await importPKCS8(privateKeyPem, 'ES256')
    return new SignJWT({})
        .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
        .setIssuer(teamId)
        .setIssuedAt()
        .sign(key)
}

export async function getApnsJwt(): Promise<string> {
    const now = Date.now()
    if (cached && now - cached.issuedAt < CACHE_TTL_MS) {
        return cached.token
    }
    const token = await sign()
    cached = { token, issuedAt: now }
    return token
}

function mustEnv(name: string): string {
    const v = process.env[name]
    if (!v) throw new Error(`${name} is not set`)
    return v
}
