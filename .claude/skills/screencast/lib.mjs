// Shared runtime for narrated screencasts (adapted from the iRecycle screencast scripts).
// A screencast script only defines STEPS and calls runScreencast(); everything else lives here.
import { Builder, By, until } from 'selenium-webdriver';
import chrome from 'selenium-webdriver/chrome.js';
import { execSync, execFileSync, spawn } from 'child_process';
import { mkdirSync, existsSync, writeFileSync, unlinkSync } from 'fs';
import { createHash } from 'crypto';
import path from 'path';

export { By, until };

export const BASE_URL = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
export const DEMO_PASSWORD = process.env.DEMO_PASSWORD || 'demo-password-2026';
const VOICE = process.env.VOICE || 'Samantha';

export function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ── AUDIO ────────────────────────────────────────────────────────────────────

// Cached per step id, voice and text, so edited narration or another VOICE regenerates only what changed.
function generateAudio(audioDir, id, text) {
  const hash = createHash('sha1').update(`${VOICE}\n${text}`).digest('hex').slice(0, 8);
  const wav = path.join(audioDir, `${id}-${hash}.wav`);
  const aiff = path.join(audioDir, `${id}.aiff`);
  const txt = path.join(audioDir, `${id}.txt`);
  if (!existsSync(wav)) {
    writeFileSync(txt, text, 'utf8');
    execSync(`say -v "${VOICE}" -o "${aiff}" -f "${txt}"`);
    execSync(`afconvert -f WAVE -d LEI16 "${aiff}" "${wav}"`);
    unlinkSync(aiff);
    unlinkSync(txt);
  }
  return wav;
}

function getAudioDuration(file) {
  try {
    const out = execSync(`ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${file}"`).toString().trim();
    return Math.ceil(parseFloat(out) * 1000);
  } catch { return 3000; }
}

function playAudio(file) {
  return new Promise(resolve => {
    const p = spawn('afplay', [file]);
    p.on('close', resolve);
    p.on('error', resolve);
  });
}

// ── SCREEN RECORDING ─────────────────────────────────────────────────────────

// SCREEN picks the display (0 = the main display with the menu bar). The same index drives the ffmpeg
// "Capture screen N" device and where the browser windows are placed, so the recording shows them.
const SCREEN = process.env.SCREEN || '0';

function screenDevice() {
  const list = execSync('ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true').toString();
  const match = list.match(new RegExp(`\\[(\\d+)\\] Capture screen ${SCREEN}\\b`));
  if (!match) throw new Error(`No "Capture screen ${SCREEN}" device (see ffmpeg -f avfoundation -list_devices true -i "")`);
  return match[1];
}

// Usable area of that display (minus menu bar and Dock) in window coordinates: origin at the top-left of the
// main display, y growing downwards. AppKit reports bottom-left origins, hence the flip.
function displayArea() {
  const js = `ObjC.import('AppKit');
    const screens = $.NSScreen.screens, main = screens.objectAtIndex(0).frame, s = screens.objectAtIndex(${Number(SCREEN)});
    const v = s.visibleFrame;
    JSON.stringify({ x: v.origin.x, y: main.size.height - (v.origin.y + v.size.height), width: v.size.width, height: v.size.height })`;
  return JSON.parse(execFileSync('osascript', ['-l', 'JavaScript', '-e', js]).toString());
}

function startScreenRecording(outputFile) {
  const proc = spawn('ffmpeg', [
    '-f', 'avfoundation', '-capture_cursor', '1', '-framerate', '30', '-i', screenDevice(),
    '-vcodec', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-y', outputFile,
  ], { stdio: ['pipe', 'ignore', 'ignore'] });
  proc.on('error', err => console.error('ffmpeg error:', err));
  return proc;
}

function stopScreenRecording(proc) {
  return new Promise(resolve => {
    proc.on('close', resolve);
    try { proc.stdin.write('q'); } catch {}
    setTimeout(() => { try { proc.kill('SIGINT'); } catch {} }, 3000);
  });
}

// ── BROWSER HELPERS ──────────────────────────────────────────────────────────

export async function waitVisible(driver, css, timeout = 15000) {
  const el = await driver.wait(until.elementLocated(By.css(css)), timeout);
  await driver.wait(until.elementIsVisible(el), timeout);
  return el;
}

