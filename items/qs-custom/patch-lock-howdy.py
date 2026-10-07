#!/usr/bin/env python3
"""Idempotent: Howdy face-unlock + Windows Hello-style indicator on the ii lock screen.

Usage: patch-lock-howdy.py <ii-dir>      (e.g. ~/.config/quickshell/ii)

Patches two dots files (both are in installed_listfile, so a dots update reverts them):
  * modules/common/panels/lock/LockContext.qml  - facePam (PAM howdy), faceState machine
  * modules/ii/lock/LockSurface.qml             - face icon + status text in the toolbar

faceState: "idle" | "scanning" | "retrying" | "failed" | "success"
Uyanınca (hypridle -> quickshell:lockFocus -> shouldReFocus) tarama otomatik yeniden başlar;
tanınamazsa faceMaxAttempts kez otomatik dener, sonra simgeye tıklanarak yeniden denenir.
Mirrors the stock fprintd flow: facePam starts from tryFingerUnlock() when the screen
locks, so the camera scans as soon as the lid opens. Password typing keeps working
(pam_howdy is `sufficient`). Face unlock is only attempted when pam_howdy.so exists.
"""
import pathlib
import sys

MARK = "faceState"


def patch(path, edits, tail=None):
    src = path.read_text(encoding="utf-8")
    if MARK in src:
        print(f"  {path.name}: zaten yamalı -> howdy")
        return True
    for old, new in edits:
        if src.count(old) != 1:
            sys.stderr.write(
                f"  UYARI: {path.name} beklenen kalıbı içermiyor ({old.strip()[:50]!r}); "
                "howdy yaması atlandı, elle bakın.\n"
            )
            return False
        src = src.replace(old, new)
    if tail:
        idx = src.rstrip().rfind("}")
        src = src[:idx].rstrip("\n") + "\n" + tail
    path.write_text(src, encoding="utf-8")
    print(f"  {path.name}: howdy yüz tanıma eklendi")
    return True


CONTEXT_TAIL = '''
    function startFaceScan() {
        if (!root.faceAvailable || !GlobalStates.screenLocked || facePam.active) return;
        root.faceAborting = false;
        root.faceState = root.faceAttempts > 0 ? "retrying" : "scanning";
        facePam.start();
    }

    function stopFaceScan() {
        faceRetryTimer.stop();
        faceWakeTimer.stop();
        if (facePam.active) {
            root.faceAborting = true;
            facePam.abort();
        }
    }

    // Uyanış: hypridle after_sleep_cmd -> quickshell:lockFocus -> shouldReFocus. Uyku öncesi başlayan
    // tarama çoktan bitmiştir; USB kamera uyanana kadar kısa bekleyip taramayı yeniden başlat.
    Connections {
        target: root
        function onShouldReFocus() {
            if (root.faceAvailable && GlobalStates.screenLocked) faceWakeTimer.restart();
        }
    }
    Timer {
        id: faceWakeTimer
        interval: 1200
        onTriggered: {
            if (!facePam.active) {
                root.faceAttempts = 0;
                root.startFaceScan();
            }
        }
    }
    Timer {
        id: faceRetryTimer
        interval: 700
        onTriggered: root.startFaceScan()
    }

    Process {
        id: faceCheckProc
        running: true
        command: ["bash", "-c", "test -e /usr/lib/security/pam_howdy.so || test -e /lib/security/pam_howdy.so"]
        onExited: (exitCode, exitStatus) => {
            root.faceAvailable = (exitCode === 0);
        }
    }

    PamContext {
        id: facePam

        configDirectory: "pam"
        config: "howdy.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.faceState = "success";
                root.unlocked(root.targetAction);
                root.stopFingerPam();
                return;
            }
            if (root.faceAborting) {            // bilinçli iptal (kilit açıldı / sıfırlandı)
                root.faceAborting = false;
                root.faceState = "idle";
                return;
            }
            root.faceAttempts += 1;
            if (root.faceAttempts < root.faceMaxAttempts && GlobalStates.screenLocked) {
                root.faceState = "retrying";
                faceRetryTimer.start();
            } else {
                root.faceState = "failed";      // simgeye tıklayınca yeniden dener
            }
        }
    }
}
'''

