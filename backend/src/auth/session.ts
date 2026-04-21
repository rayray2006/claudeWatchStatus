import { SignJWT, jwtVerify } from 'jose'

const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60 // 30 days
const ISSUER = 'nudge'
const AUDIENCE = 'nudge-app'

function secret(): Uint8Array {
    const raw = process.env.SESSION_SECRET
    if (!raw) throw new Error('SESSION_SECRET is not set')
    return new TextEncoder().encode(raw)
}

export interface SessionClaims {
    userId: string
}

export async function issueSessionToken(claims: SessionClaims): Promise<string> {
    return new SignJWT({ uid: claims.userId })
        .setProtectedHeader({ alg: 'HS256' })
        .setIssuer(ISSUER)
        .setAudience(AUDIENCE)
        .setIssuedAt()
        .setExpirationTime(`${SESSION_TTL_SECONDS}s`)
        .sign(secret())
}

export async function verifySessionToken(token: string): Promise<SessionClaims> {
    const { payload } = await jwtVerify(token, secret(), {
        issuer: ISSUER,
        audience: AUDIENCE,
    })
    const userId = payload.uid
    if (typeof userId !== 'string' || userId.length === 0) {
        throw new Error('session token missing uid')
    }
    return { userId }
}
