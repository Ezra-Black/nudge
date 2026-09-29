// Renders the ad frame by frame: headless Chromium seeks index.html to each frame's time over the
// DevTools protocol, captures it, and pipes the frames into ffmpeg with the soundtrack.
//
//   node render.mjs                     full 1440×1440, 60 fps MP4
//   node render.mjs --stills 1.2,4.9    PNG stills at those times, for checking
//   node render.mjs --fps 30 --out preview.mp4
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const fps = Number(opt('--fps', 60));
const out = resolve(here, opt('--out', 'Nudge-Ad-1440.mp4'));
const stills = opt('--stills', null);
const size = 1440;

function findChromium() {
  if (process.env.CHROME) return process.env.CHROME;
  const base = join(homedir(), 'Library/Caches/ms-playwright');
  for (const dir of ['chromium_headless_shell-1234', 'chromium_headless_shell-1208']) {
    const p = join(base, dir, 'chrome-headless-shell-mac-arm64/chrome-headless-shell');
    if (existsSync(p)) return p;
  }
  throw new Error('No headless Chromium found. Set CHROME to a Chrome or chrome-headless-shell binary.');
}

const port = 9300 + Math.floor(Math.random() * 400);
const chrome = spawn(findChromium(), [
  `--remote-debugging-port=${port}`, '--headless', '--hide-scrollbars', '--force-device-scale-factor=1',
  `--window-size=${size},${size}`, '--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required',
  '--font-render-hinting=none', '--force-color-profile=srgb', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
chrome.stderr.on('data', () => {});

async function connect() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('Chromium did not start');
}
const ws = new WebSocket(await connect());
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let nextId = 1;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { const { ok, fail } = pending.get(msg.id); pending.delete(msg.id); msg.error ? fail(new Error(msg.error.message)) : ok(msg.result); }
});
const send = (method, params = {}) => new Promise((ok, fail) => { const id = nextId++; pending.set(id, { ok, fail }); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
  return r.result.value;
};

await send('Page.enable');
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: size, height: size, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: pathToFileURL(join(here, 'index.html')).href + '?render' });
for (let i = 0; i < 200 && !(await evaluate('window.__ready === true').catch(() => false)); i++) await new Promise((r) => setTimeout(r, 50));
const duration = await evaluate('window.DURATION');

const capture = async (t) => {
  await evaluate(`seek(${t})`);
  const { data } = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: size, height: size, scale: 1 }, optimizeForSpeed: true });
  return Buffer.from(data, 'base64');
};

if (stills) {
  const dir = join(here, 'stills');
  mkdirSync(dir, { recursive: true });
  for (const t of stills.split(',').map(Number)) {
    const file = join(dir, `t${t.toFixed(2)}.png`);
    writeFileSync(file, await capture(t));
    console.log(file);
  }
} else {
  const wav = join(here, 'soundtrack.wav');
  const frames = Math.round(duration * fps);
  const ffArgs = ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-'];
  if (existsSync(wav)) ffArgs.push('-i', wav);
  ffArgs.push('-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709');
  if (existsSync(wav)) ffArgs.push('-c:a', 'aac', '-b:a', '256k', '-shortest');
  ffArgs.push(out);
  const ff = spawn('ffmpeg', ffArgs, { stdio: ['pipe', 'inherit', 'inherit'] });
  const started = Date.now();
  for (let f = 0; f < frames; f++) {
    const png = await capture(f / fps);
    if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once('drain', r));
    if (f % 60 === 0) process.stdout.write(`\rframe ${f}/${frames}  ${((Date.now() - started) / 1000).toFixed(0)} s`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on('close', r));
  console.log(`\n${out}`);
}
ws.close();
chrome.kill();