// Orange ripple where the click lands, so viewers can follow it.
async function ripple(driver, el) {
  await driver.executeScript('arguments[0].scrollIntoView({block:"center"})', el);
  await driver.executeScript(`
    const rect = arguments[0].getBoundingClientRect();
    if (!document.getElementById('_sc_ripple_style')) {
      const s = document.createElement('style');
      s.id = '_sc_ripple_style';
      s.textContent = '@keyframes _sc_ripple{0%{transform:translate(-50%,-50%) scale(.3);opacity:1}100%{transform:translate(-50%,-50%) scale(2.2);opacity:0}}' +
        '._sc_dot{position:absolute;width:40px;height:40px;border-radius:50%;background:rgba(255,80,0,.75);pointer-events:none;z-index:2147483647;animation:_sc_ripple .55s ease-out forwards}';
      document.head.appendChild(s);
    }
    const dot = document.createElement('div');
    dot.className = '_sc_dot';
    dot.style.left = (rect.left + rect.width / 2 + window.scrollX) + 'px';
    dot.style.top = (rect.top + rect.height / 2 + window.scrollY) + 'px';
    document.body.appendChild(dot);
    setTimeout(() => dot.remove(), 600);
  `, el);
  await sleep(300);
}

async function clickLocated(driver, locator, timeout) {
  const deadline = Date.now() + timeout;
  while (true) {
    try {
      const el = await driver.wait(until.elementLocated(locator), timeout);
      await driver.wait(until.elementIsVisible(el), timeout);
      await ripple(driver, el);
      await el.click();
      return;
    } catch (err) {
      // Turbo morphs replace elements under us; retry until the deadline.
      if (err.name !== 'StaleElementReferenceError' || Date.now() > deadline) throw err;
      await sleep(200);
    }
  }
}

export const click = (driver, css, timeout = 15000) => clickLocated(driver, By.css(css), timeout);

// This app's buttons have no ids: click by visible text.
export const clickButton = (driver, text, timeout = 15000) =>
  clickLocated(driver, By.xpath(`//button[normalize-space()=${JSON.stringify(text)}]`), timeout);

export const clickLink = (driver, text, timeout = 15000) =>
  clickLocated(driver, By.xpath(`//a[normalize-space()=${JSON.stringify(text)}]`), timeout);

export async function fill(driver, css, text) {
  const el = await waitVisible(driver, css);
  await el.clear();
  await el.sendKeys(text);
  await driver.executeScript(`arguments[0].dispatchEvent(new Event('input', {bubbles:true}))`, el);
}

// Shows a fake open dropdown so the viewer sees every option, then selects the value.
export async function selectByValue(driver, css, value) {
  await waitVisible(driver, css);
  await driver.executeScript(`
    const s = document.querySelector(arguments[0]);
    const rect = s.getBoundingClientRect();
    const menu = document.createElement('div');
    menu.id = '_sc_menu';
    Object.assign(menu.style, { position: 'fixed', zIndex: 2147483647, top: (rect.bottom + 4) + 'px', left: rect.left + 'px',
      background: '#fff', border: '1px solid #ccc', borderRadius: '6px', boxShadow: '0 4px 16px rgba(0,0,0,.18)',
      minWidth: '220px', font: '14px/1 -apple-system, sans-serif', pointerEvents: 'none', overflow: 'hidden' });
    Array.from(s.options).forEach(opt => {
      if (!opt.value) return;
      const item = document.createElement('div');
      item.textContent = opt.text;
      Object.assign(item.style, { padding: '9px 14px', color: '#222', whiteSpace: 'nowrap' });
      if (opt.value === arguments[1]) Object.assign(item.style, { background: '#0071e3', color: '#fff', fontWeight: 600 });
      menu.appendChild(item);
    });
    document.body.appendChild(menu);
  `, css, value);
  await sleep(1800);
  await driver.executeScript(`
    document.getElementById('_sc_menu')?.remove();
    const s = document.querySelector(arguments[0]);
    s.value = arguments[1];
    s.dispatchEvent(new Event('change', {bubbles:true}));
  `, css, value);
}

export async function scrollBottom(driver) {
  await driver.executeScript('window.scrollTo({top: document.body.scrollHeight, behavior: "smooth"})');
}

export async function scrollTop(driver) {
  await driver.executeScript('window.scrollTo({top: 0, behavior: "smooth"})');
}

// ── SIGN IN / OUT (this app: email + demo password) ──────────────────────────

export async function signIn(driver, email) {
  await driver.get(`${BASE_URL}/session/new`);
  await fill(driver, '#email_address', email);
  await fill(driver, '#password', DEMO_PASSWORD);
  await sleep(400);
  await clickButton(driver, 'Sign in');
  await driver.wait(async () => !(await driver.getCurrentUrl()).includes('/session'), 15000);
  await sleep(1000);
}

export async function signOut(driver) {
  await clickButton(driver, 'Sign out');
  await driver.wait(until.urlContains('/session/new'), 15000);
  await sleep(800);
}

// ── SUBTITLES AND FINAL MIX ──────────────────────────────────────────────────