CONTEXT_EDITS = [
    ("    property bool fingerprintsConfigured: false\n",
     "    property bool fingerprintsConfigured: false\n"
     "    property bool faceAvailable: false\n"
     "    property string faceState: \"idle\" // idle | scanning | retrying | failed | success\n"
     "    property int faceAttempts: 0\n"
     "    readonly property int faceMaxAttempts: 3\n"
     "    property bool faceAborting: false\n"),
    ("    function tryFingerUnlock() {\n",
     "    function tryFingerUnlock() {\n"
     "        root.faceAttempts = 0;\n"
     "        root.startFaceScan();\n"),
    ("    function stopFingerPam() {\n",
     "    function stopFingerPam() {\n"
     "        root.stopFaceScan();\n"),
    ("    function reset() {\n",
     "    function reset() {\n"
     "        root.faceState = \"idle\";\n"),
]

SURFACE_FACE = '''        // Face (Howdy) - Windows Hello style
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.faceAvailable
            visible: active

            sourceComponent: MouseArea {
                id: faceArea
                implicitWidth: faceIcon.implicitWidth
                implicitHeight: faceIcon.implicitHeight
                cursorShape: Qt.PointingHandCursor
                onClicked: root.context.tryFingerUnlock()

                property real pulse: 1
                SequentialAnimation on pulse {
                    running: root.context.faceState === "scanning" || root.context.faceState === "retrying"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 750; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) faceArea.pulse = 1
                }

                MaterialSymbol {
                    id: faceIcon
                    anchors.centerIn: parent
                    fill: root.context.faceState === "success" ? 1 : 0
                    iconSize: Appearance.font.pixelSize.hugeass
                    opacity: (root.context.faceState === "scanning" || root.context.faceState === "retrying") ? faceArea.pulse : 1
                    text: {
                        switch (root.context.faceState) {
                        case "success": return "check_circle";
                        case "failed": return "face_retouching_off";
                        default: return "face";
                        }
                    }
                    color: {
                        switch (root.context.faceState) {
                        case "success": return Appearance.colors.colPrimary;
                        case "failed": return Appearance.colors.colError;
                        default: return Appearance.colors.colOnSurfaceVariant;
                        }
                    }
                }
            }
        }

'''

SURFACE_OLD_PLACEHOLDER = (
    '            placeholderText: GlobalStates.screenUnlockFailed ? '
    'Translation.tr("Incorrect password") : Translation.tr("Enter password")\n'
)
SURFACE_NEW_PLACEHOLDER = (
    '            placeholderText: {\n'
    '                if (GlobalStates.screenUnlockFailed) return Translation.tr("Incorrect password");\n'
    '                if (root.context.faceState === "scanning") return "Yüz taranıyor…";\n'
    '                if (root.context.faceState === "retrying") return "Tanınamadı, biraz yaklaş · tekrar deneniyor (" + (root.context.faceAttempts + 1) + "/" + root.context.faceMaxAttempts + ")";\n'
    '                if (root.context.faceState === "failed") return "Yüz tanınamadı · simgeye tıkla ya da şifre gir";\n'
    '                return Translation.tr("Enter password");\n'
    '            }\n'
)

SURFACE_EDITS = [
    ("        // Fingerprint\n        Loader {\n",
     SURFACE_FACE + "        // Fingerprint\n        Loader {\n"),
    (SURFACE_OLD_PLACEHOLDER, SURFACE_NEW_PLACEHOLDER),
]


def main():
    ii = pathlib.Path(sys.argv[1])
    ctx = ii / "modules/common/panels/lock/LockContext.qml"
    surf = ii / "modules/ii/lock/LockSurface.qml"
    ok = patch(ctx, CONTEXT_EDITS, CONTEXT_TAIL)
    ok = patch(surf, SURFACE_EDITS) and ok
    sys.exit(0 if ok else 1)


main()
