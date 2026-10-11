// Synthesises a royalty-free music bed + transition whooshes aligned to the timeline.
// Usage: node music.mjs en|tr → audio/<lang>/music.wav (48 kHz stereo)
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const lang = process.argv[2];
const tl = JSON.parse(fs.readFileSync(here(`./out/timeline_${lang}.json`)));
const SR = 48000, T = tl.total, N = Math.round(SR * T);
const Lch = new Float32Array(N), Rch = new Float32Array(N);

const BPM = 120, BEAT = 60 / BPM, BAR = BEAT * 4;
const sc = Object.fromEntries(tl.scenes.map((s) => [s.id, s]));
const DROP = sc.intro.start;                 // groove starts with the logo
const LOCKUP = sc.outro.cues[3] - 0.1;       // final lockup → groove stops, ring out
const ENDFADE = T - 2.2;

let seed = 12345;
const noise = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 2147483648 - 1);
const add = (i, l, r = l) => { if (i >= 0 && i < N) { Lch[i] += l; Rch[i] += r; } };
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

// D – A – Bm – G, one chord per bar (MIDI notes)
const chords = [
  { root: 38, tones: [62, 66, 69] },
  { root: 33, tones: [57, 61, 64] },
  { root: 35, tones: [59, 62, 66] },
  { root: 31, tones: [55, 59, 62] },
];
const chordAt = (t) => chords[Math.floor(Math.max(0, t) / BAR) % 4];

// groove amount: 0 before the drop, 1 in the body, fades after the lockup
const groove = (t) => (t < DROP ? 0 : t < LOCKUP ? 1 : Math.max(0, 1 - (t - LOCKUP) / 0.25));
const pump = (t) => { if (groove(t) <= 0) return 1; const tb = (t - DROP) % BEAT; return 1 - 0.55 * groove(t) * Math.exp(-tb * 9); };
const master = (t) => Math.min(1, t / 1.2) * (t > ENDFADE ? Math.max(0, 1 - (t - ENDFADE) / 2.2) : 1);

// --- pad (detuned saw-ish, slow low-pass that opens at the drop) ---
{
  const lpL = { y: 0 }, lpR = { y: 0 };
  const ph = new Float64Array(12);
  for (let i = 0; i < N; i++) {
    const t = i / SR, ch = chordAt(t);
    const xf = Math.min(1, ((t % BAR) / 0.08)); // tiny crossfade at chord edges hidden by the LP
    let l = 0, r = 0;
    ch.tones.forEach((m, k) => {
      for (let v = 0; v < 2; v++) {
        const f = hz(m) * (v ? 1.004 : 0.996);
        const idx = k * 2 + v;
        ph[idx] += f / SR;
        const p = ph[idx] % 1;
        let s = 0;
        for (let h = 1; h <= 6; h++) s += Math.sin(2 * Math.PI * p * h) / h;
        if (v) r += s; else l += s;
      }
    });
    const cutoff = t < DROP ? 500 + 1300 * (t / DROP) : t < LOCKUP ? 2400 : 2400 - 1600 * Math.min(1, (t - LOCKUP) / 3);
    const a = 1 - Math.exp(-2 * Math.PI * cutoff / SR);
    lpL.y += a * (l - lpL.y); lpR.y += a * (r - lpR.y);
    const g = 0.05 * pump(t) * master(t) * (0.6 + 0.4 * xf);
    add(i, lpL.y * g, lpR.y * g);
  }
}

