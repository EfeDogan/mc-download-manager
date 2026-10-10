<p align="center">
  <img src="docs/icon.png" width="128" alt="MC Download Manager simgesi">
</p>

<h1 align="center">MC Download Manager</h1>

<p align="center">
  macOS için hızlı, açık kaynaklı bir indirme yöneticisi.<br>
  Safari ve Chrome indirmelerini yakalar, 16'ya kadar paralel bağlantıyla hızlandırır ve sayfalardaki videoları indirir.
</p>

<p align="center">
  <a href="README.md">🇬🇧 English</a> · <a href="https://github.com/mstcvk/mc-download-manager/releases">Sürümler</a>
</p>

---

Her şey tek bir `.app` içinde gelir: Safari uzantısı, Chrome uzantısı, `yt-dlp` ve `ffmpeg` uygulamaya gömülüdür.
DMG'yi açıp uygulamayı *Applications* klasörüne sürüklemek yeterlidir. Arayüz **İngilizce** ve **Türkçe**dir (sistem dilini izler).

## Özellikler

- **Çok parçalı indirme** — dosya HTTP `Range` isteklerine bölünür (varsayılan 8 bağlantı, 1–16 arası ayarlanabilir).
  Sunucu `Range` desteklemiyorsa tek akışa düşer; `429`/`503` sınırlamalarında bağlantı sayısı adaptif olarak azaltılır.
- **Duraklat / sürdür** — parça durumları diske yazılır; uygulama yeniden açılsa bile kaldığı yerden devam eder.
- **Tarayıcı entegrasyonu** — Safari ve Chrome (ve Chromium tabanlı tarayıcılar) için tek kaynaklı WebExtension.
  Tarayıcıdaki indirme iptal edilip çerezler, `Referer` ve `User-Agent` ile birlikte uygulamaya iletilir.
- **Video indirme** — sayfadaki `<video>`, `.m3u8` ve `.mpd` akışları yakalanır; "Bu sayfadaki videoyu indir" gömülü yt-dlp'yi
  (ffmpeg ile birleştirme dahil) kullanır. Üyelik gerektiren siteler için tarayıcı çerezleri yt-dlp'ye aktarılır.
- **Pano** — bir bağlantı kopyaladığınızda uygulama indirmek isteyip istemediğinizi sorar; ana pencereye ⌘V ile bağlantı yapıştırabilirsiniz.
- **Arayüz** — kenar çubuğunda kategoriler (Resim, Müzik, Video, Uygulama, Belge, Arşiv…), sıralanabilir tablo, arama,
  IDM tarzı dosya özelinde pencere (bağlantı tablosu, parça çubuğu, otomatik kapat seçeneği), menü çubuğu simgesi, bildirimler.
- **Arka planda çalışır** — isteğe bağlı oturumda başlatma; pencere kapansa bile tarayıcı köprüsü açık kalır.

<p align="center">
  <img src="docs/main-tr.png" width="720" alt="Ana pencere"><br>
  <img src="docs/detail.png" width="520" alt="İndirme penceresi">
</p>

## Kurulum

1. [Sürümler](https://github.com/mstcvk/mc-download-manager/releases) sayfasından DMG'yi indirin, açın ve **MC Download Manager.app**'i *Applications*'a sürükleyin.
   - Notarize edilmemiş derlemelerde ilk açılışta macOS uyarı verir: *Sistem Ayarları ▸ Gizlilik ve Güvenlik ▸ "Yine de Aç"*.
2. **Safari:** *Safari ▸ Ayarlar ▸ Uzantılar ▸ MC Download Manager* → etkinleştirin ve tüm web sitelerine izin verin.
   - Ad-hoc imzalı derlemelerde Safari ayrıca *Geliştirici ▸ İmzasız uzantılara izin ver* seçeneğini ister (Developer ID ile imzalı sürümlerde gerekmez).
3. **Chrome:** `chrome://extensions` ▸ *Geliştirici modu* ▸ *Paketlenmemiş öğe yükle* ▸ uygulama içindeki
   *Ayarlar ▸ Tarayıcı ▸ "Klasörü Göster"* ile açılan `ChromeExtension` klasörünü seçin.

Uygulama `127.0.0.1:48213` üzerinde yalnızca tarayıcı uzantılarından (`Origin` denetimi) istek kabul eden küçük bir HTTP köprüsü çalıştırır.

## Kaynaktan derleme

Gereksinimler: macOS 13+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
scripts/fetch-tools.sh   # universal yt-dlp ve ffmpeg (arm64 + x86_64) ikililerini Tools/ içine indirir
scripts/build.sh         # Release derler, imzalar ve build/MC Download Manager <sürüm>.dmg üretir
```

Geliştirme için `xcodegen generate` çalıştırıp `MCDownloadManager.xcodeproj`'yi Xcode'da açın.

Developer ID ile imzalama ve notarizasyon:

```bash
CODESIGN_IDENTITY="Developer ID Application: Ad Soyad (TEAMID)" NOTARY_PROFILE=notary scripts/build.sh
```

GitHub Actions iş akışı (`.github/workflows/build.yml`) her push'ta DMG üretir ve `v*` etiketlerinde Release'e ekler.

### Chrome eklentisini Web Store'da yayınlama

Chrome, eklentileri yalnızca Chrome Web Store'dan sessizce kurar; eklenti yayınlanana kadar uygulama kullanıcıyı
*Geliştirici modu ▸ Paketlenmemiş öğe yükle* adımlarıyla yönlendirir. Yayınlamak için:

```bash
scripts/pack-extension.sh      # → build/mc-download-manager-chrome-<sürüm>.zip
```

Zip'i [Chrome Web Store geliştirici konsoluna](https://chrome.google.com/webstore/devconsole) yükleyin, ardından
`BrowserIntegration.chromeWebStoreURL` değerini mağaza sayfası yapın; "Kur" doğrudan mağazayı açar.

## Köprü API'si

| Uç nokta | Açıklama |
|---|---|
| `GET /ping` | sürüm, yt-dlp durumu, aktif indirme sayısı |
| `POST /download` | `{url, filename?, referer?, userAgent?, cookieHeader?, cookies?[], kind: "file"\|"video", segments?}` |
| `GET /downloads` | son 50 indirmenin durumu |
| `POST /action` | `{id, action: "pause"\|"resume"\|"cancel"\|"remove"}` |

## Katkı

Issue ve pull request'ler memnuniyetle karşılanır. Çeviriler `App/Resources/Localizable.xcstrings` ve `Extension/_locales/` içindedir.

## Lisans

Kod MIT lisanslıdır (bkz. `LICENSE`). Gömülü ikililer kendi lisanslarına tabidir:
[yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense) ve [FFmpeg](https://ffmpeg.org) (martin-riedl.de statik derlemesi, GPL).
GPL'li ffmpeg ikilisi ile dağıtım yapıyorsanız kaynak erişimi yükümlülüğünü göz önünde bulundurun ya da `scripts/fetch-tools.sh` içindeki URL'yi LGPL bir derlemeyle değiştirin.
