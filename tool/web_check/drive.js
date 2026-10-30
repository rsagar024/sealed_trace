// Runs the dart2js build of check.dart in a real headless browser and checks
// its output with Node's own crypto (no Dart code involved).
//
//   dart compile js -O2 -o build/web_check/check.js tool/web_check/check.dart
//   node tool/web_check/drive.js chrome|edge|firefox [browser executable]
//
// Chrome and Edge are driven over the DevTools protocol on a pipe; Firefox over
// WebDriver BiDi on a loopback port. The page is served from a loopback HTTP
// server because IndexedDB is not reliable on file:// URLs. Each run uses a
// fresh temporary profile. No npm packages are needed (Node 22+).
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const root = path.resolve(__dirname, '..', '..');
const browserName = process.argv[2];
const defaults = {
  chrome: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  edge: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  firefox: 'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
};
if (!defaults[browserName]) {
  console.error('usage: node drive.js chrome|edge|firefox [executable]');
  process.exit(2);
}
const extra = process.argv.slice(3);
const only = (extra.find((a) => a.startsWith('--only=')) || '').slice(7).split(',').filter(Boolean);
const want = (phase) => only.length === 0 || only.includes(phase);
const executable = extra.find((a) => !a.startsWith('--')) || defaults[browserName];
const QUOTA_MB = 1; // envelope size in the quota phase
const CHROME_QUOTA = 10 * 1024 * 1024; // origin quota set through DevTools
const FIREFOX_LIMIT_KB = 51200; // global temporary-storage limit pref

const privateKey = (() => {
  const text = fs.readFileSync(path.join(root, 'test', 'helpers', 'test_keys.dart'), 'utf8');
  const m = text.match(/-----BEGIN PRIVATE KEY-----[\s\S]+?-----END PRIVATE KEY-----/);
  return crypto.createPrivateKey(m[0]);
})();

let failures = 0;
function report(ok, name) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`);
  if (!ok) failures++;
}

// ---------------------------------------------------------------- server

function serve() {
  const files = {
    '/index.html': [path.join(root, 'tool', 'web_check', 'index.html'), 'text/html; charset=utf-8'],
    '/check.js': [path.join(root, 'build', 'web_check', 'check.js'), 'text/javascript'],
  };
  const server = http.createServer((req, res) => {
    const entry = files[new URL(req.url, 'http://x').pathname];
    if (!entry) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { 'content-type': entry[1], 'cache-control': 'no-store' });
    res.end(fs.readFileSync(entry[0]));
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

function freePort() {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- Chromium (CDP over pipe)

async function launchChromium(profile) {
  const child = spawn(
    executable,
    [
      '--headless=new',
      '--remote-debugging-pipe',
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] },
  );
  const out = child.stdio[3];
  const inp = child.stdio[4];
  let nextId = 1;
  const pending = new Map();
  let buffer = Buffer.alloc(0);
  inp.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    let end;
    while ((end = buffer.indexOf(0)) >= 0) {
      const msg = JSON.parse(buffer.subarray(0, end).toString('utf8'));
      buffer = buffer.subarray(end + 1);
      if (msg.id && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) reject(new Error(`${msg.error.message}`));
        else resolve(msg.result);
      }
    }
  });
  const send = (method, params = {}, sessionId) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      out.write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + '\0');
    });

  const version = await send('Browser.getVersion');
  let page;
  for (let i = 0; i < 50 && !page; i++) {
    const { targetInfos } = await send('Target.getTargets');
    page = targetInfos.find((t) => t.type === 'page');
    if (!page) await sleep(100);
  }
  const tab = async (targetId) => {
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    await send('Page.enable', {}, sessionId);
    return {
      async navigate(url) {
        await send('Page.navigate', { url }, sessionId);
      },
      async evaluate(expression) {
        const r = await send('Runtime.evaluate', { expression, returnByValue: true }, sessionId);
        return r.result ? r.result.value : undefined;
      },
      async close() {
        await send('Target.closeTarget', { targetId });
      },
      sessionId,
    };
  };
  const main = await tab(page.targetId);
  return {
    version: version.product,
    navigate: main.navigate,
    evaluate: main.evaluate,
    async openTab() {
      const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
      return tab(targetId);
    },
    async setQuota(origin, bytes) {
      // Accepted, but headless Chrome/Edge 156 do not apply it (the page's
      // estimate keeps the default quota); the caller checks the estimate.
      await send('Storage.overrideQuotaForOrigin', { origin, quotaSize: bytes }, main.sessionId);
    },
    async close() {
      try {
        await send('Browser.close');
      } catch (_) {}
      await sleep(300);
      child.kill();
    },
  };
}

// ---------------------------------------------------------------- Firefox (WebDriver BiDi)

async function launchFirefox(profile, prefs) {
  const lines = Object.entries({
    'browser.shell.checkDefaultBrowser': false,
    'browser.startup.homepage_override.mstone': 'ignore',
    'datareporting.policy.dataSubmissionEnabled': false,
    'toolkit.telemetry.reportingpolicy.firstRun': false,
    ...prefs,
  }).map(([k, v]) => `user_pref(${JSON.stringify(k)}, ${JSON.stringify(v)});`);
  fs.writeFileSync(path.join(profile, 'user.js'), lines.join('\n') + '\n');
  const port = await freePort();
  const child = spawn(
    executable,
    ['-headless', '-no-remote', '-profile', profile, '--remote-debugging-port', String(port), 'about:blank'],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Firefox did not start BiDi')), 60000);
    const onData = (d) => {
      if (/WebDriver BiDi listening/.test(d.toString())) {
        clearTimeout(timer);
        resolve();
      }
    };
    child.stderr.on('data', onData);
    child.stdout.on('data', onData);
  });
  const ws = new WebSocket(`ws://127.0.0.1:${port}/session`);
  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = () => reject(new Error('BiDi WebSocket failed'));
  });
  let nextId = 1;
  const pending = new Map();
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.type === 'error') reject(new Error(`${msg.error}: ${msg.message}`));
      else resolve(msg.result);
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });
  const session = await send('session.new', { capabilities: {} });
  const { contexts } = await send('browsingContext.getTree', {});
  const tab = (context) => ({
    async navigate(url) {
      await send('browsingContext.navigate', { context, url, wait: 'none' });
    },
    async evaluate(expression) {
      const r = await send('script.evaluate', {
        expression,
        target: { context },
        awaitPromise: false,
        resultOwnership: 'none',
      });
      return r.result && 'value' in r.result ? r.result.value : undefined;
    },
    async close() {
      await send('browsingContext.close', { context });
    },
  });
  const main = tab(contexts[0].context);
  return {
    version: `Firefox ${session.capabilities.browserVersion}`,
    navigate: main.navigate,
    evaluate: main.evaluate,
    async openTab() {
      const { context } = await send('browsingContext.create', { type: 'tab' });
      return tab(context);
    },
    async setQuota() {
      throw new Error('quota is set through prefs on Firefox');
    },
    async close() {
      try {
        await send('browser.close', {});
      } catch (_) {}
      await sleep(500);
      child.kill();
    },
  };
}

