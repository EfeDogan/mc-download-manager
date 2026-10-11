# YouTube upload kit

Files (in `promo/out/`):

| | English | Türkçe |
|---|---|---|
| Video (1920×1080, 30 fps, H.264 + AAC, −14 LUFS) | `MC-Download-Manager-en.mp4` | `MC-Download-Manager-tr.mp4` |
| Thumbnail (1280×720) | `thumbnail_en.png` | `thumbnail_tr.png` |
| Subtitles | `MC-Download-Manager-en.srt` | `MC-Download-Manager-tr.srt` |
| README preview (with play button) | `thumbnail_en_play.png` | `thumbnail_tr_play.png` |

Chapters need at least three entries of 10 s or more, so features are grouped.

---

## English

**Title**

MC Download Manager: Free, Open-Source Download Manager for macOS (Safari, Chrome, Brave)

**Description**

MC Download Manager is a fast, free and open-source download manager for macOS.

⚡ Up to 16 parallel connections per file, adapts automatically when a server throttles
⏯ Pause and resume, even after a restart
🌐 Safari, Chrome and Brave hand their downloads to the app, cookies included
🎬 Save videos from web pages (yt-dlp + ffmpeg built in, MP4 up to 1080p)
📋 Copy a link and it offers to download it
🗂 Automatic categories, lives in the menu bar
🇬🇧 🇹🇷 English and Turkish

Download (free, MIT license): https://github.com/mstcvk/mc-download-manager/releases
Source code: https://github.com/mstcvk/mc-download-manager

00:00 MC Download Manager
00:12 Multi-connection downloads & resume
00:28 Browser integration & video downloads
00:42 Clipboard, categories, menu bar & install

**Tags**

download manager, mac download manager, macos, free download manager, open source, safari extension, chrome extension, brave, yt-dlp, video downloader, idm alternative mac, multi connection download, swiftui

---

## Türkçe

**Başlık**

MC Download Manager: macOS için Ücretsiz ve Açık Kaynak İndirme Yöneticisi (Safari, Chrome, Brave)

**Açıklama**

MC Download Manager, macOS için hızlı, ücretsiz ve açık kaynak bir indirme yöneticisidir.

⚡ Dosya başına 16'ya kadar paralel bağlantı, sunucu yavaşlatınca otomatik uyum
⏯ Duraklatın ve sürdürün, bilgisayarı yeniden başlatsanız bile
🌐 Safari, Chrome ve Brave indirmeleri çerezleriyle birlikte uygulamaya aktarır
🎬 Web sayfalarındaki videoları kaydedin (yt-dlp + ffmpeg dahili, 1080p'ye kadar MP4)
📋 Bir bağlantı kopyalayın, indirmeyi önersin
🗂 Otomatik kategoriler, menü çubuğunda çalışır
🇹🇷 🇬🇧 Türkçe ve İngilizce arayüz

İndir (ücretsiz, MIT lisansı): https://github.com/mstcvk/mc-download-manager/releases
Kaynak kod: https://github.com/mstcvk/mc-download-manager

00:00 MC Download Manager
00:13 Çoklu bağlantı ve kaldığı yerden devam
00:28 Tarayıcı entegrasyonu ve video indirme
00:42 Pano, kategoriler, menü çubuğu ve kurulum

**Etiketler**

indirme yöneticisi, mac indirme yöneticisi, macos, ücretsiz indirme programı, açık kaynak, safari eklentisi, chrome eklentisi, brave, yt-dlp, video indirme, idm alternatifi mac, download manager, swiftui

---

## Rebuilding

```bash
cd promo && npm install
GEMINI_API_KEY=... ./build.sh en --tts   # Gemini TTS → trim → timeline → music → frames → mix
./build.sh tr                            # reuse existing voice clips
node thumb.mjs                           # thumbnails
```

Edit narration in `script.json` and visuals in `motion.html` (open `motion.html?lang=tr&t=14` via a local
web server to preview a single frame). The API key is only read from the environment.
