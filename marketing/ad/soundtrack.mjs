// Original score and sound design for the ad, synthesized sample by sample so timing is exact and the
// licensing is unambiguous. Reads the same cue sheet as the picture (cues.js) and writes soundtrack.wav.
//
//   node soundtrack.mjs
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { T, BEAT } = createRequire(import.meta.url)('./cues.js');
const SR = 48000;
const LEN = Math.ceil(T.duration * SR);
const L = new Float32Array(LEN), Rt = new Float32Array(LEN);
const music = { L: new Float32Array(LEN), R: new Float32Array(LEN) };
const sfx = { L: new Float32Array(LEN), R: new Float32Array(LEN) };
const STEP = BEAT / 4; // a sixteenth note

// Deterministic noise.
let seed = 0x9e3779b9;
const rand = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 * 2 - 1; };
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const TAU = Math.PI * 2;

/** Writes `fn(localTime)` into a bus from `t0` for `dur` seconds, panned with equal power (-1 left … 1 right). */
function render(bus, t0, dur, fn, pan = 0, gain = 1) {
  const start = Math.max(0, Math.floor(t0 * SR)), end = Math.min(LEN, Math.floor((t0 + dur) * SR));
  const a = (pan + 1) * Math.PI / 4, gl = Math.cos(a) * gain, gr = Math.sin(a) * gain;
  for (let i = start; i < end; i++) { const v = fn((i - t0 * SR) / SR); bus.L[i] += v * gl; bus.R[i] += v * gr; }
}
const env = (t, attack, decay) => (t < attack ? t / attack : Math.exp(-(t - attack) / decay));