// ---------------------------------------------------------------- page helpers

async function runPhase(browser, base, query, { waitDone = true, timeout = 180000 } = {}) {
  await browser.navigate(`${base}/index.html?${query}`);
  const started = Date.now();
  // Wait for the new document, then for the page's done flag.
  for (;;) {
    let state;
    try {
      state = await browser.evaluate(
        `(location.search === ${JSON.stringify('?' + query)} && document.body && document.body.dataset.done === '1') ? document.getElementById('result').textContent : null`,
      );
    } catch (_) {
      state = null; // navigation in progress
    }
    if (state) return state.split('\n');
    if (!waitDone && Date.now() - started > timeout) return [];
    if (Date.now() - started > timeout) throw new Error(`phase ${query} timed out`);
    await sleep(100);
  }
}

function decrypt(wire) {
  const key = crypto.privateDecrypt(
    { key: privateKey, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
    Buffer.from(wire.wrappedKey, 'base64'),
  );
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(wire.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(wire.tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(wire.ciphertext, 'base64')), decipher.final()]);
}

function checkPageLines(lines, label) {
  for (const l of lines) {
    if (l.startsWith('PASS') || l.startsWith('FAIL')) {
      report(l.startsWith('PASS'), `${label}: ${l.slice(5)}`);
    } else if (/^(REDOS|SEAL|MASKMS|QUOTA|LIFECYCLE|UA|STACK|TRACE) /.test(l)) {
      console.log(`  ${l}`);
    }
  }
}

function checkMain(lines) {
  checkPageLines(lines, 'main');
  const gcm = lines.filter((l) => l.startsWith('GCM '));
  report(gcm.length === 8, 'main: 8 AES-GCM cases reported');
  for (const l of gcm) {
    const [, sizeText, ctHash, tag] = l.split(' ');
    const size = parseInt(sizeText, 10);
    const key = Buffer.from(Array.from({ length: 32 }, (_, i) => (i * 7 + 1) & 0xff));
    const iv = Buffer.from(Array.from({ length: 12 }, (_, i) => (i * 13 + 5) & 0xff));
    const plain = Buffer.from(Array.from({ length: size }, (_, i) => (i * 31 + (i >> 3)) & 0xff));
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const ct = Buffer.concat([cipher.update(plain), cipher.final()]);
    report(
      crypto.createHash('sha256').update(ct).digest('base64') === ctHash &&
        cipher.getAuthTag().toString('base64') === tag,
      `main: AES-GCM in the page matches Node for ${size} bytes`,
    );
  }
  const slow = lines.filter((l) => l.startsWith('REDOS') && parseInt(l.split(' ')[1], 10) > 2000);
  report(slow.length === 0, 'main: every adversarial masking input under 2 s');
  const envelopes = lines.filter((l) => l.startsWith('ENVELOPE ')).map((l) => JSON.parse(l.slice(9)));
  report(envelopes.length === 4, 'main: 4 sealed envelopes reported');
  for (const e of envelopes) {
    let ok = false;
    try {
      const plain = decrypt(e.wire);
      ok =
        crypto.createHash('sha256').update(plain).digest('base64') === e.plainHash &&
        e.wire.v === 1 &&
        e.wire.alg === 'RSA-OAEP-2048-SHA256+AES-256-GCM';
    } catch (err) {
      console.log(`  decrypt error: ${err.message}`);
    }
    report(ok, `main: Node decrypts the "${e.name}" envelope to the exact plaintext`);
  }
}

