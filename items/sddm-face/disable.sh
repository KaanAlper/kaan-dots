#!/bin/bash
# enable.sh'ın yaptıklarını geri alır. Root ile: sudo bash disable.sh
set -euo pipefail
PAM="${SDDM_PAM_FILE:-/etc/pam.d/sddm}"
BACKUP="$PAM.bak-howdy"
CONF="${SDDM_THEME_DIR:-/usr/share/sddm/themes/Sugar-Candy}/theme.conf.user"

[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0" >&2; exit 1; }

if [ -f "$BACKUP" ]; then
    cp -a "$BACKUP" "$PAM"
    echo "PAM: yedekten geri yüklendi"
else
    sed -i '/pam_howdy\.so/d' "$PAM"
    echo "PAM: pam_howdy satırı silindi (yedek yoktu)"
fi
if [ -f "$CONF" ]; then
    sed -i '/^AllowEmptyPassword/d' "$CONF"
    echo "Tema: boş parola izni kaldırıldı"
fi
echo "Tamam."
