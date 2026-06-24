#!/usr/bin/env node
/**
 * Demo load-test helper — bridges the UI "Run load test" button to the cluster.
 *
 * WHY THIS EXISTS: a browser cannot run `kubectl`. So this tiny localhost-only server
 * exposes two endpoints the Admin button calls; each one runs the SAME kubectl command
 * you'd type by hand. It does NOTHING else — only applies/deletes the loadgen Deployment.
 *
 * SECURITY BOUNDARY (so it's safe to run during a demo):
 *   - binds to 127.0.0.1 only (not reachable from the network)
 *   - allows CORS only from the local frontend (http://localhost:5173)
 *   - runs exactly two fixed commands; no user input is ever passed to the shell
 *
 * RUN (in a terminal, before the demo):
 *   node k8s-lab/loadtest-helper.js
 * Then the Admin-page button works. Ctrl-C to stop. If you forget to stop it, it's harmless.
 */
const http = require('http')
const {execFile} = require('child_process')
const path = require('path')

const PORT = 7070
const HOST = '127.0.0.1'
const FRONTEND_ORIGIN = 'http://localhost:5173'

// The loadgen lives in the same file as the HPA; we apply/delete only the loadgen Deployment.
const HPA_FILE = path.join(__dirname, 'platform', '10-hpa-autoscale.yaml')
const NS = 'synthetic-data'

// Fixed commands — no interpolation of any request data.
const CMD_START = ['apply', '-f', HPA_FILE]            // creates HPA (idempotent) + loadgen
const CMD_STOP = ['-n', NS, 'delete', 'deploy', 'loadgen', '--ignore-not-found']

function runKubectl(args) {
  return new Promise((resolve) => {
    execFile('kubectl', args, {timeout: 30000}, (err, stdout, stderr) => {
      resolve({ok: !err, out: (stdout || '') + (stderr || '')})
    })
  })
}

const server = http.createServer(async (req, res) => {
  // CORS — only the local frontend, only what we need.
  res.setHeader('Access-Control-Allow-Origin', FRONTEND_ORIGIN)
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type')
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end() }

  const send = (code, obj) => {
    res.writeHead(code, {'Content-Type': 'application/json'})
    res.end(JSON.stringify(obj))
  }

  if (req.method === 'POST' && req.url === '/load/start') {
    const r = await runKubectl(CMD_START)
    console.log('[start]', r.ok ? 'loadgen applied' : 'FAILED', r.out.trim())
    return send(r.ok ? 200 : 500, {status: r.ok ? 'started' : 'error', detail: r.out})
  }
  if (req.method === 'POST' && req.url === '/load/stop') {
    const r = await runKubectl(CMD_STOP)
    console.log('[stop]', r.ok ? 'loadgen deleted' : 'FAILED', r.out.trim())
    return send(r.ok ? 200 : 500, {status: r.ok ? 'stopped' : 'error', detail: r.out})
  }
  if (req.method === 'GET' && req.url === '/health') {
    return send(200, {status: 'ok'})
  }
  send(404, {status: 'not-found'})
})

server.listen(PORT, HOST, () => {
  console.log(`load-test helper listening on http://${HOST}:${PORT}`)
  console.log(`  POST /load/start -> kubectl apply -f ${HPA_FILE}`)
  console.log(`  POST /load/stop  -> kubectl -n ${NS} delete deploy loadgen`)
  console.log(`  (CORS allowed from ${FRONTEND_ORIGIN})`)
})
