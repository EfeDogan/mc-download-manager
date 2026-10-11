// Renders motion.html frame by frame in headless Chrome and pipes the frames into ffmpeg.
// Usage:
//   node render.mjs en                 → out/video_en.mp4 (silent, 1920x1080, 30 fps)
//   node render.mjs en --stills 3,14.2 → out/still_en_3.png, …
import fs from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const lang = process.argv[2];
const stillsArg = process.argv.indexOf("--stills");
const stills = stillsArg > 0 ? process.argv[stillsArg + 1].split(",").map(Number) : null;
const FPS = 30;
const timeline = JSON.parse(fs.readFileSync(here(`./out/timeline_${lang}.json`)));

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  args: ["--force-color-profile=srgb", "--hide-scrollbars", "--font-render-hinting=none"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
page.on("pageerror", (e) => { console.error("page error:", e.message); process.exitCode = 1; });
page.on("console", (m) => { if (m.type() === "error") console.error("console:", m.text()); });
await page.goto(`file://${here("./motion.html")}`);
await page.evaluate((tl) => window.setup(tl), timeline);

if (stills) {
  for (const t of stills) {
    await page.evaluate((x) => window.render(x), t);
    await page.screenshot({ path: here(`./out/still_${lang}_${t}.png`) });
    console.log("still", t);
  }
} else {
  const frames = Math.round(timeline.total * FPS);
  const out = here(`./out/video_${lang}.mp4`);
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709",
    "-colorspace", "bt709", "-movflags", "+faststart", out], { stdio: ["pipe", "inherit", "inherit"] });
  const started = Date.now();
  for (let f = 0; f < frames; f++) {
    await page.evaluate((x) => window.render(x), f / FPS);
    const buf = await page.screenshot({ type: "png", optimizeForSpeed: true });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (f % 150 === 0) console.log(`${lang} frame ${f}/${frames} (${((Date.now() - started) / 1000).toFixed(0)} s)`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  console.log("wrote", out);
}
await browser.close();
