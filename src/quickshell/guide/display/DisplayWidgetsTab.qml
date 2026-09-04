import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"
import "../../widgets"

Item {
    id: displayWidgetsRoot
    required property var rootObj
    required property int tabIndex
    property int subTabIndex: 1

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex && rootObj.currentSubTab === subTabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property real cardRadius: ThemeBackend.borderRadius <= 16 ? ThemeBackend.borderRadius * 2 : Math.min(32, 32 - 16 * Math.exp(-(ThemeBackend.borderRadius - 16) / 12))

    property var monitorsList: []
    property var monitorWidgetsMap: ({})

    function toBase64(str) {
        let utf8 = unescape(encodeURIComponent(str));
        let bytes = [];
        for (let i = 0; i < utf8.length; i++) {
            bytes.push(utf8.charCodeAt(i));
        }
        return Qt.btoa(bytes);
    }

    function deleteWidget(monName, widgetId) {
        if (!widgetId) return;
        let safeM = (monName || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
        let targetId = String(widgetId).trim();
        let curList = (displayWidgetsRoot.monitorWidgetsMap && displayWidgetsRoot.monitorWidgetsMap[monName]) ? displayWidgetsRoot.monitorWidgetsMap[monName] : [];
        let newList = [];
        for (let i = 0; i < curList.length; i++) {
            let item = curList[i];
            let id = String(item.wId || item.id || "").trim();
            if (id !== targetId) {
                newList.push(item);
            }
        }
        let m = Object.assign({}, displayWidgetsRoot.monitorWidgetsMap);
        m[monName] = newList;
        displayWidgetsRoot.monitorWidgetsMap = m;

        let mainTarget = Caching.mainQml || (Caching.serpantinumDir ? Caching.serpantinumDir + "/quickshell/Runner.qml" : "");
        if (mainTarget) {
            Quickshell.execDetached(["quickshell", "-p", mainTarget, "ipc", "call", "widgets-" + safeM, "remove", targetId]);
        } else {
            Quickshell.execDetached(["quickshell", "ipc", "call", "widgets-" + safeM, "remove", targetId]);
        }

        let b64 = toBase64(JSON.stringify(newList));
        let targetDir = Caching.getStateDir("widgets/" + safeM);
        let targetFile = targetDir + "/layout.json";
        let saveCmd = "mkdir -p '" + targetDir + "' && printf '%s' '" + b64 + "' | base64 -d > '" + targetFile + "'";
        Quickshell.execDetached(["bash", "-c", saveCmd]);
    }

    Process {
        id: screenDetector
        running: false
        command: ["bash", "-c", "hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j 2>/dev/null || niri msg -j outputs 2>/dev/null || swaymsg -t get_outputs -r 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                if (!out) return;
                let list = [];
                try {
                    let data = JSON.parse(out.trim());
                    if (Array.isArray(data)) {
                        for (let i = 0; i < data.length; i++) {
                            let item = data[i];
                            let name = item.name || "";
                            if (name) list.push({ name: name });
                        }
                    } else if (typeof data === "object") {
                        let keys = Object.keys(data);
                        for (let i = 0; i < keys.length; i++) {
                            list.push({ name: keys[i] });
                        }
                    }
                } catch(e) {}
                
                if (list.length === 0 && Quickshell.screens) {
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        list.push({ name: Quickshell.screens[i].name });
                    }
                }
                displayWidgetsRoot.monitorsList = list;
                displayWidgetsRoot.reloadAllWidgetFiles();
            }
        }
    }

    function reloadAllWidgetFiles() {
        if (monitorsList.length === 0) {
            displayWidgetsRoot.monitorWidgetsMap = {};
            return;
        }
        let paths = [];
        for (let i = 0; i < monitorsList.length; i++) {
            let mName = monitorsList[i].name;
            let safeM = (mName || "default").replace(/[^a-zA-Z0-9_-]/g, "_");
            paths.push(Caching.getStateDir("widgets/" + safeM) + "/layout.json");
        }
        readWidgetsProcess.exec(paths);
    }

    Process {
        id: readWidgetsProcess
        property var monitorNames: []

        function exec(paths) {
            monitorNames = displayWidgetsRoot.monitorsList.map(m => m.name);

            let script = "";
            for (let i = 0; i < paths.length; i++) {
                script += "echo '___WSPLIT___'; cat '" + paths[i] + "' 2>/dev/null || echo '[]'; ";
            }

            command = ["bash", "-c", script];
            running = false;
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text || "";
                let chunks = raw.split("___WSPLIT___");
                let m = {};
                for (let i = 0; i < readWidgetsProcess.monitorNames.length; i++) {
                    let mon = readWidgetsProcess.monitorNames[i];
                    let txt = (chunks[i + 1] || "[]").trim();
                    try {
                        let arr = JSON.parse(txt);
                        m[mon] = Array.isArray(arr) ? arr : [];
                    } catch (e) {
                        m[mon] = [];
                    }
                }
                displayWidgetsRoot.monitorWidgetsMap = m;
            }
        }
    }

    function openRedactor(mon) {
        let runnerTarget = Caching.serpantinumDir ? (Caching.serpantinumDir + "/quickshell/Runner.qml") : "";
        let redactorTarget = Caching.widgetRedactor || (Caching.serpantinumDir ? Caching.serpantinumDir + "/quickshell/widgets/WidgetRedactor.qml" : Caching.mainQml);
        let launchCmd = "{ mkdir -p '" + Caching.runDir + "' && printf '%s' '" + mon + "' > '" + Caching.runDir + "/redactor_target_monitor' && QS_WIDGET_MONITOR='" + mon + "' SERPANTINUM_TARGET_FILE='" + redactorTarget + "' quickshell -p '" + runnerTarget + "'; } >> /tmp/redactor_debug.log 2>&1";
        Quickshell.execDetached(["bash", "-c", launchCmd]);
        if (rootObj && typeof rootObj.closePopup === "function") {
            rootObj.closePopup();
        } else {
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
        }
    }

    Component.onCompleted: {
        screenDetector.running = true;
    }

    onVisibleChanged: {
        if (visible) {
            screenDetector.running = true;
        }
    }

    Connections {
        target: rootObj
        function onVisibleChanged() {
            if (rootObj && rootObj.visible && displayWidgetsRoot.visible) {
                screenDetector.running = true;
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: widgetsCol.implicitHeight + rootObj.s(16)
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            active: parent.moving || parent.movingVertically
            width: rootObj.s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: rootObj.s(4)
                radius: rootObj.s(2)
                color: ThemeBackend.surface2
            }
        }

        ColumnLayout {
            id: widgetsCol
            width: parent.width - (parent.contentHeight > parent.height ? rootObj.s(6) : 0)
            spacing: rootObj.s(12)

            Repeater {
                model: displayWidgetsRoot.monitorsList
                delegate: Rectangle {
                    id: monWidgetCard
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    clip: true
                    radius: displayWidgetsRoot.cardRadius
                    color: Qt.alpha(ThemeBackend.surface0, 0.4)
                    border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                    border.width: 1

                    property string monName: modelData.name
                    property var widgetsList: (displayWidgetsRoot.monitorWidgetsMap && displayWidgetsRoot.monitorWidgetsMap[monName]) ? displayWidgetsRoot.monitorWidgetsMap[monName] : []

                    implicitHeight: cardLayout.implicitHeight + rootObj.s(24)

                    ColumnLayout {
                        id: cardLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: rootObj.s(12)
                        spacing: rootObj.s(12)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(10)

                            Text {
                                text: monWidgetCard.monName
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(16)
                                font.bold: true
                                color: ThemeBackend.text
                            }

                            Text {
                                text: "(" + monWidgetCard.widgetsList.length + " " + (monWidgetCard.widgetsList.length === 1 ? I18n.t("widgets.redactor.widget_singular", "widget") : I18n.t("widgets.redactor.widgets_plural", "widgets")) + ")"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(12)
                                color: ThemeBackend.subtext0
                            }

                            Item { Layout.fillWidth: true }

                            ClickButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                maxWidth: rootObj.s(140)
                                implicitHeight: rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("guide.display.widgets.open", "Open Redactor")
                                buttonIcon: "󰕰"
                                iconFontSize: rootObj.s(14)
                                textFontSize: rootObj.s(12)
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.crust
                                onClicked: {
                                    displayWidgetsRoot.openRedactor(monWidgetCard.monName);
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.alpha(ThemeBackend.surface1, 0.3)
                        }

                        GridLayout {
                            id: widgetsGrid
                            Layout.fillWidth: true
                            columns: 3
                            rowSpacing: rootObj.s(8)
                            columnSpacing: rootObj.s(8)
                            visible: monWidgetCard.widgetsList.length > 0

                            property real colWidth: Math.max(0, (cardLayout.width - widgetsGrid.columnSpacing * 2) / 3)

                            Repeater {
                                model: monWidgetCard.widgetsList
                                delegate: Rectangle {
                                    id: widgetItemCard
                                    required property var modelData
                                    required property int index

                                    Layout.preferredWidth: widgetsGrid.colWidth
                                    Layout.maximumWidth: widgetsGrid.colWidth
                                    Layout.fillWidth: false
                                    Layout.preferredHeight: rootObj.s(48)
                                    radius: ThemeBackend.borderRadius
                                    color: Qt.alpha(ThemeBackend.surface1, 0.3)
                                    border.color: Qt.alpha(ThemeBackend.surface2, 0.35)
                                    border.width: 1

                                    property string wType: modelData.wType || modelData.type || "time"
                                    property var typeInfo: (typeof WidgetRegistry !== "undefined" && WidgetRegistry.types && WidgetRegistry.types[wType]) ? WidgetRegistry.types[wType] : null

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: rootObj.s(8)
                                        anchors.rightMargin: rootObj.s(8)
                                        spacing: rootObj.s(8)

                                        IconButton {
                                            size: rootObj.s(32)
                                            iconOffsetX: (widgetItemCard.typeInfo && widgetItemCard.typeInfo.iconOffsetX !== undefined) ? rootObj.s(widgetItemCard.typeInfo.iconOffsetX) : 0
                                            cornerRadius: ThemeBackend.borderRadius
                                            buttonIcon: (widgetItemCard.typeInfo && widgetItemCard.typeInfo.icon) ? widgetItemCard.typeInfo.icon : "󰕰"
                                            iconFontSize: rootObj.s(16)
                                            accentColor: ThemeBackend.surface1
                                            textColor: ThemeBackend.mauve
                                            Layout.alignment: Qt.AlignVCenter
                                            enabled: false
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: rootObj.s(1)

                                            Text {
                                                text: widgetItemCard.typeInfo && widgetItemCard.typeInfo.name ? widgetItemCard.typeInfo.name : widgetItemCard.wType
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(12)
                                                font.bold: true
                                                color: ThemeBackend.text
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: (widgetItemCard.modelData.wVariant || "default") + " • " + Math.round(widgetItemCard.modelData.wWidth || 0) + "x" + Math.round(widgetItemCard.modelData.wHeight || 0) + " @ (" + Math.round(widgetItemCard.modelData.wX || 0) + ", " + Math.round(widgetItemCard.modelData.wY || 0) + ")"
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(10)
                                                color: ThemeBackend.subtext0
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        DeleteButton {
                                            size: rootObj.s(28)
                                            cornerRadius: Math.min(ThemeBackend.borderRadius, rootObj.s(8))
                                            iconFontSize: rootObj.s(14)
                                            Layout.alignment: Qt.AlignVCenter
                                            onClicked: {
                                                let wId = widgetItemCard.modelData.wId || widgetItemCard.modelData.id;
                                                displayWidgetsRoot.deleteWidget(monWidgetCard.monName, wId);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: rootObj.s(40)
                            visible: monWidgetCard.widgetsList.length === 0

                            Text {
                                anchors.centerIn: parent
                                text: I18n.t("widgets.redactor.no_widgets_active", "No widgets configured for this screen")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(12)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }
                }
            }
        }
    }
}
