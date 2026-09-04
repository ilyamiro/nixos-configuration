import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../../reusables"
import "../../"

Rectangle {
    id: sideWsRoot

    property var barWindow
    property var paths
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property bool isNiri: false
    property bool isSway: false

    property int niriActiveIndex: 0
    property var niriOccupiedMap: ({})

    property int swayActiveIndex: 0
    property var swayOccupiedMap: ({})

    property int workspaceCount: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.workspaceCount !== undefined) ? Math.max(2, Math.min(10, Config.rawSettings.bar.workspaceCount)) : ((typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general && Config.rawSettings.general.workspaceCount !== undefined) ? Math.max(2, Math.min(10, Config.rawSettings.general.workspaceCount)) : ((typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.workspaceCount !== undefined) ? Math.max(2, Math.min(10, Config.rawSettings.workspaceCount)) : 8))

    function wsForId(id) {
        if (isNiri || isSway) return null;
        return Hyprland.workspaces.values.find(w => w.id === id) ?? null;
    }

    property int activeIndex: {
        let idx = -1;
        if (isNiri) {
            idx = niriActiveIndex;
        } else if (isSway) {
            idx = swayActiveIndex;
        } else {
            const fw = Hyprland.focusedWorkspace;
            if (!fw) return -1;
            idx = fw.id - 1;
        }
        return (idx >= 0 && idx < workspaceCount) ? idx : -1;
    }

    Component.onCompleted: {
        let de = SystemInfo.desktopEnv ? SystemInfo.desktopEnv.toLowerCase() : "";
        sideWsRoot.isNiri = de.indexOf("niri") !== -1;
        sideWsRoot.isSway = de.indexOf("sway") !== -1;
        if (sideWsRoot.isNiri && sideWsRoot.moduleActive) {
            niriPoller.running = true;
            niriEventStream.running = true;
        }
        if (sideWsRoot.isSway && sideWsRoot.moduleActive) {
            swayPoller.running = true;
        }
    }

    onModuleActiveChanged: {
        if (!moduleActive) {
            if (isNiri) {
                niriPoller.running = false;
                niriDebounceTimer.stop();
                niriRestartTimer.stop();
                niriEventStream.running = false;
            }
            if (isSway) {
                swayPoller.running = false;
                swayWaiter.running = false;
            }
        } else {
            if (isNiri) {
                niriPoller.running = false;
                niriPoller.running = true;
                niriEventStream.running = false;
                niriEventStream.running = true;
            }
            if (isSway) {
                swayPoller.running = false;
                swayPoller.running = true;
            }
        }
    }

    Timer {
        id: niriDebounceTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (sideWsRoot.moduleActive && sideWsRoot.isNiri) {
                niriPoller.running = false;
                niriPoller.running = true;
            }
        }
    }

    Timer {
        id: niriRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (sideWsRoot.moduleActive && sideWsRoot.isNiri) {
                niriEventStream.running = false;
                niriEventStream.running = true;
            }
        }
    }

    Process {
        id: niriEventStream
        running: false
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().length > 0) {
                    niriDebounceTimer.restart();
                }
            }
        }
        onExited: {
            if (sideWsRoot.moduleActive && sideWsRoot.isNiri) {
                niriRestartTimer.restart();
            }
        }
    }

    Process {
        id: niriPoller
        running: false
        command: [
            "bash",
            "-c",
            "workspaces=$(niri msg -j workspaces 2>/dev/null || echo '[]'); windows=$(niri msg -j windows 2>/dev/null || echo '[]'); echo \"{\\\"workspaces\\\": $workspaces, \\\"windows\\\": $windows}\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    let wsList = data.workspaces || [];
                    let winList = data.windows || [];
                    let occ = {};
                    for (let i = 0; i < winList.length; i++) {
                        let win = winList[i];
                        if (win.workspace_id !== undefined && win.workspace_id !== null) {
                            occ[win.workspace_id] = true;
                        }
                    }
                    let activeIdx = 0;
                    for (let j = 0; j < wsList.length; j++) {
                        let w = wsList[j];
                        let idx = (w.idx !== undefined ? w.idx : (w.id !== undefined ? w.id : 1)) - 1;
                        if (w.is_focused || w.is_active) {
                            activeIdx = idx;
                        }
                        if (w.active_window_id !== null || occ[w.id] || occ[w.idx]) {
                            occ[idx] = true;
                        }
                    }
                    sideWsRoot.niriActiveIndex = activeIdx;
                    sideWsRoot.niriOccupiedMap = occ;
                } catch (e) {}
            }
        }
    }

    Process {
        id: swayPoller
        running: false
        command: [
            "bash",
            "-c",
            "swaymsg -t get_workspaces -r 2>/dev/null || echo '[]'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let wsList = JSON.parse(this.text) || [];
                    let occ = {};
                    let activeIdx = 0;
                    for (let i = 0; i < wsList.length; i++) {
                        let w = wsList[i];
                        let num = (w.num !== undefined && w.num > 0) ? w.num : parseInt(w.name);
                        let idx = (!isNaN(num) && num > 0) ? num - 1 : i;
                        if (w.focused) {
                            activeIdx = idx;
                        }
                        occ[idx] = true;
                    }
                    sideWsRoot.swayActiveIndex = activeIdx;
                    sideWsRoot.swayOccupiedMap = occ;
                } catch (e) {}

                swayWaiter.running = false;
                if (sideWsRoot.moduleActive && sideWsRoot.isSway) {
                    swayWaiter.running = true;
                }
            }
        }
    }

    Process {
        id: swayWaiter
        running: false
        command: [
            "bash",
            "-c",
            "swaymsg -t subscribe -m '[\"workspace\", \"window\"]' 2>/dev/null | grep -m 1 -E '\"change\"'"
        ]
        onExited: {
            swayPoller.running = false;
            if (sideWsRoot.moduleActive && sideWsRoot.isSway) {
                swayPoller.running = true;
            }
        }
    }

    property real targetY: 0
    y: targetY
    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    property real targetWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetHeight: (moduleActive && workspaceCount > 0) ? wsCol.implicitHeight + (barWindow ? barWindow.s(isCompact ? 18 : 22) : (isCompact ? 18 : 22)) : 0

    width: targetWidth
    height: targetHeight

    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

    radius: ThemeBackend.borderRadius
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    border.width: 0
    clip: true

    opacity: (moduleActive && workspaceCount > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property real wheelAccumulator: 0
    Timer {
        id: wsWheelTimer
        interval: 200
        onTriggered: sideWsRoot.wheelAccumulator = 0
    }

    MouseArea {
        id: wsScrollArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wsWheelTimer.restart();
            sideWsRoot.wheelAccumulator += wheel.angleDelta.y;
            const threshold = 120;
            if (Math.abs(sideWsRoot.wheelAccumulator) >= threshold) {
                let steps = Math.trunc(sideWsRoot.wheelAccumulator / threshold);
                sideWsRoot.wheelAccumulator = sideWsRoot.wheelAccumulator % threshold;

                if (sideWsRoot.workspaceCount > 1) {
                    let cur = sideWsRoot.activeIndex;
                    let nextIndex = 0;
                    if (cur < 0) {
                        nextIndex = steps > 0 ? (sideWsRoot.workspaceCount - 1) : 0;
                    } else {
                        if (steps > 0) {
                            nextIndex = (cur - 1 + sideWsRoot.workspaceCount) % sideWsRoot.workspaceCount;
                        } else if (steps < 0) {
                            nextIndex = (cur + 1) % sideWsRoot.workspaceCount;
                        }
                    }
                    if (nextIndex !== sideWsRoot.activeIndex) {
                        if (sideWsRoot.isNiri) {
                            sideWsRoot.niriActiveIndex = nextIndex;
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", (nextIndex + 1).toString()]);
                        } else if (sideWsRoot.isSway) {
                            sideWsRoot.swayActiveIndex = nextIndex;
                            Quickshell.execDetached(["swaymsg", "workspace", "number", (nextIndex + 1).toString()]);
                        } else {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + (nextIndex + 1) + " })");
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: activeHighlight
        z: 3
        radius: barWindow ? barWindow.s(sideWsRoot.isCompact ? 7 : 8) : (sideWsRoot.isCompact ? 7 : 8)
        color: sideWsRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.05) : ThemeBackend.mauve

        property int prevIdx: 0
        property int curIdx: sideWsRoot.activeIndex

        onCurIdxChanged: {
            if (curIdx >= 0 && prevIdx >= 0) {
                if (curIdx > prevIdx) {
                    topAnim.duration = 400;
                    bottomAnim.duration = 300;
                } else if (curIdx < prevIdx) {
                    topAnim.duration = 300;
                    bottomAnim.duration = 400;
                }
            }
            if (curIdx >= 0) {
                prevIdx = curIdx;
            }
        }

        function getY(index, activeIndex) {
            if (index < 0) return 0;
            let yPos = 0;
            let spacing = barWindow ? barWindow.s(sideWsRoot.isCompact ? 7 : 8) : (sideWsRoot.isCompact ? 7 : 8);
            let activeH = barWindow ? barWindow.s(sideWsRoot.isCompact ? 34 : 36) : (sideWsRoot.isCompact ? 34 : 36);
            let inactiveH = barWindow ? barWindow.s(sideWsRoot.isCompact ? 16 : 18) : (sideWsRoot.isCompact ? 16 : 18);
            for (let i = 0; i < index; i++) {
                yPos += (i === activeIndex ? activeH : inactiveH) + spacing;
            }
            return yPos;
        }

        property real targetTop: curIdx >= 0 ? getY(curIdx, curIdx) : 0
        property real targetBottom: curIdx >= 0 ? targetTop + (barWindow ? barWindow.s(sideWsRoot.isCompact ? 34 : 36) : (sideWsRoot.isCompact ? 34 : 36)) : 0
        property real actualTop: targetTop
        property real actualBottom: targetBottom

        Behavior on actualTop { NumberAnimation { id: topAnim; duration: 380; easing.type: Easing.OutQuint } }
        Behavior on actualBottom { NumberAnimation { id: bottomAnim; duration: 380; easing.type: Easing.OutQuint } }

        x: wsCol.x + (wsCol.width - width) / 2
        y: wsCol.y + actualTop
        width: barWindow ? barWindow.s(sideWsRoot.isCompact ? 16 : 18) : (sideWsRoot.isCompact ? 16 : 18)
        height: actualBottom - actualTop
        opacity: (sideWsRoot.workspaceCount > 0 && sideWsRoot.activeIndex >= 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Column {
        id: wsCol
        z: 2
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(sideWsRoot.isCompact ? 7 : 8) : (sideWsRoot.isCompact ? 7 : 8)

        Repeater {
            model: sideWsRoot.workspaceCount

            delegate: Item {
                id: wsPill

                required property int index
                property int wsId: index + 1
                property var ws: sideWsRoot.wsForId(wsId)
                property bool isOccupied: {
                    if (sideWsRoot.isNiri) {
                        return !!sideWsRoot.niriOccupiedMap[index];
                    }
                    if (sideWsRoot.isSway) {
                        return !!sideWsRoot.swayOccupiedMap[index];
                    }
                    return ws !== null && ws.toplevels && ws.toplevels.values && ws.toplevels.values.length > 0;
                }
                property bool isActive: index === sideWsRoot.activeIndex
                property bool initAnimTrigger: false

                width: barWindow ? barWindow.s(sideWsRoot.isCompact ? 16 : 18) : (sideWsRoot.isCompact ? 16 : 18)
                height: isActive ? (barWindow ? barWindow.s(sideWsRoot.isCompact ? 34 : 36) : (sideWsRoot.isCompact ? 34 : 36)) : (barWindow ? barWindow.s(sideWsRoot.isCompact ? 16 : 18) : (sideWsRoot.isCompact ? 16 : 18))
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                Rectangle {
                    id: wsVisualShape
                    anchors.fill: parent
                    radius: barWindow ? barWindow.s(sideWsRoot.isCompact ? 8 : 10) : (sideWsRoot.isCompact ? 8 : 10)
                    color: wsPill.isActive ? "transparent" : (wsPill.isOccupied ? ThemeBackend.surface2 : (sideWsRoot.isCompact ? ThemeBackend.surface1 : ThemeBackend.surface0))
                    border.width: 0

                    Behavior on color { ColorAnimation { duration: 250 } }

                    scale: wsPillMouse.pressed ? 0.88 : (wsPillMouse.containsMouse ? 1.08 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                }

                opacity: initAnimTrigger ? 1.0 : 0.0
                transform: Translate {
                    x: wsPill.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
                    Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
                }

                Component.onCompleted: {
                    if (barWindow && !barWindow.startupCascadeFinished) {
                        animTimer.interval = index * 50 + 100;
                        if (sideWsRoot.moduleActive) animTimer.start();
                    } else {
                        initAnimTrigger = true;
                    }
                }

                Timer {
                    id: animTimer
                    running: false; repeat: false
                    onTriggered: wsPill.initAnimTrigger = true
                }

                Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

                MouseArea {
                    id: wsPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (sideWsRoot.isNiri) {
                            sideWsRoot.niriActiveIndex = wsPill.index;
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", wsPill.wsId.toString()]);
                        } else if (sideWsRoot.isSway) {
                            sideWsRoot.swayActiveIndex = wsPill.index;
                            Quickshell.execDetached(["swaymsg", "workspace", "number", wsPill.wsId.toString()]);
                        } else {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsPill.wsId + " })");
                        }
                    }
                }
            }
        }
    }
}
