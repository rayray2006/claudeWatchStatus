#!/usr/bin/env node
// Sends:
//   1) Watch alert push (haptic + screen update) — uses device-token.txt
//   2) iOS Live Activity update push (Smart Stack mirror) — uses activity-token.txt
// Usage: node send-push.js working|done|approval

import { readFileSync, existsSync } from 'node:fs'
import { connect } from 'node:http2'
import { createSign, randomUUID } from 'node:crypto'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

const KEY_ID = '94PA5YLF3M'
const TEAM_ID = process.env.CLAUDETAP_TEAM_ID || 'NJ4Z2645XA'

// Watch app
const WATCH_TOPIC = 'com.fm.claudetap.watchapp'
const WATCH_TOKEN_PATH = join(__dirname, 'device-token.txt')

// iOS Live Activity
const IOS_BUNDLE = 'com.fm.claudetap'
const LIVE_ACTIVITY_TOPIC = `${IOS_BUNDLE}.push-type.liveactivity`
const ACTIVITY_TOKEN_PATH = join(__dirname, 'activity-token.txt')

const KEY_PATH = join(__dirname, `AuthKey_${KEY_ID}.p8`)

const status = process.argv[2] || 'done'

if (!existsSync(WATCH_TOKEN_PATH)) {
    console.error(`No watch device token at ${WATCH_TOKEN_PATH}`)
    process.exit(1)
}
const watchToken = readFileSync(WATCH_TOKEN_PATH, 'utf8').trim()
const activityToken = existsSync(ACTIVITY_TOKEN_PATH)
    ? readFileSync(ACTIVITY_TOKEN_PATH, 'utf8').trim()
    : null

function base64url(buf) {
    return Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

const header = base64url(JSON.stringify({ alg: 'ES256', kid: KEY_ID }))
const jwtPayload = base64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) }))
const privateKey = readFileSync(KEY_PATH, 'utf8')
const signer = createSign('SHA256')
signer.update(`${header}.${jwtPayload}`)
const signature = base64url(signer.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }))
const jwt = `${header}.${jwtPayload}.${signature}`

const alertBody = status === 'approval' ? 'Needs approval' : status === 'done' ? 'Done' : 'Working...'

const client = connect(`https://api.sandbox.push.apple.com:443`)
client.on('error', (e) => { console.error(`Connection error: ${e.message}`); process.exit(1) })

function sendOnce({ token, topic, pushType, priority, payload, label }) {
    return new Promise((resolve) => {
        const headers = {
            ':method': 'POST',
            ':path': `/3/device/${token}`,
            'authorization': `bearer ${jwt}`,
            'apns-topic': topic,
            'apns-push-type': pushType,
            'apns-priority': priority,
            'apns-id': randomUUID(),
            'content-type': 'application/json'
        }

        const req = client.request(headers)
        let responseStatus = 0
        let responseBody = ''
        req.on('response', (h) => { responseStatus = h[':status'] })
        req.on('data', (c) => { responseBody += c.toString() })
        req.on('end', () => {
            if (responseStatus === 200) {
                console.log(`  ${label} ✓`)
            } else {
                console.error(`  ${label} ✗ ${responseStatus}: ${responseBody}`)
            }
            resolve()
        })
        req.write(JSON.stringify(payload))
        req.end()
    })
}

function sendWatchAlert() {
    return sendOnce({
        token: watchToken,
        topic: WATCH_TOPIC,
        pushType: 'alert',
        priority: '10',
        label: 'watch alert',
        payload: {
            aps: {
                alert: { title: 'Claude', body: alertBody },
                sound: 'default',
                'content-available': 1
            },
            status,
            ts: Date.now()
        }
    })
}

function sendLiveActivityUpdate() {
    if (!activityToken) {
        console.log('  liveactivity – (no token; skipping)')
        return Promise.resolve()
    }
    return sendOnce({
        token: activityToken,
        topic: LIVE_ACTIVITY_TOPIC,
        pushType: 'liveactivity',
        priority: '10',
        label: 'live activity',
        payload: {
            aps: {
                timestamp: Math.floor(Date.now() / 1000),
                event: 'update',
                'content-state': { state: status === 'approval' ? 'approval' : status }
            }
        }
    })
}

console.log(`Sending: ${status}`)
await Promise.all([sendWatchAlert(), sendLiveActivityUpdate()])
client.close()
