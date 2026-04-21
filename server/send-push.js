#!/usr/bin/env node
// Sends an APNs alert push to the Watch (haptic + banner + NSE-driven cache
// update). Usage: node send-push.js working|done|approval

import { readFileSync, existsSync } from 'node:fs'
import { connect } from 'node:http2'
import { createSign, randomUUID } from 'node:crypto'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

const KEY_ID = '94PA5YLF3M'
const TEAM_ID = process.env.CLAUDETAP_TEAM_ID || 'NJ4Z2645XA'
const TOPIC = 'com.fm.claudetap.watchapp'
const KEY_PATH = join(__dirname, `AuthKey_${KEY_ID}.p8`)
const TOKEN_PATH = join(__dirname, 'device-token.txt')

const status = process.argv[2] || 'done'

if (!existsSync(TOKEN_PATH)) {
    console.error(`No device token at ${TOKEN_PATH}`)
    process.exit(1)
}
const deviceToken = readFileSync(TOKEN_PATH, 'utf8').trim()

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

// `mutable-content: 1` tells APNs to run our Notification Service Extension
// on the Watch before displaying the notification — that's what keeps the
// App Group cache up to date even when the main app is terminated.
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
    ':path': `/3/device/${deviceToken}`,
    'authorization': `bearer ${jwt}`,
    'apns-topic': TOPIC,
    'apns-push-type': 'alert',
    'apns-priority': '10',
    'apns-id': randomUUID(),
    'content-type': 'application/json'
}

const client = connect(`https://api.sandbox.push.apple.com:443`)
client.on('error', (e) => { console.error(`Connection error: ${e.message}`); process.exit(1) })

const req = client.request(headers)
let responseStatus = 0
let responseBody = ''
req.on('response', (h) => { responseStatus = h[':status'] })
req.on('data', (c) => { responseBody += c.toString() })
req.on('end', () => {
    if (responseStatus === 200) {
        console.log(`${status} ✓`)
    } else {
        console.error(`${status} ✗ ${responseStatus}: ${responseBody}`)
    }
    client.close()
})
req.write(JSON.stringify(payload))
req.end()

console.log(`Sending: ${status}`)