// ───────────────────────── Instruments ─────────────────────────
/** Soft synth pluck: bright attack, upper harmonics fall away quickly. */
function pluck(t0, midi, gain = 0.12, pan = 0, bus = music) {
  const f = mtof(midi);
  for (const [det, p] of [[-0.0025, pan - 0.25], [0.0025, pan + 0.25]]) {
    const fd = f * (1 + det);
    render(bus, t0, 0.9, (t) => {
      let v = 0;
      for (let h = 1; h <= 9; h++) v += Math.sin(TAU * fd * h * t) / h * Math.exp(-t * (3.2 + h * 2.1));
      return v * Math.min(1, t / 0.003);
    }, clamp(p), gain * 0.5);
  }
}
/** Warm, rounded bass. */
function bass(t0, midi, dur, gain = 0.34) {
  const f = mtof(midi);
  render(music, t0, dur + 0.08, (t) => {
    const e = Math.min(1, t / 0.008) * (t > dur ? Math.exp(-(t - dur) / 0.03) : 1) * (0.85 + 0.15 * Math.exp(-t / 0.12));
    return (Math.sin(TAU * f * t) + 0.28 * Math.sin(TAU * 2 * f * t) + 0.08 * Math.sin(TAU * 3 * f * t)) * e;
  }, 0, gain);
}
/** Tight, muted kick. */
function kick(t0, gain = 0.55) {
  let phase = 0;
  render(music, t0, 0.32, (t) => {
    const f = 46 + 110 * Math.exp(-t / 0.035);
    phase += TAU * f / SR;
    return Math.sin(phase) * env(t, 0.002, 0.11) + rand() * 0.25 * Math.exp(-t / 0.003);
  }, 0, gain);
}
/** Soft clap: a few quick bursts of band-limited noise. */
function clap(t0, gain = 0.16) {
  let lp = 0, lp2 = 0;
  render(music, t0, 0.22, (t) => {
    const n = rand(); lp += 0.35 * (n - lp); lp2 += 0.08 * (lp - lp2);
    const band = lp - lp2;
    const bursts = [0, 0.009, 0.018].reduce((s, d) => s + (t >= d ? Math.exp(-(t - d) / (d === 0.018 ? 0.07 : 0.006)) : 0), 0);
    return band * bursts * 2.2 + Math.sin(TAU * 185 * t) * Math.exp(-t / 0.03) * 0.3;
  }, 0.05, gain);
}
/** Closed hat and shaker: high-passed noise. */
function hat(t0, gain = 0.05, decay = 0.028, pan = 0.25) {
  let lp = 0;
  render(music, t0, decay * 5, (t) => { const n = rand(); lp += 0.55 * (n - lp); return (n - lp) * env(t, 0.001, decay); }, pan, gain);
}
function shaker(t0, gain = 0.035) {
  let lp = 0;
  render(music, t0, 0.12, (t) => { const n = rand(); lp += 0.6 * (n - lp); return (n - lp) * env(t, 0.012, 0.035); }, -0.35, gain);
}
/** Glass-like FM bell: Nudge's tonal accents. */
function bell(t0, midi, gain = 0.1, pan = 0, decay = 0.55, bus = sfx) {
  const f = mtof(midi);
  gain *= 1.25;
  render(bus, t0, decay * 5, (t) => {
    const index = 1.8 * Math.exp(-t / 0.18);
    return Math.sin(TAU * f * t + index * Math.sin(TAU * f * 3.5 * t)) * env(t, 0.002, decay) + 0.25 * Math.sin(TAU * f * 2 * t) * env(t, 0.002, decay * 0.4);
  }, pan, gain);
}
/** Soft pad: detuned sines with a slow swell. */
function pad(t0, notes, dur, gain = 0.035) {
  for (const m of notes) for (const det of [-0.004, 0.004]) {
    const f = mtof(m) * (1 + det);
    render(music, t0, dur + 0.8, (t) => {
      const e = Math.min(1, t / 0.35) * (t > dur ? Math.exp(-(t - dur) / 0.35) : 1);
      return (Math.sin(TAU * f * t) + 0.18 * Math.sin(TAU * 2 * f * t)) * e;
    }, det > 0 ? 0.35 : -0.35, gain);
  }
}
/** Almost inaudible air when Nudge travels, swept across the stereo field. */
function whoosh(t0, dur = 0.32, gain = 0.05, from = 0, to = 0) {
  let lp = 0;
  const start = Math.max(0, Math.floor(t0 * SR)), end = Math.min(LEN, Math.floor((t0 + dur) * SR));
  for (let i = start; i < end; i++) {
    const t = (i - t0 * SR) / SR, p = t / dur;
    const cutoff = 0.02 + 0.2 * Math.sin(Math.PI * p);
    lp += cutoff * (rand() - lp);
    const v = lp * Math.sin(Math.PI * p) ** 2 * gain * 3;
    const a = (lerp(from, to, p) + 1) * Math.PI / 4;
    sfx.L[i] += v * Math.cos(a); sfx.R[i] += v * Math.sin(a);
  }
}
/** The person's own clicks and keys: tiny and dry. */
function click(t0, gain = 0.07, pitch = 2400) {
  render(sfx, t0, 0.03, (t) => (rand() * Math.exp(-t / 0.0025) + Math.sin(TAU * pitch * t) * Math.exp(-t / 0.004) * 0.4), 0.1, gain);
}
const clamp = (v) => Math.max(-1, Math.min(1, v));
const lerp = (a, b, p) => a + (b - a) * p;

// ───────────────────────── Score ─────────────────────────
const CH = {
  F: { bass: 41, notes: [57, 60, 64, 67] }, G: { bass: 43, notes: [59, 62, 64, 69] },
  Em: { bass: 40, notes: [55, 59, 62, 64] }, Am: { bass: 45, notes: [60, 64, 67, 71] },
  C: { bass: 36, notes: [64, 67, 71, 74] },
};
// One chord per two-second bar; the payoff lifts to G for "found it", and the hero resolves to C.
const HARMONY = [[0, 'F'], [2, 'G'], [4, 'Em'], [6, 'Am'], [8, 'F'], [10, 'G'], [12, 'Em'], [14, 'F'], [15.5, 'G'], [16, 'C']];
const chordAt = (t) => { let c = 'F'; for (const [time, name] of HARMONY) if (t >= time - 1e-6) c = name; return CH[c]; };

const inPause = (t) => t >= T.pause && t < T.found - 0.05;
const explaining = () => false;
// The busiest stretch: Calculator, Safari and the area.
const montage = (t) => t >= T.calc && t < T.pause;
const end = T.resolve;

