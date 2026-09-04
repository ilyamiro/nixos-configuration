import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../../reusables"
import "../../../"

Rectangle {
    id: sideSysMonRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property real targetY: 0
    property bool showLayout: false

    property bool isSysVisible: moduleActive && showLayout

    function updateSubscription() {
        if (isSysVisible) {
            SysData.subscribe()
        } else {
            SysData.unsubscribe()
        }
    }

    Component.onCompleted: updateSubscription()
    Component.onDestruction: SysData.unsubscribe()
    onIsSysVisibleChanged: updateSubscription()

    property real targetWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetHeight: (moduleActive && sysCol.implicitHeight > 0) ? (sysCol.implicitHeight + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0

    width: targetWidth
    height: targetHeight

    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

    x: barWindow ? ((barWindow.baseOffsetX !== undefined ? barWindow.baseOffsetX : 0) + (barWindow.barHeight - width) / 2) : 0
    y: targetY
    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    radius: Math.min(ThemeBackend.borderRadius, width / 2)
    border.width: 0
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    clip: true
    layer.enabled: true

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property real globalWavePhase: 0.0
    NumberAnimation on globalWavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
        running: sideSysMonRoot.isSysVisible
    }

    Timer {
        running: sideSysMonRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: sideSysMonRoot.showLayout = true
    }

    transform: Translate {
        y: sideSysMonRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    component SysMonPill: Rectangle {
        id: pillRoot
        property real value: 0
        property string icon: ""
        property color accentColor: ThemeBackend.mauve
        property bool initAnimTrigger: false

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

        property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        property real fillY: height * (1.0 - fillRatio)
        property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? (barWindow ? barWindow.s(sideSysMonRoot.isCompact ? 2.0 : 2.5) : (sideSysMonRoot.isCompact ? 2.0 : 2.5)) * Math.sin(fillRatio * Math.PI) : 0
        property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(sideSysMonRoot.globalWavePhase) - Math.cos(sideSysMonRoot.globalWavePhase))

        height: sysCol.pillHeight
        width: sysCol.pillWidth
        radius: Math.min(Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2)), width / 2)
        color: sideSysMonRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
        border.color: sideSysMonRoot.isCompact ? ThemeBackend.surface2 : ThemeBackend.surface1
        border.width: 1
        clip: true

        Timer {
            running: sideSysMonRoot.moduleActive && sideSysMonRoot.showLayout && !initAnimTrigger
            interval: 150
            onTriggered: initAnimTrigger = true
        }

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            y: initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
            Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        Canvas {
            id: pillCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            renderStrategy: Canvas.Cooperative

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (pillRoot.fillRatio <= 0) return;

                ctx.save();
                var r = pillRoot.radius;
                ctx.beginPath();
                ctx.moveTo(r, 0);
                ctx.lineTo(width - r, 0);
                ctx.quadraticCurveTo(width, 0, width, r);
                ctx.lineTo(width, height - r);
                ctx.quadraticCurveTo(width, height, width - r, height);
                ctx.lineTo(r, height);
                ctx.quadraticCurveTo(0, height, 0, height - r);
                ctx.lineTo(0, r);
                ctx.quadraticCurveTo(0, 0, r, 0);
                ctx.closePath();
                ctx.clip();

                ctx.beginPath();
                ctx.moveTo(0, pillRoot.fillY);
                if (pillRoot.waveAmp > 0) {
                    var cp1y = pillRoot.fillY + Math.sin(sideSysMonRoot.globalWavePhase) * pillRoot.waveAmp;
                    var cp2y = pillRoot.fillY + Math.cos(sideSysMonRoot.globalWavePhase + Math.PI) * pillRoot.waveAmp;
                    ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, pillRoot.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                } else {
                    ctx.lineTo(width, pillRoot.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                }
                ctx.closePath();

                var grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.lighter(pillRoot.accentColor, 1.25).toString());
                grad.addColorStop(1, pillRoot.accentColor.toString());
                ctx.fillStyle = grad;
                ctx.globalAlpha = 0.95;
                ctx.fill();
                ctx.restore();
            }

            Connections {
                target: sideSysMonRoot
                enabled: sideSysMonRoot.isSysVisible && pillRoot.waveAmp > 0
                function onGlobalWavePhaseChanged() { pillCanvas.requestPaint(); }
            }

            Connections {
                target: pillRoot
                enabled: sideSysMonRoot.isSysVisible
                function onFillRatioChanged() { pillCanvas.requestPaint(); }
                function onAccentColorChanged() { pillCanvas.requestPaint(); }
            }
        }

        Text {
            anchors.centerIn: parent
            text: icon
            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow ? barWindow.s(sideSysMonRoot.isCompact ? 13 : 14.5) : (sideSysMonRoot.isCompact ? 13 : 14.5)
            color: sideSysMonRoot.isCompact ? ThemeBackend.text : ThemeBackend.subtext0
        }

        Item {
            id: waveClipBox
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height, Math.max(0, (parent.height * pillRoot.fillRatio) - pillRoot.waveCenterOffset))
            clip: true
            visible: pillRoot.fillRatio > 0

            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: pillRoot.height

                Text {
                    anchors.centerIn: parent
                    text: icon
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: barWindow ? barWindow.s(sideSysMonRoot.isCompact ? 13 : 14.5) : (sideSysMonRoot.isCompact ? 13 : 14.5)
                    color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.75)
                }
            }
        }
    }

    Column {
        id: sysCol
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(sideSysMonRoot.isCompact ? 3 : 4) : (sideSysMonRoot.isCompact ? 3 : 4)
        property int pillHeight: barWindow ? barWindow.s(sideSysMonRoot.isCompact ? 26 : 28) : (sideSysMonRoot.isCompact ? 26 : 28)
        property int pillWidth: pillHeight

        SysMonPill {
            value: isNaN(SysData.cpu) ? 0 : SysData.cpu / 100.0
            icon: "\uF2DB"
            accentColor: ThemeBackend.mauve
        }

        SysMonPill {
            value: isNaN(SysData.ramPercent) ? 0 : SysData.ramPercent / 100.0
            icon: "󰍛"
            accentColor: ThemeBackend.sapphire
        }

        SysMonPill {
            value: isNaN(SysData.temp) ? 0 : Math.max(0, Math.min(1, SysData.temp / 100.0))
            icon: "\uF2C9"
            accentColor: ThemeBackend.red
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            FloatingController.showSystemUsage(sideSysMonRoot.barWindow ? sideSysMonRoot.barWindow.screen : null);
        }
    }
}
