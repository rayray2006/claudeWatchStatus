import { randomUUID } from 'node:crypto'
import { connect, type ClientHttp2Session } from 'node:http2'
import { getApnsJwt } from './jwt.js'

export type Status = 'idle' | 'working' | 'done' | 'approval'

export interface PushResult {
    ok: boolean
    httpStatus: number
    reason?: string
}

export interface PushTarget {
    token: string
    environment: 'sandbox' | 'production'
    bundleId: string
}

const ATTENTION: ReadonlySet<Status> = new Set(['done', 'approval'])

function endpoint(env: 'sandbox' | 'production'): string {
    return env === 'production'
        ? 'https://api.push.apple.com:443'
        : 'https://api.sandbox.push.apple.com:443'
}

function buildPayload(status: Status) {
    const loud = ATTENTION.has(status)
    const body =
        status === 'approval' ? 'Needs approval' :
        status === 'done'     ? 'Done' :
        status === 'working'  ? 'Working' : 'Idle'

    const aps: Record<string, unknown> = {
        alert: { body },
        'content-available': 1,
        'mutable-content': 1,
        'interruption-level': loud ? 'active' : 'passive',
    }
    if (loud) aps.sound = 'default'

    return {
        loud,
        payload: JSON.stringify({ aps, status, ts: Date.now() }),
    }
}

// Short-lived connection cache per endpoint (serverless functions don't live
// long enough for this to be very useful, but within a single request handling
// multiple devices it avoids re-TLS for each).
const sessionCache = new Map<string, ClientHttp2Session>()

function getSession(url: string): ClientHttp2Session {
    const existing = sessionCache.get(url)
    if (existing && !existing.closed && !existing.destroyed) return existing
    const session = connect(url)
    session.on('error', () => {
        sessionCache.delete(url)
    })
    sessionCache.set(url, session)
    return session
}

export async function sendPush(
    target: PushTarget,
    status: Status,
): Promise<PushResult> {
    const jwt = await getApnsJwt()
    const { loud, payload } = buildPayload(status)
    const url = endpoint(target.environment)

    return new Promise<PushResult>((resolve) => {
        let session: ClientHttp2Session
        try {
            session = getSession(url)
        } catch (err) {
            resolve({ ok: false, httpStatus: 0, reason: 'connect_error: ' + (err as Error).message })
            return
        }

        const req = session.request({
            ':method': 'POST',
            ':path': `/3/device/${target.token}`,
            authorization: `bearer ${jwt}`,
            'apns-topic': target.bundleId,
            'apns-push-type': 'alert',
            'apns-priority': loud ? '10' : '5',
            'apns-collapse-id': 'nudge-state',
            'apns-id': randomUUID(),
            'content-type': 'application/json',
        })

        let status_ = 0
        let body = ''
        req.on('response', (headers) => {
            status_ = Number(headers[':status'] ?? 0)
        })
        req.on('data', (c: Buffer) => { body += c.toString() })
        req.on('end', () => {
            if (status_ >= 200 && status_ < 300) {
                resolve({ ok: true, httpStatus: status_ })
                return
            }
            let reason: string | undefined
            try {
                const parsed = JSON.parse(body) as { reason?: string }
                reason = parsed.reason
            } catch {
                /* ignore */
            }
            resolve({ ok: false, httpStatus: status_, reason })
        })
        req.on('error', (err) => {
            resolve({ ok: false, httpStatus: 0, reason: 'request_error: ' + err.message })
        })

        req.setTimeout(10_000, () => {
            req.close()
            resolve({ ok: false, httpStatus: 0, reason: 'request_timeout' })
        })

        req.write(payload)
        req.end()
    })
}

export const PERMANENT_FAILURE_REASONS = new Set([
    'BadDeviceToken',
    'Unregistered',
    'DeviceTokenNotForTopic',
])

export function isPermanentFailure(result: PushResult): boolean {
    if (!result.reason) return false
    return (
        result.httpStatus === 410 ||
        PERMANENT_FAILURE_REASONS.has(result.reason)
    )
}
