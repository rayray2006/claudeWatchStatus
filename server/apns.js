// Shared APNs sender used by both the CLI (send-push.js) and the web app (web-server.js).

import { readFileSync } from 'node:fs'
import { connect } from 'node:http2'
import { createSign, randomUUID } from 'node:crypto'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

const KEY_ID = '94PA5YLF3M'
const TEAM_ID = process.env.CLAUDETAP_TEAM_ID || 'NJ4Z2645XA'
const TOPIC = 'com.fm.claudetap.watchapp'
const KEY_PATH = join(__dirname, `AuthKey_${KEY_ID}.p8`)

function base64url(buf) {
    return Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function makeJWT() {
    const header = base64url(JSON.stringify({ alg: 'ES256', kid: KEY_ID }))
    const payload = base64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) }))
    const privateKey = readFileSync(KEY_PATH, 'utf8')
    const signer = createSign('SHA256')
    signer.update(`${header}.${payload}`)
    const signature = base64url(signer.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }))
    return `${header}.${payload}.${signature}`
}

/**
 * Send a state-change push to the Watch.
 *
 * All pushes are alert-type with `mutable-content: 1` so the Notification
 * Service Extension runs for every state. The NSE writes the new state to
 * the shared App Group cache even when the watch app is terminated — that's
 * the only reliable path to keep the app + complication up to date.
 *
 * The NSE on the watch decides how user-visible each notification is:
 *   - done/approval → full notification with haptic + image attachment
 *   - idle/working  → passive, empty, no haptic (delivered to cache only)
 *
 * All pushes share the same apns-collapse-id so a new state replaces the
 * previous entry in Notification Center rather than stacking.
 *
 * @param {{ token: string, status: 'idle'|'working'|'done'|'approval' }} opts
 * @returns {Promise<{ ok: boolean, httpStatus: number, body: string }>}
 */
export function sendPush({ token, status }) {
    // watchOS skips the Notification Service Extension entirely when the
    // alert body is empty — so every push must carry a non-empty body even
    // for silent states. The NSE clears it again before the notification is
    // delivered to the user for idle/working.
    const body = status === 'approval' ? 'Needs approval' :
                 status === 'done'     ? 'Done' :
                 status === 'working'  ? 'Working' :
                                         'Idle'

    const loud = status === 'approval' || status === 'done'

    const aps = {
        alert: { body },
        'content-available': 1,
        'mutable-content': 1,
        // Set the interruption level directly in APNs for silent states so
        // the system knows to suppress the haptic from the moment the push
        // arrives — the NSE can't strip the haptic after the fact.
        'interruption-level': loud ? 'active' : 'passive'
    }
    if (loud) aps.sound = 'default'

    const payload = { aps, status, ts: Date.now() }

    const headers = {
        ':method': 'POST',
        ':path': `/3/device/${token}`,
        'authorization': `bearer ${makeJWT()}`,
        'apns-topic': TOPIC,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': 'claudetap-state',
        'apns-id': randomUUID(),
        'content-type': 'application/json'
    }

    return new Promise((resolve, reject) => {
        const client = connect('https://api.sandbox.push.apple.com:443')
        client.on('error', (e) => reject(e))

        const req = client.request(headers)
        let httpStatus = 0
        let body = ''
        req.on('response', (h) => { httpStatus = h[':status'] })
        req.on('data', (c) => { body += c.toString() })
        req.on('end', () => {
            client.close()
            resolve({ ok: httpStatus === 200, httpStatus, body })
        })
        req.on('error', (e) => { client.close(); reject(e) })
        req.write(JSON.stringify(payload))
        req.end()
    })
}
