#!/bin/bash
# kaan-dots tek satır kurulum (private repo: gh girişi gerekir):
#   gh api repos/KaanAlper/kaan-dots/contents/install.sh -H "Accept: application/vnd.github.raw" | bash
#
# Akış: ~/kaan-dots'u klonlar (varsa günceller) -> kurulum penceresi açılır:
#   1) "Kuruluma hoş geldin": installer (dotsync) kurulur  [yalnızca ilk kurulumda]
#   2) "Neleri kuralım?": sistemde olmayanlar onay kutularıyla listelenir
# Sonraki açılışlarda yalnızca 2. ekran, o da yalnızca eksik varsa gelir.
# Sistem dosyalarına dokunmaz; "İndir" demeden hiçbir ayar/paket kurulmaz.
set -euo pipefail

REPO="${KAAN_DOTS_REPO:-KaanAlper/kaan-dots}"
DEST="${KAAN_DOTS_DIR:-$HOME/kaan-dots}"

command -v git >/dev/null || { echo "git gerekli: sudo pacman -S git" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh gerekli: sudo pacman -S github-cli" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 gerekli" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "GitHub girişi yok: önce 'gh auth login' çalıştır." >&2; exit 1; }

if [ -d "$DEST/.git" ]; then
    echo "→ $DEST güncelleniyor"
    git -C "$DEST" -c credential.helper= -c "credential.helper=!gh auth git-credential" pull --ff-only
else
    echo "→ $REPO klonlanıyor: $DEST"
    gh repo clone "$REPO" "$DEST"
fi

export PATH="$HOME/.local/bin:$PATH"

# Arayüz: quickshell + Wayland oturumu varsa pencere, yoksa metin modu.
if command -v qs >/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ] && [ -z "${DOTSYNC_NO_UI:-}" ]; then
    echo "→ kurulum penceresi açılıyor"
    DOTSYNC_BIN="$DEST/dotsync/dotsync.py" DOTSYNC_BOOTSTRAP="$DEST/bootstrap.sh" \
        qs -p "$DEST/dotsync/ui" || true
fi

# Pencere açılamadıysa ya da kurulum tamamlanmadan kapatıldıysa: metin modunda tamamla.
if ! command -v dotsync >/dev/null; then
    echo "→ installer kuruluyor (metin modu)"
    "$DEST/bootstrap.sh"
    dotsync status | python3 -c "import json,sys; d=json.load(sys.stdin); print('Eksikler:', ', '.join(d['pending']) or 'yok')"
    echo "İndirmek için: dotsync apply <id>...   (liste: dotsync status)"
fi
echo "Tamam. Sonradan eksik kontrolü: dotsync setup"