for (let step = 0; step * STEP < end; step++) {
  const t = step * STEP, s16 = step % 16, beat = step % 4 === 0;
  const ch = chordAt(t);
  if (inPause(t)) continue;
  const soft = explaining(t) ? 0.55 : 1;
  // Drums.
  if (s16 === 0 || s16 === 8) kick(t, t < 2 ? 0.28 : 0.36);
  if (montage(t) && s16 === 14) kick(t, 0.24);
  if (t >= 2 && (s16 === 4 || s16 === 12)) clap(t, 0.15 * soft);
  if (step % 2 === 1) hat(t, (s16 % 4 === 2 ? 0.07 : 0.042) * soft);
  if (montage(t)) shaker(t);
  // Bass: rounded, a little syncopated.
  const bassHits = { 0: [0, 3], 6: [0, 1], 8: [0, 2], 11: [7, 2], 14: [12, 1] };
  if (bassHits[s16] && t >= 1.0) { const [interval, len] = bassHits[s16]; bass(t, ch.bass + interval, len * STEP * 0.9, 0.19 * (explaining(t) ? 0.8 : 1)); }
  // Chord stabs on a syncopated grid.
  const stab = { 0: 1, 3: 0.7, 6: 0.85, 8: 0.75, 11: 0.8, 14: 0.65 }[s16];
  if (stab) {
    const top = ch.notes.slice(s16 === 0 ? 0 : 1);
    top.forEach((m, i) => pluck(t + i * 0.006, m, 0.12 * stab * soft, (i - 1.5) * 0.25));
  }
}
// Momentum pauses: a held chord under the type, then a lift into "found it".
pad(T.pause, CH.F.notes, T.found - T.pause - 0.1, 0.045);
pluck(T.pause, CH.F.notes[3] + 12, 0.07, 0.2);
pluck(15.5, CH.G.notes[3] + 12, 0.07, -0.2);
// A warm bed under the hero and the call to action.
pad(16, CH.C.notes, T.duration - 16 - 0.6, 0.04);
pad(0, CH.F.notes, 2, 0.018); pad(2, CH.G.notes, 2, 0.018);

// ───────────────────────── Sound design ─────────────────────────
// Nudge's own sounds, from the app (SoundEffects.swift): rising bubbles when a scan starts, a "pop-pop" when the guide is ready.
function bubbles(t0, list, gain = 0.5, pan = 0) {
  for (const [at, f0, glide, length, decay, g] of list) {
    let phase = 0;
    render(sfx, t0 + at, length, (t) => {
      phase += TAU * f0 * Math.pow(glide, Math.min(1, t / length * 1.6)) / SR;
      return (Math.sin(phase) + 0.18 * Math.sin(2 * phase)) * Math.min(1, t / 0.004) * Math.exp(-t / decay) * g;
    }, pan, gain);
  }
}
const SCAN = [[0, 480, 1.7, 0.12, 0.035, 0.45], [0.075, 600, 1.7, 0.12, 0.035, 0.42], [0.14, 720, 1.75, 0.12, 0.035, 0.4], [0.21, 900, 1.8, 0.14, 0.04, 0.4], [0.27, 1800, 1.2, 0.1, 0.03, 0.12]];
const READY = [[0, 560, 1.5, 0.14, 0.05, 0.5], [0.09, 840, 1.5, 0.18, 0.07, 0.5], [0.16, 1680, 1.15, 0.2, 0.06, 0.15], [0.2, 2240, 1.1, 0.15, 0.04, 0.08]];
// Each shortcut: the keys, then Nudge's scan sound. Choosing an area starts the scan when the box is confirmed.
for (const t of [T.keys, T.safariKeys, T.areaKeys]) [0, 0.05, 0.1, 0.16].forEach((d) => click(t + d, 0.05, 1900));
for (const t of [T.keys + 0.2, T.safariKeys + 0.2, T.clickExplain + 0.04]) bubbles(t, SCAN, 0.2);
// A guide is ready.
for (const t of [T.overview, T.webStep, T.areaCard]) bubbles(t, READY, 0.2);
// Space moves to the next step.
for (const t of [T.space1, T.space2]) click(t + 0.16, 0.06, 1500);
// The person's clicks, and the drag.
for (const t of [T.click1, T.clickWeb, T.clickExplain, T.dragStart - 0.04]) click(t, 0.07, 2600);
click(T.dragEnd + 0.02, 0.04, 2200);
// Travel.
for (const [t, gain, from, to] of [[T.launch, 0.07, 0.3, -0.1], [T.loading, 0.05, -0.4, 0.4], [T.step1 - 0.05, 0.03, 0.2, -0.2], [T.step2 - 0.05, 0.03, -0.2, 0.2],
  [T.step3 - 0.05, 0.035, 0.3, -0.4], [T.calc - 0.12, 0.06, -0.4, 0.5], [T.safariKeys - 0.12, 0.05, 0.4, -0.2], [T.webStep - 0.1, 0.035, 0.2, -0.3],
  [T.pause, 0.05, 0.4, -0.3], [T.hero, 0.04, 0.3, 0]]) whoosh(t, 0.34, gain, from, to);
