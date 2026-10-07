#!/bin/bash
# Bu repo'dan dotsync istemcisini kurar (bir kez). Yeni bilgisayarda:
#   gh auth login && gh repo clone KaanAlper/kaan-dots ~/kaan-dots && ~/kaan-dots/bootstrap.sh
# Ardından eksikleri görmek için: dotsync boot
# İstemci repo'dan OTOMATİK güncellenmez (güvenlik): güncellemek için bu betiği tekrar çalıştır.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/dotsync"
CLIENT="$DATA/client"
BIN="$HOME/.local/bin"

command -v gh >/dev/null || { echo "gh gerekli: sudo pacman -S github-cli" >&2; exit 1; }
command -v qs >/dev/null || echo "uyarı: quickshell (qs) yok; arayüz açılmaz, 'dotsync status' çalışır." >&2

mkdir -p "$CLIENT" "$BIN"
rm -rf "$CLIENT/ui"
cp -r "$HERE/dotsync/dotsync.py" "$HERE/dotsync/ui" "$CLIENT/"
chmod +x "$CLIENT/dotsync.py"
ln -sf "$CLIENT/dotsync.py" "$BIN/dotsync"

# Repo önbelleği: yoksa GitHub'dan klonla (origin adresinden sahip/ad çıkarılır).
if [ ! -d "$DATA/repo/.git" ]; then
    SLUG="$(git -C "$HERE" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
    mkdir -p "$DATA"
    gh repo clone "$SLUG" "$DATA/repo" -- --depth 1
fi
echo "dotsync kuruldu: $BIN/dotsync   (PATH'te değilse: export PATH=\$HOME/.local/bin:\$PATH)"
echo "Şimdi: dotsync status"
