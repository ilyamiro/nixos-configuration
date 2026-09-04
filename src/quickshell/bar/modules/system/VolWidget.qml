import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import "../../../reusables"
import "../../../"

Rectangle {
    id: volWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)

    property real sysVolume: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    property bool isMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false
    property string volPercent: sysVolume + "%"
    property string volIcon: isMuted || sysVolume === 0 ? "󰖁" : (sysVolume > 50 ? "󰕾" : "󰖀")
    property bool sysMuted: isMuted

    property bool isDraggingVol: false
    property bool isSoundActive: !isMuted && sysVolume > 0
    property real targetX: 0
    property bool showLayout: false
    property alias volPill: volPill

    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }
    height: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    y: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - height) / 2 : 0
    radius: ThemeBackend.borderRadius
    border.width: 0
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    clip: true

    property real targetWidth: (moduleActive && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: volWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: volWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: volWidgetRoot.showLayout ? 0 : barWindow.s(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(volWidgetRoot.isCompact ? 28 : 30) : (volWidgetRoot.isCompact ? 28 : 30)

        ClickButton {
            id: volPill
            property bool initAnimTrigger: false
            property bool isActive: isSoundActive

            height: sysLayout.pillHeight
            maxWidth: barWindow ? barWindow.s(volWidgetRoot.isCompact ? 96 : 100) : (volWidgetRoot.isCompact ? 96 : 100)
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            horizontalPadding: barWindow ? barWindow.s(volWidgetRoot.isCompact ? 10 : 12) : (volWidgetRoot.isCompact ? 10 : 12)
            buttonIcon: volIcon
            iconFontSize: barWindow ? barWindow.s(volWidgetRoot.isCompact ? 14 : 15) : (volWidgetRoot.isCompact ? 14 : 15)
            buttonText: volPercent
            textFontSize: barWindow ? barWindow.s(volWidgetRoot.isCompact ? 11 : 12) : (volWidgetRoot.isCompact ? 11 : 12)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            accentColor: isActive ? (volWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve) : (volWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.12) : ThemeBackend.surface1)
            textColor: isActive ? ThemeBackend.base : (volWidgetRoot.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)

            property real targetWidth: implicitWidth
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Timer { running: volWidgetRoot.moduleActive && volWidgetRoot.showLayout && !volPill.initAnimTrigger; interval: 250; onTriggered: volPill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: volPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle volume"])
            onRightClicked: if (Audio.defaultSink) Audio.toggleMute(Audio.defaultSink)

            property real wheelAccumulator: 0
            Timer {
                id: volWheelTimer
                interval: 200
                onTriggered: volPill.wheelAccumulator = 0
            }

            onWheel: wheel => {
                volWheelTimer.restart()
                volPill.wheelAccumulator += wheel.angleDelta.y
                const threshold = 120
                if (Math.abs(volPill.wheelAccumulator) >= threshold) {
                    let steps = Math.trunc(volPill.wheelAccumulator / threshold)
                    volPill.wheelAccumulator = volPill.wheelAccumulator % threshold
                    if (steps !== 0 && Audio.defaultSink) {
                        let newVol = Math.max(0, Math.min(Audio.maxVolume, sysVolume + (steps * 5)))
                        Audio.setVolume(Audio.defaultSink, newVol)
                    }
                }
            }
        }
    }
}