// ---------------------------------------------------------------- run

async function main() {
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  const profiles = [];
  const newProfile = () => {
    const p = fs.mkdtempSync(path.join(os.tmpdir(), `web_check_${browserName}_`));
    profiles.push(p);
    return p;
  };
  const launch = (prefs = {}) =>
    browserName === 'firefox' ? launchFirefox(newProfile(), prefs) : launchChromium(newProfile());

  try {
    let browser = await launch();
    console.log(`browser: ${browser.version}`);

    // 1. Masking, AES-GCM, sealing timings, lifecycle source, storage write.
    if (want('main')) checkMain(await runPhase(browser, base, 'phase=main'));

    // 2. A real reload of the page (new document, same profile) reads it back.
    if (want('main')) {
    const read = await runPhase(browser, base, 'phase=persist-read');
    checkPageLines(read, 'reload');
    const stored = read.filter((l) => l.startsWith('STORED ')).map((l) => JSON.parse(l.slice(7)).wire);
    let decrypted = stored.length === 3;
    for (const w of stored) {
      try {
        const events = JSON.parse(decrypt(w).toString('utf8'));
        decrypted = decrypted && Array.isArray(events) && events.length === 5;
      } catch (_) {
        decrypted = false;
      }
    }
    report(decrypted, 'reload: Node decrypts the 3 envelopes read back after the reload');
    }

    // 3. Leaving the page inside the 2 s write-behind window: pagehide must
    //    persist the queue before the document goes. "navigate" goes to
    //    another page in the same tab, "close" closes the tab, and the
    //    control run has no listener and must lose the events.
    // "spill" is the SDK's web path and must keep all 5 events; "none" is the
    // control and must lose them; "flush" is the old asynchronous path,
    // recorded for comparison only.
    const lifecycleRuns = [
      ['navigate', 'spill'],
      ['navigate', 'flush'],
      ['navigate', 'none'],
      ['close', 'spill'],
      ['close', 'flush'],
    ];
    for (const [how, mode] of want('lifecycle') ? lifecycleRuns : []) {
      let after;
      if (how === 'navigate') {
        await runPhase(browser, base, `phase=lifecycle-write&mode=${mode}`);
        after = await runPhase(browser, base, `phase=lifecycle-read&n=${how}-${mode}`);
      } else {
        const tab = await browser.openTab();
        await runPhase(tab, base, `phase=lifecycle-write&mode=${mode}`);
        await tab.close();
        after = await runPhase(browser, base, `phase=lifecycle-read&n=${how}-${mode}`);
      }
      const line = after.find((l) => l.startsWith('LIFECYCLE ')) || 'LIFECYCLE ?';
      console.log(`  ${how} ${mode}: ${line}`);
      for (const t of after.filter((l) => l.startsWith('TRACE'))) console.log(`    ${t}`);
      const events = parseInt((line.match(/(\d+) events/) || [])[1] || '-1', 10);
      const what = how === 'close' ? 'closing the tab' : 'navigating away';
      if (mode === 'spill') report(events === 5, `lifecycle: ${what} keeps the 5 queued events (spill)`);
      if (mode === 'none') report(events === 0, `lifecycle control: ${what} without a listener loses them`);
      if (mode === 'flush') console.log(`  INFO ${what} with the old async flush kept ${events} of 5`);
    }

    // 4. Quota: a small quota, then fill until the browser refuses.
    if (want('quota')) {
      let testable = true;
      if (browserName === 'firefox') {
        await browser.close();
        browser = await launch({ 'dom.quotaManager.temporaryStorage.fixedLimit': FIREFOX_LIMIT_KB });
      } else {
        await browser.setQuota(base, CHROME_QUOTA);
        await runPhase(browser, base, 'phase=noop');
        const quota = await browser.evaluate('navigator.storage.estimate().then((e) => e.quota)');
        const reported = typeof quota === 'number' ? quota : await (async () => {
          await browser.evaluate("navigator.storage.estimate().then((e) => { window.__q = e.quota; })");
          await sleep(300);
          return browser.evaluate('window.__q');
        })();
        if (!(reported <= 2 * CHROME_QUOTA)) {
          testable = false;
          console.log(`SKIP quota: the DevTools quota override was not applied (quota still ${reported} bytes)`);
        }
      }
      if (testable) {
        checkPageLines(await runPhase(browser, base, `phase=quota&mb=${QUOTA_MB}`), 'quota');
      }
    }

    await browser.close();
  } finally {
    server.close();
    await sleep(500);
    for (const p of profiles) {
      try {
        fs.rmSync(p, { recursive: true, force: true });
      } catch (_) {}
    }
  }
  console.log(failures === 0 ? 'ALL PASSED' : `${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
