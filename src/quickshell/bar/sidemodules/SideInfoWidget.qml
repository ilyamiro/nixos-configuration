import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../reusables"
import "../../"

Rectangle {
    id: sideInfoWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    readonly property bool isRightBar: barWindow ? (barWindow.barPosition === "right") : false

    property bool isCleaningUp: false
    property bool isRecording: false
    property int recSeconds: 0
    property real recStartEpoch: 0
    property string recTimeFormatted: String(Math.floor(recSeconds / 60)).padStart(2, "0") + ":" + String(recSeconds % 60).padStart(2, "0")
    readonly property string recCacheDir: Caching.cacheDir ? Caching.getCacheDir("recording") : ""

    readonly property bool isTimerActive: TimerState.isActive
    readonly property string timerTimeFormatted: TimerState.timeFormatted
    readonly property string timerIcon: TimerState.icon
    readonly property color timerColor: TimerState.colorType === "green" ? ((typeof ThemeBackend !== "undefined" && ThemeBackend.green !== undefined) ? ThemeBackend.green : Qt.rgba(166/255, 227/255, 161/255, 1.0)) : ThemeBackend.mauve

    readonly property bool hasActiveContent: isRecording || isTimerActive

    function checkRecording() {
        if (sideInfoWidgetRoot.isCleaningUp || !sideInfoWidgetRoot.moduleActive || sideInfoWidgetRoot.recCacheDir === "") return;
        recCheckProc.running = false;
        recCheckProc.running = true;
    }

    onIsRecordingChanged: {
        if (!isRecording) {
            recSeconds = 0;
            recStartEpoch = 0;
        }
    }

    onRecCacheDirChanged: {
        if (recCacheDir !== "") {
            sideInfoWidgetRoot.checkRecording();
        }
    }

    Process {
        id: recCheckProc
        command: sideInfoWidgetRoot.recCacheDir ? [
            "bash", "-c",
            "d='" + sideInfoWidgetRoot.recCacheDir + "'; if [ -f \"$d/rec_pid\" ] && [ -f \"$d/rec_start_epoch\" ]; then p=$(cat \"$d/rec_pid\" 2>/dev/null); if [ -n \"$p\" ] && kill -0 \"$p\" 2>/dev/null; then cat \"$d/rec_start_epoch\" 2>/dev/null; else echo 'NONE'; fi; else echo 'NONE'; fi"
        ] : []
        stdout: StdioCollector {
            id: recCheckOut
            onStreamFinished: {
                let txt = recCheckOut.text.trim();
                let epoch = parseInt(txt);
                if (!isNaN(epoch) && epoch > 0) {
                    sideInfoWidgetRoot.recStartEpoch = epoch;
                    sideInfoWidgetRoot.recSeconds = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
                    sideInfoWidgetRoot.isRecording = true;
                } else {
                    sideInfoWidgetRoot.isRecording = false;
                }
            }
        }
    }

    Process {
        id: recWatcher
        running: !sideInfoWidgetRoot.isCleaningUp && sideInfoWidgetRoot.moduleActive && sideInfoWidgetRoot.recCacheDir !== ""
        command: sideInfoWidgetRoot.recCacheDir ? [
            "bash", "-c",
            "mkdir -p '" + sideInfoWidgetRoot.recCacheDir + "' && exec inotifywait -m -e create,delete,modify,moved_to,moved_from '" + sideInfoWidgetRoot.recCacheDir + "' 2>/dev/null"
        ] : []
        stdout: SplitParser {
            onRead: data => {
                sideInfoWidgetRoot.checkRecording();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 127 || sideInfoWidgetRoot.isCleaningUp) return;
            if (sideInfoWidgetRoot.moduleActive && sideInfoWidgetRoot.recCacheDir !== "") {
                recWatcherRestartTimer.restart();
            }
        }
    }

    Timer {
        id: recWatcherRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!sideInfoWidgetRoot.isCleaningUp && sideInfoWidgetRoot.moduleActive && sideInfoWidgetRoot.recCacheDir !== "" && !recWatcher.running) {
                recWatcher.running = true;
            }
        }
    }

    Timer {
        id: recElapsedTimer
        interval: 1000
        running: !sideInfoWidgetRoot.isCleaningUp && sideInfoWidgetRoot.moduleActive && sideInfoWidgetRoot.isRecording
        repeat: true
        onTriggered: {
            sideInfoWidgetRoot.recSeconds = Math.max(0, Math.floor(Date.now() / 1000 - sideInfoWidgetRoot.recStartEpoch));
            if (sideInfoWidgetRoot.recSeconds % 5 === 0) {
                sideInfoWidgetRoot.checkRecording();
            }
        }
    }

    property int animDuration: 600
    property real targetY: 0
    y: targetY

    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging
        NumberAnimation { duration: sideInfoWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }

    property alias recCol: recCol
    property alias timerCol: timerCol

    property real verticalPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    property real innerSpacing: barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10)

    property real recHeight: isRecording ? recCol.implicitHeight : 0
    property real timerHeight: isTimerActive ? timerCol.implicitHeight : 0
    property real activeSpacing: (isRecording && isTimerActive) ? innerSpacing : 0

    property real baseHeight: hasActiveContent ? (recHeight + timerHeight + activeSpacing + (verticalPadding * 2)) : 0
    property real baseWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))

    property real targetWidth: moduleActive ? baseWidth : 0
    property real targetHeight: moduleActive ? baseHeight : 0

    MouseArea {
        id: bgMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    property bool isHovered: bgMouse.containsMouse
    property bool showLayout: false

    property real targetX: isRightBar ? (parent ? (parent.width - targetWidth) : 0) : 0
    x: targetX

    Behavior on x {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideInfoWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }

    width: targetWidth
    height: targetHeight

    color: "transparent"
    border.width: 0
    clip: true
    visible: (height > 0 || opacity > 0) && (!barWindow || !barWindow.positionChanging)
    opacity: (showLayout && moduleActive && hasActiveContent && (!barWindow || !barWindow.positionChanging)) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0

    Rectangle {
        id: bgRect
        z: -1
        width: parent.width
        height: parent.height
        radius: ThemeBackend.borderRadius
        color: sideInfoWidgetRoot.isGrouped ? "transparent" : (sideInfoWidgetRoot.isSolid ? (sideInfoWidgetRoot.distinctPills ? (sideInfoWidgetRoot.isHovered ? ThemeBackend.surface0 : Qt.darker(ThemeBackend.surface0, 1.15)) : "transparent") : (sideInfoWidgetRoot.isHovered ? ThemeBackend.surface0 : ThemeBackend.base))
        border.width: 0
        visible: height > 0

        Behavior on color { enabled: barWindow ? !barWindow.positionChanging : true; ColorAnimation { duration: 250 } }
    }

    Behavior on width {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideInfoWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideInfoWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
    }

    transform: Translate {
        x: sideInfoWidgetRoot.showLayout ? 0 : (barWindow ? (sideInfoWidgetRoot.isRightBar ? barWindow.s(20) : barWindow.s(-20)) : (sideInfoWidgetRoot.isRightBar ? 20 : -20))
        Behavior on x {
            enabled: barWindow ? !barWindow.positionChanging : true
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Timer {
        running: barWindow && barWindow.isStartupReady
        interval: 120
        onTriggered: sideInfoWidgetRoot.showLayout = true
    }

    Item {
        id: topArea
        width: parent.width
        height: parent.height
        anchors.centerIn: parent

        Column {
            id: centerActiveCol
            anchors.centerIn: parent
            spacing: sideInfoWidgetRoot.innerSpacing

            Column {
                id: recCol
                spacing: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 3 : 4) : (sideInfoWidgetRoot.isCompact ? 3 : 4)
                visible: isRecording
                opacity: isRecording ? 1.0 : 0.0
                anchors.horizontalCenter: parent.horizontalCenter
                Behavior on opacity {
                    enabled: barWindow ? !barWindow.positionChanging : true
                    NumberAnimation { duration: 300 }
                }

                Rectangle {
                    id: recDot
                    width: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 8 : 10) : (sideInfoWidgetRoot.isCompact ? 8 : 10)
                    height: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 8 : 10) : (sideInfoWidgetRoot.isCompact ? 8 : 10)
                    radius: width * 0.5
                    color: sideInfoWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.red, 1.08) : ThemeBackend.red
                    anchors.horizontalCenter: parent.horizontalCenter

                    SequentialAnimation on opacity {
                        running: isRecording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    id: recText
                    text: recTimeFormatted
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 11 : 12) : (sideInfoWidgetRoot.isCompact ? 11 : 12)
                    font.weight: Font.Bold
                    color: sideInfoWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.red, 1.08) : ThemeBackend.red
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                id: timerCol
                spacing: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 3 : 4) : (sideInfoWidgetRoot.isCompact ? 3 : 4)
                visible: isTimerActive
                opacity: isTimerActive ? 1.0 : 0.0
                anchors.horizontalCenter: parent.horizontalCenter
                Behavior on opacity {
                    enabled: barWindow ? !barWindow.positionChanging : true
                    NumberAnimation { duration: 300 }
                }

                Text {
                    text: timerIcon
                    font.family: "Font Awesome 6 Free Solid"
                    font.pixelSize: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 10 : 11) : (sideInfoWidgetRoot.isCompact ? 10 : 11)
                    color: sideInfoWidgetRoot.isCompact ? Qt.lighter(sideInfoWidgetRoot.timerColor, 1.08) : sideInfoWidgetRoot.timerColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                Text {
                    id: timerText
                    text: timerTimeFormatted
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: barWindow ? barWindow.s(sideInfoWidgetRoot.isCompact ? 11 : 12) : (sideInfoWidgetRoot.isCompact ? 11 : 12)
                    font.weight: Font.Bold
                    color: sideInfoWidgetRoot.isCompact ? Qt.lighter(sideInfoWidgetRoot.timerColor, 1.08) : sideInfoWidgetRoot.timerColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }
        }
    }

    Component.onCompleted: {
        sideInfoWidgetRoot.checkRecording();
    }

    Component.onDestruction: {
        sideInfoWidgetRoot.isCleaningUp = true;
        recWatcherRestartTimer.stop();
        recWatcher.running = false;
        recCheckProc.running = false;
    }
}