// Highlights landing: a soft glass accent in the chord of the moment.
for (const [t, pan] of [[T.step1, -0.2], [T.step2, 0.3], [T.step3, -0.4], [T.calc + 0.05, 0.2], [T.webStep, -0.3], [T.clickExplain + 0.04, 0], [T.targetCTA, 0]]) {
  const ch = chordAt(t); bell(t, ch.notes[3] + 24, 0.04, pan, 0.28, music);
}
// Payoff: the two-note motif on "found it", and once more resolving at the end.
bell(T.found + 0.02, 79, 0.085, 0, 0.5); bell(T.found + 0.02 + BEAT / 4, 84, 0.095, 0, 0.7);
bell(T.resolve - BEAT / 2, 79, 0.08, -0.1, 0.5); bell(T.resolve - BEAT / 4, 84, 0.09, 0.1, 0.6);
CH.C.notes.forEach((m, i) => bell(T.resolve + i * 0.018, m + 12, 0.045, (i - 1.5) * 0.3, 1.1, music));
bass(T.resolve, 36, 0.9, 0.22); kick(T.resolve, 0.32);
CH.C.notes.forEach((m, i) => pluck(T.resolve + i * 0.012, m, 0.09, (i - 1.5) * 0.3));
bell(T.wink, 100, 0.03, 0.3, 0.3);

// ───────────────────────── Mix ─────────────────────────
const fadeOut = (i) => { const t = i / SR, tail = T.duration - 0.45; return t < tail ? 1 : Math.max(0, 1 - (t - tail) / 0.45); };
let peak = 0;
// A gentle high-pass keeps sub-bass from eating phone-speaker headroom.
const hpA = Math.exp(-TAU * 38 / SR);
let hlx = 0, hly = 0, hrx = 0, hry = 0;
for (let i = 0; i < LEN; i++) {
  const g = fadeOut(i);
  const inL = music.L[i] * 0.9 + sfx.L[i], inR = music.R[i] * 0.9 + sfx.R[i];
  hly = hpA * (hly + inL - hlx); hlx = inL; hry = hpA * (hry + inR - hrx); hrx = inR;
  const l = Math.tanh(hly * 1.3) / 1.3 * g;
  const r = Math.tanh(hry * 1.3) / 1.3 * g;
  L[i] = l; Rt[i] = r; peak = Math.max(peak, Math.abs(l), Math.abs(r));
}
const norm = 0.89 / (peak || 1); // about -1 dBFS
const data = Buffer.alloc(44 + LEN * 4);
data.write('RIFF', 0); data.writeUInt32LE(36 + LEN * 4, 4); data.write('WAVE', 8); data.write('fmt ', 12);
data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22); data.writeUInt32LE(SR, 24); data.writeUInt32LE(SR * 4, 28);
data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34); data.write('data', 36); data.writeUInt32LE(LEN * 4, 40);
for (let i = 0; i < LEN; i++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * norm)) * 32767), 44 + i * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, Rt[i] * norm)) * 32767), 46 + i * 4);
}
writeFileSync(join(here, 'soundtrack.wav'), data);
console.log(`soundtrack.wav · ${T.duration}s · peak normalized from ${peak.toFixed(3)}`);
