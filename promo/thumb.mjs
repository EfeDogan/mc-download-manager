// Renders the YouTube thumbnails (1280x720) and README previews with a play button.
// Usage: node thumb.mjs
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  args: ["--force-color-profile=srgb", "--hide-scrollbars"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });
for (const lang of ["en", "tr"]) {
  for (const play of [false, true]) {
    await page.goto(`file://${here("./thumbnail.html")}?lang=${lang}${play ? "&play=1" : ""}`);
    await page.evaluate(() => document.fonts.ready);
    const path = here(`./out/thumbnail_${lang}${play ? "_play" : ""}.png`);
    await page.screenshot({ path });
    console.log("wrote", path);
  }
}
await browser.close();
