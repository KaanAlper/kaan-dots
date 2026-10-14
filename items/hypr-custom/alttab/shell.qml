// Alt+Tab window switcher for Hyprland (Quickshell), ported from Logical Lunge's switcher.
// Hold Alt and press Tab to move forward (Shift+Tab back, arrow keys, Enter; Esc cancels; click or hover with the mouse);
// releasing Alt switches to the selected window. Lists the windows of every workspace in a fixed order (workspace,
// then left to right inside it); it opens on the previously used window, with live previews. Runs as its own Quickshell instance, so dots updates don't overwrite it.
// Started from custom/execs.lua (qs -p ~/.config/hypr/custom/alttab/shell.qml); keys are bound in custom/keybinds.lua.
//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    property bool open: false
    property bool reverseOpen: false
    property var cards: []          // [{ address, title, cls, ws, wsName, toplevel, icon }]
    property int sel: 0
    property bool mouseArmed: false // don't select the card under the cursor just because the switcher opened there
    property string pendingStep: "" // a step ("next"/"prev") that arrived before the window list
    // Alt released before the window list arrived (a quick Alt+Tab tap): switch as soon as it does,
    // so repeated quick taps flip between the two most recent windows
    property bool pendingCommit: false

    // Material colours that ii generates from the wallpaper (purple defaults if the file is missing)
    property var c: ({
        surface: "#141218", card: "#221f28", border: "#3a3842", selFill: "#4f378b",
        selBorder: "#d0bcff", text: "#e6e0e9", sub: "#cac4d0", scrim: "#000000"
    })
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const m = JSON.parse(text());
                root.c = {
                    surface: m.surface_container_low ?? m.background ?? root.c.surface,
                    card: m.surface_container_high ?? root.c.card,
                    border: m.outline_variant ?? root.c.border,
                    selFill: m.primary_container ?? root.c.selFill,
                    selBorder: m.primary ?? root.c.selBorder,
                    text: m.on_surface ?? root.c.text,
                    sub: m.on_surface_variant ?? root.c.sub,
                    scrim: "#000000"
                };
            } catch (e) { console.warn("alttab: could not read colors.json: " + e); }
        }
    }

    // ---- window list: hyprctl clients (focusHistoryID 0 = the focused window) ----
    Process {
        id: clients
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: root.build(text)
        }
    }

    function iconFor(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable");
        const lc = cls.toLowerCase();
        const apps = DesktopEntries.applications.values;
        const e = apps.find(a => (a.startupClass ?? "").toLowerCase() === lc)
            ?? apps.find(a => (a.id ?? "").toLowerCase() === lc || (a.id ?? "").toLowerCase().endsWith("." + lc))
            ?? apps.find(a => (a.name ?? "").toLowerCase() === lc);
        const p = Quickshell.iconPath(e?.icon ?? lc, true);
        return p !== "" ? p : Quickshell.iconPath("application-x-executable");
    }

    function toplevelFor(address) {
        return ToplevelManager.toplevels.values.find(t => `0x${t.HyprlandToplevel?.address}` === address) ?? null;
    }

    function build(json) {
        let list = [];
        try { list = JSON.parse(json); } catch (e) { console.warn("alttab: could not parse hyprctl output"); }
        // Fixed order: by workspace, then by position inside it (left to right, then top to bottom), so the cards
        // don't reshuffle with every switch. Special workspaces (negative ids) go last.
        const wsKey = id => id < 0 ? 100000 - id : id;
        list = list.filter(w => w.mapped && !w.hidden && w.workspace && w.workspace.id !== -1 && w.title !== undefined)
                   .sort((a, b) => wsKey(a.workspace.id) - wsKey(b.workspace.id) || a.at[0] - b.at[0] || a.at[1] - b.at[1]);
        const current = list.findIndex(w => w.focusHistoryID === 0);
        const previous = list.findIndex(w => w.focusHistoryID === 1); // the window used before the focused one
        const active = Hyprland.focusedMonitor?.activeWorkspace?.id;
        root.cards = list.map(w => ({
            address: w.address,
            title: w.title || w.class,
            cls: w.class,
            ws: w.workspace.id,
            wsName: w.workspace.name,
            otherWs: w.workspace.id !== active,
            toplevel: root.toplevelFor(w.address),
            icon: root.iconFor(w.class)
        }));
        if (root.cards.length === 0) { root.close(); return; }
        // Alt+Tab starts on the previously used window (a quick tap flips between the last two); more Tabs walk the
        // fixed order from there. Shift+Tab starts on the card before the focused window.
        const n = root.cards.length;
        const from = current >= 0 ? current : 0;
        if (n <= 1) root.sel = 0;
        else if (!root.reverseOpen && previous >= 0) root.sel = previous;
        else root.sel = ((from + (root.reverseOpen ? -1 : 1)) % n + n) % n;
        if (root.pendingStep !== "") { const s = root.pendingStep; root.pendingStep = ""; root.step(s === "next" ? 1 : -1); }
        if (root.pendingCommit) root.commit();
    }

    // ---- open / step / commit ----
    function openSwitcher(reverse) {
        root.reverseOpen = reverse;
        root.cards = [];
        root.mouseArmed = false;
        root.pendingCommit = false;
        root.open = true;
        clients.running = true;
    }

    function step(d) {
        if (!root.open) { root.openSwitcher(d < 0); return; }
        if (root.cards.length === 0) { root.pendingStep = d > 0 ? "next" : "prev"; return; }
        const n = root.cards.length;
        root.sel = ((root.sel + d) % n + n) % n;
    }

    function stepRow(dy, perRow) {
        const t = root.sel + dy * perRow;
        if (t >= 0 && t < root.cards.length) root.sel = t;
    }

    function commit() {
        if (!root.open) return;
        if (root.cards.length === 0) { root.pendingCommit = true; return; } // the list is still loading
        const card = root.cards[root.sel];
        root.close();
        if (!card) return;
        // Focus only after the layer is gone: when it unmaps, Hyprland gives keyboard focus back to the window
        // that had it before the switcher, and if that lands after our focus the MRU order flips around
        focusLater.address = card.address;
        focusLater.restart();
    }

    Timer {
        id: focusLater
        property string address: ""
        interval: 60
        onTriggered: Hyprland.dispatch(`hl.dsp.focus({window = "address:${address}"})`)
    }

    function close() {
        root.open = false;
        root.pendingStep = "";
        root.pendingCommit = false;
        root.cards = [];
    }

    // Testing / scripting: qs ipc -p <this file> call alttab next|prev|commit|cancel|state
    IpcHandler {
        target: "alttab"
        function next(): void { root.step(1) }
        function prev(): void { root.step(-1) }
        function commit(): void { root.commit() }
        function cancel(): void { root.close() }
        function state(): string {
            return JSON.stringify({ open: root.open, sel: root.sel, cards: root.cards.map(c => c.cls + "@" + c.wsName) })
        }
    }

    GlobalShortcut { appid: "alttab"; name: "next"; description: "Alt+Tab: next window"; onPressed: root.step(1) }
    GlobalShortcut { appid: "alttab"; name: "prev"; description: "Alt+Shift+Tab: previous window"; onPressed: root.step(-1) }
    // Alt released: the release event of a transparent bind on the Alt key itself (caught even if Alt is released
    // before the layer gets keyboard focus; Alt still reaches applications)
    GlobalShortcut { appid: "alttab"; name: "alt"; description: "Alt key (release switches to the selection)"; onReleased: root.commit() }

    // ---- view ----
    PanelWindow {
        id: panel
        visible: root.open
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "alttab"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        readonly property int cw: 232
        readonly property int ch: 170
        readonly property int gap: 12
        readonly property int pad: 20
        readonly property int thW: 212
        readonly property int thH: 118
        readonly property int perRow: Math.max(1, Math.min(root.cards.length, Math.floor((width * 0.9 - 2 * pad + gap) / (cw + gap))))

        // a click outside cancels
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: box
            anchors.centerIn: parent
            visible: root.cards.length > 0
            width: panel.perRow * (panel.cw + panel.gap) - panel.gap + 2 * panel.pad
            height: grid.implicitHeight + 2 * panel.pad
            radius: 24
            color: root.c.surface
            border.color: root.c.border
            border.width: 1
            opacity: visible ? 1 : 0
            scale: visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent } // clicks inside the box don't cancel

            focus: root.open
            Keys.onPressed: (e) => {
                switch (e.key) {
                case Qt.Key_Right: root.step(1); break;
                case Qt.Key_Left: root.step(-1); break;
                case Qt.Key_Down: root.stepRow(1, panel.perRow); break;
                case Qt.Key_Up: root.stepRow(-1, panel.perRow); break;
                case Qt.Key_Tab: root.step(1); break;          // in case the bind reaches the layer
                case Qt.Key_Backtab: root.step(-1); break;
                case Qt.Key_Return: case Qt.Key_Enter: root.commit(); break;
                case Qt.Key_Escape: root.close(); break;
                default: return;
                }
                e.accepted = true;
            }
            Keys.onReleased: (e) => {
                if (e.key === Qt.Key_Alt || e.key === Qt.Key_AltGr) { root.commit(); e.accepted = true; }
            }

            Grid {
                id: grid
                anchors.centerIn: parent
                columns: panel.perRow
                spacing: panel.gap

                Repeater {
                    model: root.cards
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.sel
                        width: panel.cw
                        height: panel.ch
                        radius: 16
                        color: selected ? root.c.selFill : root.c.card
                        border.color: selected ? root.c.selBorder : "transparent"
                        border.width: selected ? 2 : 0
                        Behavior on color { ColorAnimation { duration: 110 } }

                        Item {
                            id: thumbArea
                            x: (panel.cw - panel.thW) / 2
                            y: 12
                            width: panel.thW
                            height: panel.thH

                            ScreencopyView {
                                id: shot
                                anchors.centerIn: parent
                                // stop capturing when the window closes while the switcher is open: capturing a dead Wayland
                                // object crashes Quickshell (the crash reported on upstream PR #3595)
                                readonly property bool alive: card.modelData.toplevel !== null
                                    && ToplevelManager.toplevels.values.indexOf(card.modelData.toplevel) >= 0
                                captureSource: root.open && alive ? card.modelData.toplevel : null
                                live: true
                                visible: alive && hasContent
                                // keep the aspect ratio
                                readonly property real k: sourceSize.width > 0 && sourceSize.height > 0
                                    ? Math.min(panel.thW / sourceSize.width, panel.thH / sourceSize.height) : 1
                                width: sourceSize.width > 0 ? sourceSize.width * k : panel.thW
                                height: sourceSize.height > 0 ? sourceSize.height * k : panel.thH
                            }
                            Image { // a large icon when there is no preview
                                anchors.centerIn: parent
                                visible: !shot.visible
                                source: card.modelData.icon
                                sourceSize: Qt.size(56, 56)
                                width: 56; height: 56
                            }
                        }

                        RowLayout {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                            spacing: 6
                            Image {
                                source: card.modelData.icon
                                sourceSize: Qt.size(22, 22)
                                Layout.preferredWidth: 22; Layout.preferredHeight: 22
                            }
                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                color: root.c.text
                                elide: Text.ElideRight
                                font.pixelSize: 13
                            }
                            Rectangle { // badge for a window on another workspace
                                visible: card.modelData.otherWs
                                radius: 8
                                color: root.c.border
                                implicitWidth: wsText.implicitWidth + 10
                                implicitHeight: 18
                                Text {
                                    id: wsText
                                    anchors.centerIn: parent
                                    text: card.modelData.wsName
                                    color: root.c.sub
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: { if (root.mouseArmed) root.sel = card.index; else root.mouseArmed = true; }
                            onClicked: { root.sel = card.index; root.commit(); }
                        }
                    }
                }
            }
        }
    }
}
