// Generates one WAV per scene with Gemini TTS (Interactions API, designed voice).
// Usage: GEMINI_API_KEY=... node tts.mjs en|tr [sceneId ...]
import fs from "node:fs";

const key = process.env.GEMINI_API_KEY;
if (!key) throw new Error("GEMINI_API_KEY is not set");
const [lang, ...only] = process.argv.slice(2);
const script = JSON.parse(fs.readFileSync(new URL("./script.json", import.meta.url)));
fs.mkdirSync(new URL(`./audio/${lang}/`, import.meta.url), { recursive: true });

async function synth(text) {
  const body = {
    model: script.model,
    input: [{
      type: "user_input",
      content: [{ type: "text", text, annotations: [{ type: "speech_metadata", style: script.style[lang] }] }],
    }],
    generation_config: { speech_config: [{ voice: script.voice }] },
  };
  for (let attempt = 1; ; attempt++) {
    const res = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
      method: "POST",
      headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const json = await res.json();
    const audio = json.steps?.flatMap((s) => s.content ?? []).find((c) => c.type === "audio");
    if (res.ok && audio) return Buffer.from(audio.data, "base64");
    if (attempt >= 4) throw new Error(`TTS failed: ${res.status} ${JSON.stringify(json).slice(0, 400)}`);
    await new Promise((r) => setTimeout(r, 2000 * attempt));
  }
}

await Promise.all(script.scenes
  .filter((s) => only.length === 0 || only.includes(s.id))
  .map(async (s) => {
    const wav = await synth(s[lang]);
    fs.writeFileSync(new URL(`./audio/${lang}/${s.id}.wav`, import.meta.url), wav);
    console.log(lang, s.id, wav.length);
  }));
