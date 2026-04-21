#!/usr/bin/env node
// Tiny web UI for firing ClaudeTap pushes.
// Run:   node web-server.js
// Visit: http://localhost:8787

import { createServer } from 'node:http'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { sendPush } from './apns.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PORT = Number(process.env.PORT) || 8787
const INDEX_PATH = join(__dirname, 'public', 'index.html')

const VALID_STATES = new Set(['idle', 'working', 'done', 'approval'])

function readJSON(req) {
    return new Promise((resolve, reject) => {
        let raw = ''
        req.on('data', (c) => { raw += c })
        req.on('end', () => {
            try { resolve(JSON.parse(raw || '{}')) } catch (e) { reject(e) }
        })
        req.on('error', reject)
    })
}

const server = createServer(async (req, res) => {
    try {
        if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
            const html = readFileSync(INDEX_PATH, 'utf8')
            res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' })
            res.end(html)
            return
        }

        if (req.method === 'POST' && req.url === '/push') {
            const body = await readJSON(req)
            const token = String(body.token || '').trim().toLowerCase()
            const status = String(body.status || '').trim()

            if (!/^[0-9a-f]{64}$/.test(token)) {
                res.writeHead(400, { 'content-type': 'application/json' })
                res.end(JSON.stringify({ ok: false, error: 'Invalid token (expected 64 hex chars)' }))
                return
            }
            if (!VALID_STATES.has(status)) {
                res.writeHead(400, { 'content-type': 'application/json' })
                res.end(JSON.stringify({ ok: false, error: `Invalid status (expected one of ${[...VALID_STATES].join(', ')})` }))
                return
            }

            const result = await sendPush({ token, status })
            res.writeHead(result.ok ? 200 : 502, { 'content-type': 'application/json' })
            res.end(JSON.stringify(result))
            return
        }

        res.writeHead(404)
        res.end('Not found')
    } catch (e) {
        res.writeHead(500, { 'content-type': 'application/json' })
        res.end(JSON.stringify({ ok: false, error: e.message }))
    }
})

server.listen(PORT, () => {
    console.log(`ClaudeTap push tester → http://localhost:${PORT}`)
})