function msToSrtTime(ms) {
  const pad = (n, w = 2) => String(n).padStart(w, '0');
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms % 3600000 / 60000))}:${pad(Math.floor(ms % 60000 / 1000))},${pad(ms % 1000, 3)}`;
}

function buildSrt(timeline) {
  return timeline.map((s, i) =>
    `${i + 1}\n${msToSrtTime(s.delayMs)} --> ${msToSrtTime(s.delayMs + getAudioDuration(s.file))}\n${s.narration}\n`
  ).join('\n');
}

function buildFinalVideo(rawVideo, outputFile, srtFile, timeline) {
  if (timeline.length === 0) { execSync(`mv "${rawVideo}" "${outputFile}"`); return; }
  writeFileSync(srtFile, buildSrt(timeline), 'utf8');
  console.log(`\nMixing ${timeline.length} narration clips into the video...`);
  const filters = timeline.map((s, i) => `[${i + 1}:a]adelay=${s.delayMs}|${s.delayMs}[a${i}]`);
  const mix = `${timeline.map((_, i) => `[a${i}]`).join('')}amix=inputs=${timeline.length}:duration=longest:normalize=0[aout]`;
  execSync([
    'ffmpeg -y', `-i "${rawVideo}"`, timeline.map(s => `-i "${s.file}"`).join(' '), `-i "${srtFile}"`,
    `-filter_complex "${[...filters, mix].join(';')}"`,
    '-map 0:v -map "[aout]"', `-map ${timeline.length + 1}:s`,
    '-c:v copy -c:a aac -c:s mov_text -metadata:s:s:0 language=eng', `-shortest "${outputFile}"`,
  ].join(' '), { stdio: 'inherit' });
  execSync(`rm -f "${rawVideo}" "${srtFile}"`);
}

// ── RUNNER ───────────────────────────────────────────────────────────────────

// Each window is its own fresh Chrome profile (separate sign-in, no cookies from your own Chrome),
// without the "controlled by automated software" bar. Selenium Manager fetches the matching chromedriver.
async function launchChrome() {
  const options = new chrome.Options()
    .excludeSwitches('enable-automation')
    .addArguments('--no-first-run', '--no-default-browser-check', '--disable-search-engine-choice-screen');
  options.setUserPreferences({ credentials_enable_service: false, 'profile.password_manager_enabled': false });
  return new Builder().forBrowser('chrome').setChromeOptions(options).build();
}

// steps: [{ id, narration, actions: async (...drivers) => {} }]. `windows` Chrome windows split the screen side by
// side, left to right, and are passed to every step's actions in that order. Narration and actions run together.
export async function runScreencast({ slug, outDir, steps, windows = 1 }) {
  // `say` silently falls back to the default voice for an unknown name, so check it is really installed.
  const voices = execSync(`say -v '?'`).toString().split('\n').map(line => line.split(/\s{2,}/)[0].trim());
  if (!voices.includes(VOICE)) throw new Error(`Voice "${VOICE}" is not installed (see \`say -v '?'\`); download it or set VOICE`);

  const audioDir = path.join(outDir, `audio_${slug}`);
  const outputFile = path.join(outDir, `screencast_${slug}.mp4`);
  const rawVideo = path.join(outDir, `_raw_${slug}.mp4`);
  const srtFile = path.join(outDir, `_subtitles_${slug}.srt`);
  mkdirSync(audioDir, { recursive: true });

  console.log(`Generating narration audio (voice: ${VOICE})...`);
  for (const step of steps) {
    if (step.narration) { step.audioFile = generateAudio(audioDir, step.id, step.narration); console.log(`  ✓ ${step.id}`); }
  }

  console.log(`\nLaunching ${windows} Chrome window(s) on screen ${SCREEN} against ${BASE_URL}...`);
  const area = displayArea();
  const width = Math.floor(area.width / windows);
  const drivers = [];
  for (let i = 0; i < windows; i++) {
    const driver = await launchChrome();
    await driver.manage().window().setRect({ x: area.x + i * width, y: area.y, width, height: area.height });
    drivers.push(driver);
  }

  console.log('Starting screen recording...');
  await sleep(1000);
  const ffmpeg = startScreenRecording(rawVideo);
  await sleep(1500);
  const recordingStart = Date.now();
  const timeline = [];

  try {
    for (const step of steps) {
      console.log(`▶  ${step.id}`);
      if (step.audioFile) timeline.push({ file: step.audioFile, delayMs: Date.now() - recordingStart, narration: step.narration });
      await Promise.all([step.audioFile ? playAudio(step.audioFile) : null, step.actions?.(...drivers)]);
      await sleep(500);
    }
    await sleep(5000);
  } finally {
    console.log('\nStopping recording...');
    await stopScreenRecording(ffmpeg);
    await Promise.all(drivers.map(d => d.quit()));
    buildFinalVideo(rawVideo, outputFile, srtFile, timeline);
    console.log(`\n✅  Screencast saved: ${outputFile}`);
  }
}
