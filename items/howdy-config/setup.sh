#!/bin/bash
# Howdy sistem ayarı (root ile): sudo bash setup.sh
#  - pacman'ın cv2'si vtk 9.6 bekliyor; vtk IgnorePkg'de 9.5.2 kalınca `import cv2` kırılıyor.
#    Kendi kütüphanelerini taşıyan headless cv2'yi /usr/lib/howdy içine koyuyoruz
#    (script dizini sys.path[0] olduğundan sistem cv2'sinden önce yüklenir).
#  - IR kamerayı howdy'ye tanıt.
# Tam sistem güncellemesi (vtk dahil) sonrası /usr/lib/howdy/cv2* silinebilir.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "root gerekli: sudo bash $0" >&2
    exit 1
fi
if [ ! -d /usr/lib/howdy ]; then
    echo "howdy kurulu değil (/usr/lib/howdy yok). Önce 'howdy-packages' öğesini kur." >&2
    exit 1
fi

# IR kamerayı bul: GREY (8-bit) formatlı video düğümü, yoksa argüman/varsayılan.
IR_DEV="${1:-}"
if [ -z "$IR_DEV" ] && command -v v4l2-ctl >/dev/null 2>&1; then
    for dev in /dev/video*; do
        if v4l2-ctl -d "$dev" --list-formats 2>/dev/null | grep -q "'GREY'"; then
            IR_DEV="$dev"
            break
        fi
    done
fi
IR_DEV="${IR_DEV:-/dev/video2}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python -m pip download opencv-python-headless --no-deps --only-binary=:all: -d "$TMP"
python -m pip install --no-deps --upgrade --target /usr/lib/howdy "$TMP"/opencv_python_headless-*.whl

sed -i "s|^device_path = .*|device_path = $IR_DEV|" /etc/howdy/config.ini
grep -n '^device_path' /etc/howdy/config.ini

# algılama ayarları (karanlık eşiği vb.)
bash "$(dirname "$0")/tune.sh"

python -c "import sys; sys.path.insert(0,'/usr/lib/howdy'); import cv2; print('cv2 OK', cv2.__version__, cv2.__file__)"
echo "Tamam. Sıradaki: sudo howdy add"
