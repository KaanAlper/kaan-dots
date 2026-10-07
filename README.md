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

## Kurulum (tek satır)

Repo private olduğu için GitHub girişi gerekir (`gh auth login`, bir kez). Sonra tek satır:

```sh
gh api repos/KaanAlper/kaan-dots/contents/install.sh -H "Accept: application/vnd.github.raw" | bash
```

Bu komut `~/kaan-dots`'u klonlar (varsa günceller) ve kurulum penceresini açar:

1. **Kuruluma hoş geldin**: installer'ın (`dotsync`) kendisi kurulur. *Yalnızca ilk kurulumda.*
2. **Neleri kuralım?**: sistemde olmayanlar onay kutularıyla listelenir; işaretlediklerin kurulur.
3. İlerleme ve sonuç ekranı.

Sonraki oturum açılışlarında 1. adım yoktur: yalnızca sistemde bir şey eksikse 2. ekran açılır, eksik yoksa pencere hiç görünmez.
Pencere "İndir" demeden hiçbir ayar veya paket kurmaz. `quickshell` yoksa metin moduna düşer.

Gereksinimler: `git`, `gh` (GitHub CLI), `python3`; arayüz için `quickshell` (`qs`).

<details><summary>Adım adım (aynı şey)</summary>

```sh
gh auth login
gh repo clone KaanAlper/kaan-dots ~/kaan-dots
~/kaan-dots/bootstrap.sh
dotsync boot        # eksikler penceresi
```
</details>

Güncelleme: aynı tek satırı tekrar çalıştırmak yeterli (repo'yu çeker, istemciyi yeniler).

## Komutlar
`dotsync status [--sync]` · `dotsync apply ID... [--decline ID...]` · `dotsync decline ID...` · `dotsync reset` · `dotsync sync` · `dotsync boot` (açılış denetimi) · `dotsync setup` (kurulum ekranını elle aç, reddedilenler dahil)

## Öğe eklemek
`items/<ad>/` altına dosyaları koy, `manifest.json`'a öğeyi ekle (`kind`: `files` | `pkgs` | `check`), test:
`python -m pytest tests`
