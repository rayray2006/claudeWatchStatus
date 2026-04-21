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
 * @param {{ token: string, status: 'idle'|'working'|'done'|'approval' }} opts
 * @returns {Promise<{ ok: boolean, httpStatus: number, body: string }>}
 */
export function sendPush({ token, status }) {
    const alertBody = status === 'approval' ? 'Needs approval'
                    : status === 'done'     ? 'Done'
                    : status === 'idle'     ? 'Idle'
                    : 'Working...'

    const payload = {
        aps: {
            alert: { title: 'Claude', body: alertBody },
            sound: 'default',
            'content-available': 1,
            'mutable-content': 1
        },
        status,
        ts: Date.now()
    }

    const headers = {
        ':method': 'POST',
        ':path': `/3/device/${token}`,
        'authorization': `bearer ${makeJWT()}`,
        'apns-topic': TOPIC,
        'apns-push-type': 'alert',
        'apns-priority': '10',
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
