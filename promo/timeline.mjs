// Lays out the 60 s timeline from the trimmed voice clips, detects sentence cues,
// writes out/timeline_<lang>.json, out/<lang>.srt and audio/<lang>/voice.wav.
// Usage: node timeline.mjs en|tr
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const lang = process.argv[2];
import { fileURLToPath } from "node:url";
const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const script = JSON.parse(fs.readFileSync(here("./script.json")));

const TOTAL = 60;
const LEAD = 0.6;     // silence before the first line
const TAIL = 3.2;     // logo hold after the last line
const VISUAL_LEAD = 0.35; // a scene starts this much before its voice

const duration = (f) => Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).toString());

function pausesOf(f) {
  const out = execFileSync("sh", ["-c", `ffmpeg -hide_banner -i "${f}" -af silencedetect=noise=-36dB:d=0.16 -f null - 2>&1`]).toString();
  const starts = [...out.matchAll(/silence_start: ([\d.]+)/g)].map((m) => +m[1]);
  const ends = [...out.matchAll(/silence_end: ([\d.]+) \| silence_duration: ([\d.]+)/g)].map((m) => ({ end: +m[1], dur: +m[2] }));
  return ends.map((e, i) => ({ start: starts[i], end: e.end, dur: e.dur }));
}

const sentencesOf = (text) => text.match(/[^.?!]+[.?!]+/g).map((s) => s.trim());

const clips = script.scenes.map((s) => {
  const file = here(`./audio/${lang}/${s.id}_trim.wav`);
  const dur = duration(file);
  const sentences = sentencesOf(s[lang]);
  const ps = pausesOf(file).filter((p) => p.end < dur - 0.05);
  // the N-1 longest pauses are the sentence boundaries
  const bounds = [...ps].sort((a, b) => b.dur - a.dur).slice(0, sentences.length - 1).sort((a, b) => a.start - b.start);
  let cues = [0, ...bounds.map((p) => p.end - 0.05)];
  if (bounds.length !== sentences.length - 1) {
    // fallback: proportional to characters
    const total = sentences.join("").length;
    let acc = 0;
    cues = sentences.map((t) => { const c = (acc / total) * dur; acc += t.length; return c; });
  }
  return { id: s.id, file, dur, sentences, cues };
});

const voiceTotal = clips.reduce((a, c) => a + c.dur, 0);
const gap = (TOTAL - LEAD - TAIL - voiceTotal) / (clips.length - 1);
if (gap < 0.5) console.warn(`warning: gap between scenes is only ${gap.toFixed(2)} s`);

let t = LEAD;
const scenes = clips.map((c, i) => {
  const voiceStart = t;
  t += c.dur + gap;
  return { id: c.id, voiceStart, voiceDur: c.dur, cues: c.cues.map((q) => voiceStart + q), sentences: c.sentences };
});
scenes.forEach((s, i) => {
  s.start = i === 0 ? 0 : s.voiceStart - VISUAL_LEAD;
  s.end = i === scenes.length - 1 ? TOTAL : scenes[i + 1].voiceStart - VISUAL_LEAD;
});

fs.mkdirSync(here("./out"), { recursive: true });
fs.writeFileSync(here(`./out/timeline_${lang}.json`), JSON.stringify({ lang, total: TOTAL, gap, scenes }, null, 2));

// subtitles: one cue per sentence, ending at the next sentence (or the clip end)
const ts = (x) => {
  const ms = Math.round(x * 1000);
  const p = (n, w = 2) => String(n).padStart(w, "0");
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
};
let n = 0;
const srt = scenes.flatMap((s, i) => (sentencesOf(script.scenes[i].subtitle?.[lang] ?? script.scenes[i][lang])).map((text, k) => {
  const a = s.cues[k];
  const b = k + 1 < s.cues.length ? s.cues[k + 1] - 0.05 : s.voiceStart + s.voiceDur + 0.3;
  return `${++n}\n${ts(a)} --> ${ts(b)}\n${text}\n`;
})).join("\n");
fs.writeFileSync(here(`./out/MC-Download-Manager-${lang}.srt`), srt);

// voice track: every clip delayed to its voiceStart, padded to TOTAL
const args = ["-v", "error", "-y"];
clips.forEach((c) => args.push("-i", c.file));
const filters = scenes.map((s, i) => `[${i}:a]aresample=48000,adelay=${Math.round(s.voiceStart * 1000)}:all=1[a${i}]`);
filters.push(`${scenes.map((_, i) => `[a${i}]`).join("")}amix=inputs=${scenes.length}:normalize=0,apad,atrim=0:${TOTAL}[v]`);
args.push("-filter_complex", filters.join(";"), "-map", "[v]", "-ac", "1", here(`./audio/${lang}/voice.wav`));
execFileSync("ffmpeg", args);

console.log(`${lang}: voice ${voiceTotal.toFixed(2)} s, gap ${gap.toFixed(2)} s`);
scenes.forEach((s) => console.log(` ${s.id.padEnd(9)} ${s.start.toFixed(2)}–${s.end.toFixed(2)}  voice@${s.voiceStart.toFixed(2)}  cues ${s.cues.map((c) => c.toFixed(2)).join(", ")}`));
