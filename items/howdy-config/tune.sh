#!/bin/bash
# Howdy algılama ayarları (root ile): sudo bash tune.sh
#   dark_threshold 60 -> 90 : Howdy her karede "tam siyah piksel %"sine bakar (CLAHE sonrası) ve eşiği
#       aşan kareyi TANIMA AŞAMASINA GEÇMEDEN atar. IR ışık uzaklıkla zayıfladığı için normal mesafede
#       bile %63-75 çıkabiliyor; 60 eşiğinde compare.py "All frames were too dark" (exit 13) verir.
#   max_height     320 -> 360: IR kamera 640x360; kareyi küçültmeden işle (yüz küçüldükçe tespit zorlaşır).
# Idempotent: tekrar çalıştırmak güvenli. Değerleri değiştirmek için ortam değişkeni: DARK=85 sudo -E bash tune.sh
set -euo pipefail

CFG=/etc/howdy/config.ini
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0" >&2; exit 1; }
[ -f "$CFG" ] || { echo "$CFG yok; howdy kurulu mu?" >&2; exit 1; }

set_cfg() {
    local key="$1" value="$2"
    if grep -qE "^${key}[[:space:]]*=" "$CFG"; then
        sed -i -E "s|^(${key}[[:space:]]*=).*|\1 ${value}|" "$CFG"
    else
        echo "uyarı: $key config'de yok, atlandı" >&2
    fi
}

set_cfg dark_threshold "${DARK:-90}"
set_cfg max_height "${MAXH:-360}"
[ -n "${CERT:-}" ] && set_cfg certainty "$CERT"

grep -nE "^(dark_threshold|max_height|certainty|timeout)\b" "$CFG"
echo "Tamam. Deneme: cd /usr/lib/howdy && python compare.py \$USER; echo exit=\$?   (0 = tanıdı)"
