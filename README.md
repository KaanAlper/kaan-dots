# kaan-dots

Kişisel Hyprland / quickshell ayarlarım ve **eksik olanları otomatik tamamlayan** küçük bir istemci (`dotsync`).

Her oturum açılışında GitHub'daki bu repo ile yerel durum karşılaştırılır. Yerelde **olmayan** bir şey varsa
bir pencere açılır: eksikler onay kutularıyla listelenir, işaretlediklerin indirilir.
İşaretlemediklerin "istemiyorum" sayılır ve **bir daha sorulmaz** (`Reddedilenleri sıfırla` ile geri açılır).
Hiçbir şey eksik değilse pencere açılmaz.

## Öğeler (`manifest.json`)

| id | ne | nasıl denetlenir |
|---|---|---|
| `qs-custom` | quickshell ses widget'ları + kilit ekranı yüz tanıma yaması (`apply.sh`) | dosyalar var mı |
| `hypr-custom` | Hyprland kısayol/kural/hypridle/execs | dosyalar var mı |
| `howdy-packages` | `python-dlib` (CPU) + `howdy-git` | `pacman -Q` |
| `howdy-config` | IR kamera + cv2 çakışma çözümü | bildirimsel kontrol |

## Güvenlik modeli
- Açılıştaki denetim yalnızca **veri okur**; manifestten gelen komutlar sen "indir" demeden çalışmaz.
- `check` kuralları bildirimsel (`exists`, `file_lacks`), kabuk komutu içermez.
- Dosya kurulumu **var olan yerel dosyaların üzerine yazmaz**.
- İstemci repo'dan otomatik güncellenmez; `bootstrap.sh` ile bilinçli güncellenir.

## Yeni bilgisayarda
```sh
gh auth login
gh repo clone KaanAlper/kaan-dots ~/kaan-dots
~/kaan-dots/bootstrap.sh
dotsync boot        # eksikler penceresi
```

## Komutlar
`dotsync status [--sync]` · `dotsync apply ID... [--decline ID...]` · `dotsync decline ID...` · `dotsync reset` · `dotsync sync` · `dotsync boot`

## Öğe eklemek
`items/<ad>/` altına dosyaları koy, `manifest.json`'a öğeyi ekle (`kind`: `files` | `pkgs` | `check`), test:
`python -m pytest tests`
