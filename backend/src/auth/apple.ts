import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose'

const APPLE_ISSUER = 'https://appleid.apple.com'
const APPLE_JWKS_URL = new URL(`${APPLE_ISSUER}/auth/keys`)

const jwks = createRemoteJWKSet(APPLE_JWKS_URL, {
    cooldownDuration: 30_000,
    cacheMaxAge: 24 * 60 * 60 * 1000, // 24 hours
})

export interface AppleIdentity {
    sub: string               // Stable Apple user id
    email?: string
    emailVerified?: boolean
    isPrivateEmail?: boolean
}

/**
 * Verify a Sign In with Apple identity token. Validates signature against
 * Apple's JWKS, checks issuer and audience, returns the stable user id.
 */
export async function verifyAppleIdentityToken(
    token: string,
    audience: string,
): Promise<AppleIdentity> {
    const { payload } = await jwtVerify(token, jwks, {
        issuer: APPLE_ISSUER,
        audience,
    })

    return {
        sub: String((payload as JWTPayload).sub ?? ''),
        email: typeof payload.email === 'string' ? payload.email : undefined,
        emailVerified:
            payload.email_verified === true || payload.email_verified === 'true',
        isPrivateEmail:
            payload.is_private_email === true ||
            payload.is_private_email === 'true',
    }
}
