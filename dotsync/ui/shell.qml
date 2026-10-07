// dotsync arayüzü: logical-lunge kurulum penceresinin görsel dili (M3 koyu, lila vurgu, kayan sayfalar).
// Yalnızca ön yüz: tüm iş `dotsync.py status|apply` çıktısından gelir (JSON / JSON satırları).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // ---- palet (logical-lunge Setup.cs ile aynı)
    readonly property color cBg: "#141218"
    readonly property color cSurface: "#1d1b20"
    readonly property color cSurface2: "#2b2930"
    readonly property color cOutline: "#49454f"
    readonly property color cFg: "#e6e0e9"
    readonly property color cSub: "#cac4d0"
    readonly property color cDim: "#938f99"
    readonly property color cOk: "#a8dab5"
    readonly property color cErr: "#f2b8b5"
    readonly property color cAccent: "#b69df8"

    readonly property string bin: Quickshell.env("DOTSYNC_BIN") || (Quickshell.env("HOME") + "/.local/share/dotsync/client/dotsync.py")

    // Modlar: boot (varsayılan, yalnızca eksik varsa açılır) | setup (her zaman açılır) |
    // bootstrap (ilk kurulum: önce installer'ın kendisi kurulur, sonra setup gibi devam eder)
    readonly property string bootstrapPath: Quickshell.env("DOTSYNC_BOOTSTRAP") || ""
    readonly property bool bootstrapMode: bootstrapPath !== ""
    readonly property bool setupMode: bootstrapMode || Quickshell.env("DOTSYNC_MODE") === "setup"

    // 0 = installer kurulumu (yalnızca ilk kurulumda), 1 = eksikler, 2 = ilerleme, 3 = sonuç
    readonly property int firstPage: bootstrapMode ? 0 : 1
    property int page: firstPage
    property bool nothingToDo: false
    property bool bootFailed: false
    property bool loading: true
    property string loadError: ""
    property int selectedCount: 0
    property bool allOk: true

    ListModel {
        id: bootSteps
        ListElement { sid: "deps"; label: "Gerekli araçlar denetleniyor"; st: "wait" }
        ListElement { sid: "client"; label: "Installer (dotsync) kuruluyor"; st: "wait" }
        ListElement { sid: "cache"; label: "Ayar deposu hazırlanıyor"; st: "wait" }
    }
    ListModel { id: items }      // id,title,desc,kind,terminal,missing,checked,runState,detail
    ListModel { id: resultRows }

    function recount() {
        var n = 0;
        for (var i = 0; i < items.count; i++) if (items.get(i).checked) n++;
        selectedCount = n;
    }

    function load() {
        loading = true;
        loadError = "";
        statusProc.running = true;
    }

    function startApply() {
        var ids = [], declines = [];
        for (var i = 0; i < items.count; i++) {
            var it = items.get(i);
            (it.checked ? ids : declines).push(it.id);
            items.setProperty(i, "runState", it.checked ? "wait" : "skip");
        }
        var args = ["python3", root.bin, "apply"].concat(ids);
        if (declines.length) args = args.concat(["--decline"]).concat(declines);
        applyProc.command = args;
        allOk = true;
        page = 2;
        applyProc.running = true;
    }

    function setRun(id, state, detail) {
        for (var i = 0; i < items.count; i++) {
            if (items.get(i).id === id) {
                items.setProperty(i, "runState", state);
                items.setProperty(i, "detail", detail || "");
                if (state === "fail") allOk = false;
            }
        }
    }

    function onEvent(line) {
        if (!line) return;
        var e;
        try { e = JSON.parse(line); } catch (err) { return; }
        if (e.event === "start") setRun(e.id, "run", "");
        else if (e.event === "done") setRun(e.id, e.ok ? "ok" : "fail", e.detail);
        else if (e.event === "error") { allOk = false; loadError = e.detail; }
        else if (e.event === "finished") page = 3;
    }

    Process {
        id: statusProc
        command: root.setupMode ? ["python3", root.bin, "status", "--include-declined"] : ["python3", root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    items.clear();
                    for (var i = 0; i < data.items.length; i++) {
                        var s = data.items[i];
                        if (s.state !== "missing" || s.declined) continue;
                        items.append({
                            id: s.id, title: s.title, desc: s.desc, kind: s.kind,
                            terminal: s.terminal, missing: s.missing.join(", "),
                            checked: true, runState: "idle", detail: ""
                        });
                    }
                    root.recount();
                    root.loading = false;
                    if (items.count === 0) {
                        if (!root.setupMode) Qt.quit();
                        root.nothingToDo = true;
                        root.page = 3;
                    } else if (root.page === 0 || root.page === 3) {
                        root.page = 1;
                    }
                } catch (err) {
                    root.loadError = "Durum okunamadı";
                    root.loading = false;
                }
            }
        }
        onExited: code => { if (code !== 0 && !root.loadError) { root.loadError = "dotsync çalışmadı (kod " + code + ")"; root.loading = false; } }
    }

    Process {
        id: applyProc
        stdout: SplitParser { onRead: line => root.onEvent(line) }
        onExited: code => { if (root.page === 2) root.page = 3; }
    }

    function bootStep(sid, state) {
        for (var i = 0; i < bootSteps.count; i++)
            if (bootSteps.get(i).sid === sid) bootSteps.setProperty(i, "st", state);
    }

    Process {
        id: bootstrapProc
        command: ["bash", root.bootstrapPath]
        environment: ({ "DOTSYNC_PROGRESS": "1" })
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/^STEP (başla|bitti) (\w+)$/);
                if (m) root.bootStep(m[2], m[1] === "başla" ? "run" : "ok");
            }
        }
        onExited: code => {
            if (code === 0) afterBootstrap.start();
            else root.bootFailed = true;
        }
    }
    Timer { id: afterBootstrap; interval: 700; onTriggered: root.load() }

    Process { id: resetProc; command: ["python3", root.bin, "reset"]; onExited: root.load() }

    Component.onCompleted: { if (bootstrapMode) bootstrapProc.running = true; else load(); }

    FloatingWindow {
        id: win
        title: "Dots Sync"
        color: "transparent"
        implicitWidth: 760
        implicitHeight: 540
        minimumSize: Qt.size(760, 540)
        maximumSize: Qt.size(760, 540)

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 18
            color: root.cBg
            border.color: root.cOutline
            border.width: 1
            clip: true
            focus: true
            Keys.onEscapePressed: Qt.quit()

            // ---- üst şerit: ad, adım noktaları, kapat
            Item {
                id: header
                height: 60
                anchors { left: parent.left; right: parent.right; top: parent.top }

                Rectangle { x: 24; y: 24; width: 12; height: 12; radius: 6; color: root.cAccent }
                Text { x: 46; y: 19; text: "Dots Sync"; color: root.cFg; font.pixelSize: 15; font.weight: Font.DemiBold }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: root.bootstrapMode ? 4 : 3
                        Rectangle {
                            width: (index + root.firstPage) === root.page ? 22 : 8
                            height: 8
                            radius: 4
                            color: (index + root.firstPage) <= root.page ? root.cAccent : root.cOutline
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 220 } }
                        }
                    }
                }

                MouseArea {
                    id: closeArea
                    x: parent.width - 52; y: 14; width: 32; height: 32
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.quit()
                    Rectangle { anchors.fill: parent; radius: 16; color: root.cSurface2; opacity: closeArea.containsMouse ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
                    Text { anchors.centerIn: parent; text: "✕"; color: root.cSub; font.pixelSize: 13 }
                }
            }

            // ---- sayfa şeridi (kayar)
            Item {
                id: viewport
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }
                clip: true

                Row {
                    id: strip
                    x: -root.page * viewport.width
                    height: viewport.height
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    // ============ Sayfa 0: installer kurulumu (yalnızca ilk kurulumda görünür)
                    Item {
                        width: viewport.width; height: viewport.height
                        ColumnLayout {
                            anchors { fill: parent; leftMargin: 32; rightMargin: 32; topMargin: 4; bottomMargin: 24 }
                            spacing: 14
                            Text { text: "Kuruluma hoş geldin"; color: root.cFg; font.pixelSize: 24; font.weight: Font.DemiBold }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: root.bootFailed
                                    ? "Installer kurulamadı. Terminalde ~/kaan-dots/bootstrap.sh çalıştırıp hatayı görebilirsin."
                                    : "Önce installer'ın kendisi kuruluyor. Sonraki açılışlarda bu adım olmaz; yalnızca sistemde eksik olanlar sorulur."
                                color: root.bootFailed ? root.cErr : root.cSub; font.pixelSize: 13
                            }
                            Repeater {
                                model: bootSteps
                                delegate: RowLayout {
                                    Layout.fillWidth: true; Layout.topMargin: 6; spacing: 14
                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: model.st === "ok" ? root.cOk : "transparent"
                                        border.color: model.st === "run" ? root.cAccent : root.cOutline
                                        border.width: model.st === "ok" ? 0 : 2
                                        Text { anchors.centerIn: parent; visible: model.st === "ok"; text: "✓"; color: root.cBg; font.pixelSize: 13; font.weight: Font.Bold }
                                        Rectangle {
                                            visible: model.st === "run"
                                            anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: root.cAccent
                                            SequentialAnimation on opacity {
                                                running: model.st === "run"; loops: Animation.Infinite
                                                NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }
                                    Text { text: model.label; color: model.st === "wait" ? root.cDim : root.cFg; font.pixelSize: 14 }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Rectangle {
                                visible: root.bootFailed
                                Layout.alignment: Qt.AlignRight
                                implicitWidth: failTxt.implicitWidth + 44; implicitHeight: 42; radius: 21
                                color: root.cAccent
                                Text { id: failTxt; anchors.centerIn: parent; text: "Kapat"; color: root.cBg; font.pixelSize: 14; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.quit() }
                            }
                        }
                    }

                    // ============ Sayfa 1: eksikler
                    Item {
                        width: viewport.width; height: viewport.height

                        ColumnLayout {
                            anchors { fill: parent; leftMargin: 32; rightMargin: 32; topMargin: 4; bottomMargin: 24 }
                            spacing: 14

                            Text {
                                text: root.loading ? "Denetleniyor…" : (root.setupMode ? "Neleri kuralım?" : "Yerelde eksik olanlar")
                                color: root.cFg; font.pixelSize: 24; font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.loadError ? root.loadError
                                    : "GitHub'daki ayarlarında olup bu bilgisayarda bulunmayanlar. İndirmek istediklerini işaretle; işaretlemediklerin için bir daha sorulmaz."
                                color: root.loadError ? root.cErr : root.cSub
                                font.pixelSize: 13
                            }

                            ListView {
                                id: list
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10
                                clip: true
                                model: items
                                boundsBehavior: Flickable.StopAtBounds
                                delegate: Rectangle {
                                    width: list.width
                                    height: rowCol.implicitHeight + 28
                                    radius: 14
                                    color: rowArea.containsMouse ? root.cSurface2 : root.cSurface
                                    border.color: model.checked ? Qt.rgba(0.714, 0.616, 0.973, 0.55) : "transparent"
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: rowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { items.setProperty(index, "checked", !model.checked); root.recount(); }
                                    }

                                    Rectangle {
                                        id: box
                                        x: 18; y: 18; width: 22; height: 22; radius: 7
                                        color: model.checked ? root.cAccent : "transparent"
                                        border.color: model.checked ? root.cAccent : root.cDim
                                        border.width: 2
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "✓"; visible: model.checked; color: root.cBg; font.pixelSize: 14; font.weight: Font.Bold }
                                    }

                                    ColumnLayout {
                                        id: rowCol
                                        anchors { left: box.right; leftMargin: 16; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 14 }
                                        spacing: 4
                                        RowLayout {
                                            spacing: 8
                                            Text { text: model.title; color: root.cFg; font.pixelSize: 15; font.weight: Font.Medium }
                                            Rectangle {
                                                visible: model.terminal
                                                radius: 8; color: root.cSurface2
                                                implicitWidth: termLabel.implicitWidth + 14; implicitHeight: 20
                                                Text { id: termLabel; anchors.centerIn: parent; text: "terminalde"; color: root.cSub; font.pixelSize: 11 }
                                            }
                                        }
                                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: model.desc; color: root.cSub; font.pixelSize: 12 }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: "Eksik: " + model.missing
                                            color: root.cDim; font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Text {
                                    text: "Reddedilenleri sıfırla"
                                    color: resetArea.containsMouse ? root.cFg : root.cDim
                                    font.pixelSize: 12
                                    MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: resetProc.running = true }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    id: laterBtn
                                    implicitWidth: laterTxt.implicitWidth + 40; implicitHeight: 42; radius: 21
                                    color: laterArea.containsMouse ? root.cSurface2 : "transparent"
                                    border.color: root.cOutline; border.width: 1
                                    Text { id: laterTxt; anchors.centerIn: parent; text: "Şimdi değil"; color: root.cFg; font.pixelSize: 14 }
                                    MouseArea { id: laterArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.quit() }
                                }
                                Rectangle {
                                    implicitWidth: goTxt.implicitWidth + 44; implicitHeight: 42; radius: 21
                                    enabled: !root.loading && items.count > 0
                                    opacity: enabled ? 1 : 0.4
                                    color: goArea.pressed ? Qt.darker(root.cAccent, 1.15) : root.cAccent
                                    Text {
                                        id: goTxt; anchors.centerIn: parent
                                        text: root.selectedCount > 0 ? "Seçilenleri indir (" + root.selectedCount + ")" : "Hiçbirini indirme"
                                        color: root.cBg; font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                    MouseArea { id: goArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.startApply() }
                                }
                            }
                        }
                    }

                    // ============ Sayfa 2: ilerleme
                    Item {
                        width: viewport.width; height: viewport.height
                        ColumnLayout {
                            anchors { fill: parent; leftMargin: 32; rightMargin: 32; topMargin: 4; bottomMargin: 24 }
                            spacing: 14
                            Text { text: "Kuruluyor"; color: root.cFg; font.pixelSize: 24; font.weight: Font.DemiBold }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: "Terminal gerektirenler ayrı bir pencerede açılır; parolayı orada girersin."
                                color: root.cSub; font.pixelSize: 13
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                spacing: 8; clip: true
                                model: items
                                delegate: Item {
                                    width: ListView.view.width
                                    height: model.runState === "skip" ? 0 : 44
                                    visible: height > 0
                                    Rectangle {
                                        id: dot
                                        x: 6; anchors.verticalCenter: parent.verticalCenter
                                        width: 22; height: 22; radius: 11
                                        color: model.runState === "ok" ? root.cOk
                                             : model.runState === "fail" ? root.cErr
                                             : "transparent"
                                        border.color: model.runState === "run" ? root.cAccent : root.cOutline
                                        border.width: model.runState === "ok" || model.runState === "fail" ? 0 : 2
                                        Text {
                                            anchors.centerIn: parent
                                            visible: model.runState === "ok" || model.runState === "fail"
                                            text: model.runState === "ok" ? "✓" : "!"
                                            color: root.cBg; font.pixelSize: 13; font.weight: Font.Bold
                                        }
                                        Rectangle {
                                            visible: model.runState === "run"
                                            anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: root.cAccent
                                            SequentialAnimation on opacity {
                                                running: model.runState === "run"; loops: Animation.Infinite
                                                NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        anchors { left: dot.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 1
                                        Text { text: model.title; color: model.runState === "wait" ? root.cDim : root.cFg; font.pixelSize: 14 }
                                        Text {
                                            visible: model.detail.length > 0
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: model.detail
                                            color: model.runState === "fail" ? root.cErr : root.cDim; font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============ Sayfa 3: sonuç
                    Item {
                        width: viewport.width; height: viewport.height
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 14
                            width: parent.width - 120
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 72; height: 72; radius: 36
                                color: root.allOk ? root.cOk : root.cErr
                                Text { anchors.centerIn: parent; text: root.allOk ? "✓" : "!"; color: root.cBg; font.pixelSize: 38; font.weight: Font.Bold }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.nothingToDo ? "Her şey zaten kurulu" : (root.allOk ? "Hazır" : "Bazı adımlar tamamlanamadı")
                                color: root.cFg; font.pixelSize: 26; font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                text: root.nothingToDo
                                    ? "Bu bilgisayarda eksik bir şey yok. Sonraki açılışlarda yalnızca yeni bir şey eksik kalırsa sorulur."
                                    : root.allOk
                                    ? "Seçtiklerin kuruldu. İndirmediklerin için bir daha sorulmayacak (Reddedilenleri sıfırla ile geri açabilirsin)."
                                    : "Hata veren adımlar açılışta tekrar önerilir. Ayrıntı için ilerleme sayfasındaki satırlara bak."
                                color: root.cSub; font.pixelSize: 13
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 10
                                implicitWidth: doneTxt.implicitWidth + 56; implicitHeight: 42; radius: 21
                                color: doneArea.pressed ? Qt.darker(root.cAccent, 1.15) : root.cAccent
                                Text { id: doneTxt; anchors.centerIn: parent; text: "Kapat"; color: root.cBg; font.pixelSize: 14; font.weight: Font.DemiBold }
                                MouseArea { id: doneArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.quit() }
                            }
                        }
                    }
                }
            }
        }
    }
}
