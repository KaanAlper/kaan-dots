# quickshell-custom — kişisel bar widget'ları

Bar'a eklenen kişisel ses widget'larının **otoriter (master) kopyaları** burada durur.
Bu dizin end-4 / illogical-impulse `installed_listfile`'ında **olmadığı** için dots
güncellemeleri buraya dokunmaz.

## Widget'lar
- **AudioMonoToggle** — `pw-loopback` tabanlı mono/stereo geçişi.
  - `AudioMonoToggle.qml` — bar widget'ı (master).
  - `audio-mono-toggle.sh` — geçiş script'i (master).
- **AudioOutputSwitcher** — çıkış cihazını (sink) seçtiren widget.
  - `AudioOutputSwitcher.qml` — bar widget'ı (master). QML; ayrı .sh dosyası yok ama
    availability için `pactl`'e bir Process ile danışır.
  - İkona tıkla → kullanılabilir çıkışların listesi açılır; bir satıra tıklayınca o cihaz
    varsayılan çıkış olur (`Audio.setDefaultSink`). Aktif cihaz ✓ işaretli. Dışarı tıkla → kapan
    (HyprlandFocusGrab). İkon mevcut çıkışa göre değişir (kulaklık / hoparlör / HDMI / bluetooth).
  - **Availability filtresi:** PwNode port durumunu vermediği için `pactl list sinks`
    (`LC_ALL=C`) okunur; portu "not available" olan çıkışlar (takılı olmayan HDMI/DP)
    gizlenir, "available"/"unknown" olanlar ve o an aktif olan gösterilir. Tetikleme:
    başlangıç + popup açılışı + cihaz listesi değişimi.

## Uygulama / deploy
- `apply.sh` — yukarıdaki master dosyaları dots ağacına geri kopyalar + `BarContent.qml`'i
  yamalar (her iki widget'ı SysTray'den önce ekler) + bar'ı reload eder.

## Dots güncellemesinden sonra
Güncelleme `BarContent.qml`'i (ve olası yeni dosyaları) sıfırlar. Tek komutla geri al:

```sh
~/.config/quickshell-custom/apply.sh
```

İdempotenttir, kaç kez çalıştırılırsa çalıştırılsın güvenlidir.

## İkonu/davranışı değiştirmek
Önce buradaki **master** dosyayı düzenle, sonra `apply.sh` çalıştır. (Doğrudan
`~/.config/quickshell/ii/...` içindekini düzenlersen değişiklik güncellemede kaybolur.)

## Kilit ekranı yüz tanıma (Howdy)
- `pam/howdy.conf` — `auth sufficient pam_howdy.so` (şifre her zaman çalışır).
- `patch-lock-howdy.py` — idempotent yama: `LockContext.qml` (facePam + faceState) ve
  `LockSurface.qml` (Windows Hello tarzı yüz simgesi: taranıyor=nabız, başarısız=kırmızı,
  tıklayınca yeniden tara; placeholder'da durum yazısı). `apply.sh` çağırır.
- `pam_howdy.so` yoksa yüz taraması hiç başlamaz (faceAvailable=false).
- Dots güncellemesi yamayı silerse `~/.config/hypr/custom/execs.lua` oturum açılışında
  `apply.sh`'i kendiliğinden çalıştırır (LockSurface'te `faceState` yoksa).
- Howdy tarafı (sistem): `/etc/howdy/config.ini` device_path=/dev/video2; cv2 sorunu için
  `/usr/lib/howdy/cv2` içine headless wheel kuruldu (kurulum: `~/build/howdy/setup.sh`).
  Tam sistem güncellemesi (vtk dahil) sonrası `/usr/lib/howdy/cv2*` silinebilir.
