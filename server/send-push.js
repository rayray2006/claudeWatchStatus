#!/usr/bin/env node
// CLI wrapper around server/apns.js. Reads the device token from device-token.txt.
// Usage: node send-push.js working|done|approval|idle

import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { sendPush } from './apns.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const TOKEN_PATH = join(__dirname, 'device-token.txt')

if (!existsSync(TOKEN_PATH)) {
    console.error(`No device token at ${TOKEN_PATH}`)
    process.exit(1)
}
const token = readFileSync(TOKEN_PATH, 'utf8').trim()
const status = process.argv[2] || 'done'

console.log(`Sending: ${status}`)
try {
    const result = await sendPush({ token, status })
    if (result.ok) {
        console.log(`${status} ✓`)
    } else {
        console.error(`${status} ✗ ${result.httpStatus}: ${result.body}`)
        process.exit(1)
    }
} catch (e) {
    console.error(`Connection error: ${e.message}`)
    process.exit(1)
}
