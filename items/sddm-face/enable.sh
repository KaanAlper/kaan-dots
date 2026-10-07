#!/bin/bash
# SDDM giriş ekranına yüz tanıma EKLER (parola olduğu gibi kalır). Root ile: sudo bash enable.sh
#   1) /etc/pam.d/sddm içine  `auth sufficient pam_howdy.so`  (en üste; yedek alınır)
#   2) Sugar-Candy temasında boş parolaya izin (theme.conf.user; tema güncellemesinde silinmez)
#   3) pamtester varsa PAM zincirini dener
# Geri alma: sudo bash disable.sh
#
# Nasıl kullanılır: SDDM'de kullanıcı adı dolu gelir; parolayı BOŞ bırakıp Enter -> kamera taranır.
# Parola yazarak girmek de olduğu gibi çalışır (yüz tanınırsa parola beklenmeden girer; tanınmazsa
# en çok howdy `timeout` (4 sn) beklenip parola denenir).
# Dikkat: yüzle girişte anahtarlık (gnome-keyring/kwallet) parola girilmediği için KİLİTLİ kalır.
# Dikkat: Howdy canlılık (liveness) denetimi yapmaz; iyi bir IR fotoğrafla kandırılabilir.
set -euo pipefail

PAM="${SDDM_PAM_FILE:-/etc/pam.d/sddm}"
LINE='auth       sufficient  pam_howdy.so'
THEME_DIR="${SDDM_THEME_DIR:-/usr/share/sddm/themes/Sugar-Candy}"
BACKUP="$PAM.bak-howdy"

[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0" >&2; exit 1; }
[ -f "$PAM" ] || { echo "$PAM yok" >&2; exit 1; }
[ -e /usr/lib/security/pam_howdy.so ] || [ -e /lib/security/pam_howdy.so ] || {
    echo "pam_howdy.so yok; önce Howdy paketlerini kur" >&2
    exit 1
}

# 1) PAM (idempotent). İlk orijinali koru.
[ -f "$BACKUP" ] || cp -a "$PAM" "$BACKUP"
if grep -q 'pam_howdy.so' "$PAM"; then
    echo "PAM: pam_howdy zaten ekli"
else
    first_auth=$(grep -n '^auth' "$PAM" | head -1 | cut -d: -f1)
    [ -n "$first_auth" ] || { echo "$PAM içinde 'auth' satırı bulunamadı; elle ekleyin" >&2; exit 1; }
    sed -i "${first_auth}i\\${LINE}" "$PAM"
    echo "PAM: eklendi (yedek: $BACKUP)"
fi

# 2) Tema: boş parola
if [ -d "$THEME_DIR" ]; then
    CONF="$THEME_DIR/theme.conf.user"
    touch "$CONF"
    if grep -q '^AllowEmptyPassword' "$CONF"; then
        sed -i 's|^AllowEmptyPassword.*|AllowEmptyPassword="true"|' "$CONF"
    else
        grep -q '^\[General\]' "$CONF" || echo '[General]' >> "$CONF"
        sed -i '/^\[General\]/a AllowEmptyPassword="true"' "$CONF"
    fi
    echo "Tema: AllowEmptyPassword=true ($CONF)"
else
    echo "uyarı: $THEME_DIR yok (başka tema?); boş parola izni temada elle açılmalı" >&2
fi

# 3) Doğrulama
echo "--- $PAM (ilk satırlar)"
sed -n '1,8p' "$PAM"
if command -v pamtester >/dev/null; then
    echo "--- pamtester: kameraya bak (yüz tanınırsa parola sorulmadan başarılı olur)"
    if pamtester sddm "${SUDO_USER:-$USER}" authenticate; then
        echo "PAM zinciri: BAŞARILI"
    else
        echo "PAM zinciri: başarısız (parola yolu yine çalışır)"
    fi
else
    echo "bilgi: pamtester kurulu değil; denemek için: paru -S pamtester  sonra: sudo pamtester sddm \$USER authenticate"
fi
echo
echo "Geri almak için: sudo bash $(dirname "$0")/disable.sh"
echo "Acil durum: Ctrl+Alt+F3 ile TTY'ye geç, giriş yap ve: sudo cp $BACKUP $PAM"
