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
    id: workspacesWidgetRoot

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

    // Workspaces split into one block of workspaceCount per monitor (1-N, N+1-2N, ...).
    // Without this, a bar on the second monitor never lights up and switching on the
    // primary makes both bars look like they moved. Monitor order comes from screen X.
    property bool workspaceGroupsPerMonitor: (typeof Config !== "undefined" && Config.rawSettings
        && Config.rawSettings.bar) ? (Config.rawSettings.bar.workspaceGroupsPerMonitor === true) : false

    readonly property int groupOffset: {
        if (!workspaceGroupsPerMonitor) return 0;
        if (!barWindow || !barWindow.screen) return 0;
        let xs = Quickshell.screens.map(sc => sc.x).sort((a, b) => a - b);
        let i = xs.indexOf(barWindow.screen.x);
        return (i < 0 ? 0 : i) * workspaceCount;
    }

    // Index inside this bar's own group, or -1 when another monitor is focused.
    readonly property int hlLocalIndex: {
        const fw = Hyprland.focusedWorkspace;
        if (!fw) return -1;
        const l = fw.id - groupOffset - 1;
        return (l >= 0 && l < workspaceCount) ? l : -1;
    }
    // When focus is on the other screen we keep the last local one, so an unfocused
    // monitor's bar still shows where that monitor stands instead of going blank.
    property int lastLocalIndex: -1
    onHlLocalIndexChanged: if (hlLocalIndex >= 0) lastLocalIndex = hlLocalIndex;

    property int activeIndex: {
        if (isNiri) {
            let idx = niriActiveIndex;
            return (idx >= 0 && idx < workspaceCount) ? idx : -1;
        }
        if (isSway) {
            let idx = swayActiveIndex;
            return (idx >= 0 && idx < workspaceCount) ? idx : -1;
        }
        // Sticky only makes sense with per-monitor groups; without them an
        // out-of-range workspace means "nothing active", as before.
        return workspaceGroupsPerMonitor ? lastLocalIndex : hlLocalIndex;
    }

    Component.onCompleted: {
        let de = SystemInfo.desktopEnv ? SystemInfo.desktopEnv.toLowerCase() : "";
        workspacesWidgetRoot.isNiri = de.indexOf("niri") !== -1;
        workspacesWidgetRoot.isSway = de.indexOf("sway") !== -1;
        if (workspacesWidgetRoot.isNiri && workspacesWidgetRoot.moduleActive) {
            niriPoller.running = true;
            niriEventStream.running = true;
        }
        if (workspacesWidgetRoot.isSway && workspacesWidgetRoot.moduleActive) {
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
            if (workspacesWidgetRoot.moduleActive && workspacesWidgetRoot.isNiri) {
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
            if (workspacesWidgetRoot.moduleActive && workspacesWidgetRoot.isNiri) {
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
            if (workspacesWidgetRoot.moduleActive && workspacesWidgetRoot.isNiri) {
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
                    workspacesWidgetRoot.niriActiveIndex = activeIdx;
                    workspacesWidgetRoot.niriOccupiedMap = occ;
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
                    workspacesWidgetRoot.swayActiveIndex = activeIdx;
                    workspacesWidgetRoot.swayOccupiedMap = occ;
                } catch (e) {}

                swayWaiter.running = false;
                if (workspacesWidgetRoot.moduleActive && workspacesWidgetRoot.isSway) {
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
            if (workspacesWidgetRoot.moduleActive && workspacesWidgetRoot.isSway) {
                swayPoller.running = true;
            }
        }
    }

    property real targetX: 0
    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    radius: ThemeBackend.borderRadius
    border.width: 0
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    height: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    y: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - height) / 2 : 0
    clip: true

    property real targetWidth: (moduleActive && workspaceCount > 0) ? wsLayout.implicitWidth + barWindow.s(isCompact ? 18 : 22) : 0
    width: targetWidth
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

    opacity: (moduleActive && workspaceCount > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property real wheelAccumulator: 0
    Timer {
        id: wsWheelTimer
        interval: 200
        onTriggered: workspacesWidgetRoot.wheelAccumulator = 0
    }

    MouseArea {
        id: wsScrollArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wsWheelTimer.restart();
            workspacesWidgetRoot.wheelAccumulator += wheel.angleDelta.y;
            const threshold = 120;
            if (Math.abs(workspacesWidgetRoot.wheelAccumulator) >= threshold) {
                let steps = Math.trunc(workspacesWidgetRoot.wheelAccumulator / threshold);
                workspacesWidgetRoot.wheelAccumulator = workspacesWidgetRoot.wheelAccumulator % threshold;

                if (workspacesWidgetRoot.workspaceCount > 1) {
                    let cur = workspacesWidgetRoot.activeIndex;
                    let nextIndex = 0;
                    if (cur < 0) {
                        nextIndex = steps > 0 ? (workspacesWidgetRoot.workspaceCount - 1) : 0;
                    } else {
                        if (steps > 0) {
                            nextIndex = (cur - 1 + workspacesWidgetRoot.workspaceCount) % workspacesWidgetRoot.workspaceCount;
                        } else if (steps < 0) {
                            nextIndex = (cur + 1) % workspacesWidgetRoot.workspaceCount;
                        }
                    }
                    if (nextIndex !== workspacesWidgetRoot.activeIndex) {
                        if (workspacesWidgetRoot.isNiri) {
                            workspacesWidgetRoot.niriActiveIndex = nextIndex;
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", (nextIndex + 1).toString()]);
                        } else if (workspacesWidgetRoot.isSway) {
                            workspacesWidgetRoot.swayActiveIndex = nextIndex;
                            Quickshell.execDetached(["swaymsg", "workspace", "number", (nextIndex + 1).toString()]);
                        } else {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + (nextIndex + 1 + workspacesWidgetRoot.groupOffset) + " })");
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: activeHighlight
        z: 3
        radius: barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8)
        color: workspacesWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.05) : ThemeBackend.mauve

        property int prevIdx: 0
        property int curIdx: workspacesWidgetRoot.activeIndex

        onCurIdxChanged: {
            if (curIdx >= 0 && prevIdx >= 0) {
                if (curIdx > prevIdx) {
                    leftAnim.duration = 400;
                    rightAnim.duration = 300;
                } else if (curIdx < prevIdx) {
                    leftAnim.duration = 300;
                    rightAnim.duration = 400;
                }
            }
            if (curIdx >= 0) {
                prevIdx = curIdx;
            }
        }

        function getX(index, activeIndex) {
            if (index < 0) return 0;
            let xPos = 0;
            let spacing = barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8);
            let activeW = barWindow.s(workspacesWidgetRoot.isCompact ? 34 : 36);
            let inactiveW = barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18);
            for (let i = 0; i < index; i++) {
                xPos += (i === activeIndex ? activeW : inactiveW) + spacing;
            }
            return xPos;
        }

        property real targetLeft: curIdx >= 0 ? getX(curIdx, curIdx) : 0
        property real targetRight: curIdx >= 0 ? targetLeft + barWindow.s(workspacesWidgetRoot.isCompact ? 34 : 36) : 0
        property real actualLeft: targetLeft
        property real actualRight: targetRight

        Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 380; easing.type: Easing.OutQuint } }
        Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 380; easing.type: Easing.OutQuint } }

        x: wsLayout.x + actualLeft
        y: wsLayout.y + (wsLayout.height - height) / 2
        width: actualRight - actualLeft
        height: barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18)
        opacity: (workspacesWidgetRoot.workspaceCount > 0 && workspacesWidgetRoot.activeIndex >= 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Row {
        id: wsLayout
        z: 2
        anchors.centerIn: parent
        spacing: barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8)

        Repeater {
            model: workspacesWidgetRoot.workspaceCount

            delegate: Item {
                id: wsPill

                required property int index
                property int wsId: index + 1 + workspacesWidgetRoot.groupOffset
                property var ws: workspacesWidgetRoot.wsForId(wsId)
                property bool isOccupied: {
                    if (workspacesWidgetRoot.isNiri) {
                        return !!workspacesWidgetRoot.niriOccupiedMap[index];
                    }
                    if (workspacesWidgetRoot.isSway) {
                        return !!workspacesWidgetRoot.swayOccupiedMap[index];
                    }
                    return ws !== null && ws.toplevels && ws.toplevels.values && ws.toplevels.values.length > 0;
                }
                property bool isActive: index === workspacesWidgetRoot.activeIndex
                property bool initAnimTrigger: false

                width: isActive ? barWindow.s(workspacesWidgetRoot.isCompact ? 34 : 36) : barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18)
                height: barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18)
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                Rectangle {
                    id: wsVisualShape
                    anchors.fill: parent
                    radius: barWindow.s(workspacesWidgetRoot.isCompact ? 8 : 10)
                    color: wsPill.isActive ? "transparent" : (wsPill.isOccupied ? ThemeBackend.surface2 : (workspacesWidgetRoot.isCompact ? ThemeBackend.surface1 : ThemeBackend.surface0))
                    border.width: 0

                    Behavior on color { ColorAnimation { duration: 250 } }

                    scale: wsPillMouse.pressed ? 0.88 : (wsPillMouse.containsMouse ? 1.08 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                }

                opacity: initAnimTrigger ? 1.0 : 0.0
                transform: Translate {
                    y: wsPill.initAnimTrigger ? 0 : barWindow.s(15)
                    Behavior on y { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
                }

                Component.onCompleted: {
                    if (!barWindow.startupCascadeFinished) {
                        animTimer.interval = index * 50 + 100;
                        if (workspacesWidgetRoot.moduleActive) animTimer.start();
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
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: {
                        if (workspacesWidgetRoot.isNiri) {
                            workspacesWidgetRoot.niriActiveIndex = wsPill.index;
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", wsPill.wsId.toString()]);
                        } else if (workspacesWidgetRoot.isSway) {
                            workspacesWidgetRoot.swayActiveIndex = wsPill.index;
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