// --- drums, bass, arp: event based ---
function kick(t0, amp = 1) {
  let ph = 0;
  for (let j = 0; j < SR * 0.4; j++) {
    const t = j / SR, f = 48 + 110 * Math.exp(-t * 32);
    ph += f / SR;
    const s = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 7) + (j < 120 ? noise() * 0.3 * (1 - j / 120) : 0);
    add(Math.round(t0 * SR) + j, s * 0.42 * amp);
  }
}
function clap(t0, amp = 1) {
  let lp = 0;
  for (let j = 0; j < SR * 0.25; j++) {
    const t = j / SR, n = noise();
    lp += 0.25 * (n - lp);
    const hp = n - lp;
    const env = Math.exp(-t * 20) * (t < 0.02 ? 0.6 + 0.4 * Math.sin(t * 900) : 1);
    const s = hp * env * 0.16 + Math.sin(2 * Math.PI * 190 * t) * Math.exp(-t * 30) * 0.08;
    add(Math.round(t0 * SR) + j, s * amp, s * amp * 0.9);
  }
}
function hat(t0, amp = 1, open = false) {
  let lp = 0;
  for (let j = 0; j < SR * (open ? 0.22 : 0.06); j++) {
    const t = j / SR, n = noise();
    lp += 0.6 * (n - lp);
    const s = (n - lp) * Math.exp(-t * (open ? 14 : 70)) * 0.07 * amp;
    add(Math.round(t0 * SR) + j, s * 0.8, s);
  }
}
function bass(t0, m, dur, amp = 1) {
  let ph = 0, lp = 0;
  for (let j = 0; j < SR * dur; j++) {
    const t = j / SR, f = hz(m);
    ph += f / SR;
    const p = ph % 1;
    const raw = Math.sin(2 * Math.PI * p) + 0.5 * Math.sin(4 * Math.PI * p) + 0.25 * Math.sin(6 * Math.PI * p);
    lp += 0.08 * (raw - lp);
    const env = Math.min(1, t / 0.005) * Math.exp(-t * 4) * Math.min(1, (dur - t) / 0.01);
    add(Math.round(t0 * SR) + j, lp * env * 0.16 * amp);
  }
}
function pluck(t0, m, amp = 1, pan = 0) {
  for (let j = 0; j < SR * 0.45; j++) {
    const t = j / SR, f = hz(m);
    const s = (Math.sin(2 * Math.PI * f * t) + 0.35 * Math.sin(4 * Math.PI * f * t)) * Math.exp(-t * 10) * Math.min(1, t / 0.003);
    add(Math.round(t0 * SR) + j, s * 0.045 * amp * (1 - pan), s * 0.045 * amp * (1 + pan));
  }
}
function whoosh(tc, amp = 1, rise = 0.45, fall = 0.35) {
  let lp1 = 0, lp2 = 0;
  const n0 = Math.round((tc - rise) * SR), len = Math.round((rise + fall) * SR);
  for (let j = 0; j < len; j++) {
    const t = j / SR - rise;                       // -rise … fall, peak at 0
    const env = t < 0 ? Math.pow(1 + t / rise, 2.2) : Math.exp(-t * 9);
    const fc = 400 + 5200 * (t < 0 ? 1 + t / rise : Math.exp(-t * 6));
    const a = 1 - Math.exp(-2 * Math.PI * fc / SR);
    const n = noise();
    lp1 += a * (n - lp1); lp2 += a * (lp1 - lp2);
    const band = lp1 - lp2;
    const pan = Math.sin((j / len) * Math.PI * 2) * 0.5;
    add(n0 + j, band * env * 0.5 * amp * (1 - pan), band * env * 0.5 * amp * (1 + pan));
  }
}
function riser(t0, t1, amp = 1) {
  let lp = 0;
  for (let i = Math.round(t0 * SR); i < Math.round(t1 * SR); i++) {
    const x = (i / SR - t0) / (t1 - t0), n = noise();
    const a = 1 - Math.exp(-2 * Math.PI * (300 + 6000 * x * x) / SR);
    lp += a * (n - lp);
    add(i, lp * x * x * 0.22 * amp, lp * x * x * 0.22 * amp);
  }
}
function impact(t0, amp = 1) {
  kick(t0, 1.3 * amp);
  let lp = 0, ph = 0;
  for (let j = 0; j < SR * 1.6; j++) {
    const t = j / SR, n = noise();
    lp += 0.5 * (n - lp);
    ph += (40 + 30 * Math.exp(-t * 4)) / SR;
    const s = (n - lp) * Math.exp(-t * 3.2) * 0.12 + Math.sin(2 * Math.PI * ph) * Math.exp(-t * 2.5) * 0.25;
    add(Math.round(t0 * SR) + j, s * amp, s * amp);
  }
}

// hook: a nervous ticking pulse that builds into the drop
for (let t = BEAT; t < DROP - 0.05; t += BEAT / 2) hat(t, 0.5 + 0.5 * (t / DROP));
for (let t = 0; t < DROP - 0.05; t += BEAT) bass(t, chordAt(t).root + 12, 0.18, 0.5);
riser(DROP - 1.4, DROP, 1);
impact(DROP, 1);

// body groove (grid anchored on the drop)
for (let t = DROP; t < LOCKUP - 0.01; t += BEAT / 4) {
  const step = Math.round((t - DROP) / (BEAT / 4)) % 16, ch = chordAt(t);
  if (step % 4 === 0 && t > DROP + 0.01) kick(t, 0.9);
  if (step === 4 || step === 12) clap(t, 0.8);
  if (step % 2 === 1 && step % 4 !== 1) hat(t, 0.8);
  if (step % 4 === 2) hat(t, 0.6, step === 14);
  if (step % 2 === 0) bass(t, ch.root + 12, BEAT / 2 - 0.02, 0.9);
  const arp = [0, 1, 2, 1, 0, 2, 1, 2];
  pluck(t, ch.tones[arp[step % 8]] + 12, step % 4 === 0 ? 1 : 0.7, (step % 2 ? 0.35 : -0.35));
}
// final lockup: impact + a ringing D major arpeggio
impact(LOCKUP, 0.8);
[62, 66, 69, 74, 78, 81].forEach((m, k) => pluck(LOCKUP + 0.05 + k * BEAT / 4, m, 1.1, (k % 2 ? 0.3 : -0.3)));
[50, 57].forEach((m) => bass(LOCKUP, m, 2.5, 0.8));

// whooshes on every scene change after the drop
tl.scenes.slice(2).forEach((s) => whoosh(s.start + 0.05, 0.9));
whoosh(sc.resume.cues[1] + 0.05, 0.6, 0.3, 0.6);   // the "restart" blackout

// master: soft clip, normalise, write 16-bit WAV
let peak = 0;
for (let i = 0; i < N; i++) {
  const m = master(i / SR);
  Lch[i] = Math.tanh(Lch[i] * 1.2) * m; Rch[i] = Math.tanh(Rch[i] * 1.2) * m;
  peak = Math.max(peak, Math.abs(Lch[i]), Math.abs(Rch[i]));
}
const gain = 0.89 / peak;
const buf = Buffer.alloc(44 + N * 4);
buf.write("RIFF", 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write("WAVE", 8); buf.write("fmt ", 12);
buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24);
buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write("data", 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(clamp16(Lch[i] * gain) * 32767), 44 + i * 4);
  buf.writeInt16LE(Math.round(clamp16(Rch[i] * gain) * 32767), 46 + i * 4);
}
function clamp16(x) { return Math.max(-1, Math.min(1, x)); }
fs.mkdirSync(here(`./audio/${lang}/`), { recursive: true });
fs.writeFileSync(here(`./audio/${lang}/music.wav`), buf);
console.log(`${lang}: music written (drop ${DROP.toFixed(2)} s, lockup ${LOCKUP.toFixed(2)} s)`);
