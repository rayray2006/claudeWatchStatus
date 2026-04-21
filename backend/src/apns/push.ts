import { randomUUID } from 'node:crypto'
import { getApnsJwt } from './jwt.js'

export type Status = 'idle' | 'working' | 'done' | 'approval'

export interface PushResult {
    ok: boolean
    httpStatus: number
    reason?: string   // APNs error reason, if any
}

export interface PushTarget {
    token: string
    environment: 'sandbox' | 'production'
    bundleId: string
}

const ATTENTION: ReadonlySet<Status> = new Set(['done', 'approval'])

function endpoint(env: 'sandbox' | 'production'): string {
    return env === 'production'
        ? 'https://api.push.apple.com'
        : 'https://api.sandbox.push.apple.com'
}

function buildPayload(status: Status) {
    const loud = ATTENTION.has(status)
    const body =
        status === 'approval' ? 'Needs approval' :
        status === 'done'     ? 'Done' :
        status === 'working'  ? 'Working' : 'Idle'

    const aps: Record<string, unknown> = {
        alert: { title: 'Claude', body },
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

export async function sendPush(
    target: PushTarget,
    status: Status,
): Promise<PushResult> {
    const jwt = await getApnsJwt()
    const { loud, payload } = buildPayload(status)

    const url = `${endpoint(target.environment)}/3/device/${target.token}`
    let response: Response
    try {
        response = await fetch(url, {
            method: 'POST',
            headers: {
                authorization: `bearer ${jwt}`,
                'apns-topic': target.bundleId,
                'apns-push-type': 'alert',
                'apns-priority': loud ? '10' : '5',
                'apns-collapse-id': 'nudge-state',
                'apns-id': randomUUID(),
                'content-type': 'application/json',
            },
            body: payload,
        })
    } catch (err) {
        return { ok: false, httpStatus: 0, reason: (err as Error).message }
    }

    if (response.ok) {
        return { ok: true, httpStatus: response.status }
    }

    let reason: string | undefined
    try {
        const body = (await response.json()) as { reason?: string }
        reason = body.reason
    } catch {
        /* ignore */
    }
    return { ok: false, httpStatus: response.status, reason }
}

/** Reasons APNs returns when a device token is permanently invalid. */
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
