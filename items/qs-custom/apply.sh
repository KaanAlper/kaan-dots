#!/usr/bin/env bash
# Re-apply the custom bar widgets after an end-4 / illogical-impulse dots update.
#
# Widgets restored here:
#   - AudioMonoToggle    — mono/stereo output downmix toggle (uses scripts/audio-mono-toggle.sh)
#   - AudioOutputSwitcher — pick the default output device from a hover popup (pure QML)
#
# The dots updater overwrites tracked files (notably BarContent.qml, which IS in
# ~/.config/illogical-impulse/installed_listfile) and may delete untracked files,
# so the customizations can be lost on update. Run this once after every dots update:
#
#     ~/.config/quickshell-custom/apply.sh
#
# It is idempotent: safe to run any number of times.
set -u

CUSTOM_DIR="$HOME/.config/quickshell-custom"
II="$HOME/.config/quickshell/ii"
BAR="$II/modules/ii/bar"

if [ ! -d "$II" ]; then
    echo "✗ $II yok — quickshell ii config bulunamadı." >&2
    exit 1
fi

# 1) Restore the toggle script and the bar widgets into the dots tree.
mkdir -p "$II/scripts" "$BAR"
cp "$CUSTOM_DIR/audio-mono-toggle.sh" "$II/scripts/audio-mono-toggle.sh"
chmod +x "$II/scripts/audio-mono-toggle.sh"
cp "$CUSTOM_DIR/AudioMonoToggle.qml" "$BAR/AudioMonoToggle.qml"
cp "$CUSTOM_DIR/AudioOutputSwitcher.qml" "$BAR/AudioOutputSwitcher.qml"

# 2) Idempotently insert each widget into BarContent.qml (right section, before SysTray).
#    Order ends up: ... AudioMonoToggle, AudioOutputSwitcher, SysTray ...
python3 - "$BAR/BarContent.qml" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    src = f.read()

# Each widget: name used for the "already patched?" guard, and the block to insert.
widgets = [
    ("AudioMonoToggle",
     "            AudioMonoToggle {\n"
     "                visible: root.useShortenedForm < 2\n"
     "                Layout.alignment: Qt.AlignVCenter\n"
     "                Layout.leftMargin: 4\n"
     "                Layout.rightMargin: 4\n"
     "            }\n"
     "\n"),
    ("AudioOutputSwitcher",
     "            AudioOutputSwitcher {\n"
     "                visible: root.useShortenedForm < 2\n"
     "                Layout.alignment: Qt.AlignVCenter\n"
     "                Layout.leftMargin: 4\n"
     "                Layout.rightMargin: 4\n"
     "            }\n"
     "\n"),
]

inserted, skipped, missing = [], [], False
for name, block in widgets:
    if name in src:
        skipped.append(name)
        continue
    lines = src.splitlines(keepends=True)
    for i, ln in enumerate(lines):
        if ln.strip() == "SysTray {":
            lines.insert(i, block)
            src = "".join(lines)
            inserted.append(name)
            break
    else:
        sys.stderr.write(
            f"  UYARI: BarContent.qml icinde 'SysTray {{' bulunamadi. "
            f"{name} blogunu sag bolume elle ekleyin.\n"
        )
        missing = True

if inserted:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("  BarContent.qml: eklendi -> " + ", ".join(inserted))
if skipped:
    print("  BarContent.qml: zaten yamalı -> " + ", ".join(skipped))

sys.exit(1 if missing else 0)
PY
rc=$?

# 2b) Fix an upstream half-finished rename in the pinned dots snapshot:
#     Config.qml declares  notifications.monitor
#     but NotificationPopup.qml / InterfaceConfig.qml read
#     notifications.forceMonitor  -> "TypeError: Cannot read property 'enable'
#     of undefined", and the notification popup's screen selection breaks.
#     Config.qml IS in installed_listfile, so a dots update reverts this.
python3 - "$II/modules/common/Config.qml" "$II" <<'PY_CFG'
import sys, pathlib
cfg = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
if not cfg.exists():
    print("  UYARI: Config.qml yok, forceMonitor yaması atlandı.")
    sys.exit(0)
src = cfg.read_text(encoding="utf-8")
old = "property JsonObject monitor: JsonObject {"
new = "property JsonObject forceMonitor: JsonObject {"
uses_force = any(
    "forceMonitor" in p.read_text(encoding="utf-8", errors="ignore")
    for p in root.rglob("*.qml") if p != cfg
)
if not uses_force:
    print("  Config.qml: forceMonitor okuyan dosya yok -> yama gereksiz (upstream düzeltmiş).")
elif new in src:
    print("  Config.qml: zaten yamalı -> forceMonitor")
elif src.count(old) == 1:
    cfg.write_text(src.replace(old, new), encoding="utf-8")
    print("  Config.qml: notifications.monitor -> forceMonitor")
elif src.count(old) == 0:
    print("  Config.qml: 'JsonObject monitor' yok -> şema değişmiş, elle bakın.")
else:
    sys.stderr.write("  UYARI: 'JsonObject monitor' birden fazla geçiyor, "
                     "otomatik yama güvenli değil. Elle düzeltin.\n")
PY_CFG

# 2c) Howdy face unlock on the lock screen (pam config + LockContext.qml patch).
#     LockContext.qml is in installed_listfile, so a dots update reverts it.
LOCK="$II/modules/common/panels/lock"
if [ -d "$LOCK" ]; then
    mkdir -p "$LOCK/pam"
    cp "$CUSTOM_DIR/pam/howdy.conf" "$LOCK/pam/howdy.conf"
    python3 "$CUSTOM_DIR/patch-lock-howdy.py" "$II" || rc=1
else
    echo "  UYARI: $LOCK yok, howdy yaması atlandı."
fi

# 3) Reload Quickshell.
touch "$II/shell.qml"

if [ "$rc" -eq 0 ]; then
    echo "✓ Custom bar widget'ları uygulandı, bar yeniden yüklendi."
else
    echo "✗ BarContent yaması kısmen başarısız — yukarıdaki uyarıya bakın."
fi
exit "$rc"
