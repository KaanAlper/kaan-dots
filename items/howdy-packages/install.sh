#!/bin/bash
# Howdy paketleri (Arch/CachyOS): python-dlib (CUDA'sız, CPU) + howdy-git.
# Neden elle derleme: AUR'daki python-dlib varsayılan olarak CUDA'lı derlenir; sabitlenmiş CUDA
# gcc 16 ile kırılır ve paru PKGBUILD'i her seferinde sıfırlar. Yüz tanıma için GPU gerekmez.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

if ! pacman -Q python-dlib >/dev/null 2>&1; then
    cp "$HERE/python-dlib.PKGBUILD" "$BUILD/PKGBUILD"
    ( cd "$BUILD" && makepkg -sfC --noconfirm )
    sudo pacman -U --noconfirm "$BUILD"/python-dlib-*.pkg.tar.zst
fi
if ! pacman -Q howdy-git >/dev/null 2>&1; then
    paru -S --needed howdy-git
fi
echo "Howdy paketleri hazır."
