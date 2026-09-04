import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Services.UPower
import "../../../reusables"
import "../../../"

Rectangle {
    id: sideBatRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property real targetY: 0
    property bool showLayout: false
    property alias batPill: batBtn

    property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : SystemInfo.isDesktop
    readonly property int batCap: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property string batIcon: isDesktop ? "󰐥" : (isCharging ? "󰂄" : (batCap > 20 ? "󰁹" : "󰂃"))

    property color batDynamicColor: {
        if (isDesktop) return ThemeBackend.red;
        if (isCharging) return ThemeBackend.green;
        if (batCap <= 15) return ThemeBackend.red;
        if (batCap <= 25) return ThemeBackend.peach;
        return ThemeBackend.teal;
    }

    property real targetWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetHeight: (moduleActive && batBtn.height > 0) ? (batBtn.height + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0

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
        duration: sideBatRoot.isCharging ? 1800 : 3600
        loops: Animation.Infinite
        running: sideBatRoot.showLayout && sideBatRoot.moduleActive
    }

    Timer {
        running: sideBatRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: sideBatRoot.showLayout = true
    }

    transform: Translate {
        y: sideBatRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Rectangle {
        id: batBtn
        anchors.centerIn: parent
        width: barWindow ? barWindow.s(sideBatRoot.isCompact ? 26 : 28) : (sideBatRoot.isCompact ? 26 : 28)
        height: barWindow ? barWindow.s(sideBatRoot.isCompact ? 26 : 28) : (sideBatRoot.isCompact ? 26 : 28)
        radius: Math.min(Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2)), width / 2)
        color: sideBatRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
        border.color: sideBatRoot.isCompact ? ThemeBackend.surface2 : ThemeBackend.surface1
        border.width: 1
        clip: true

        property real value: sideBatRoot.isDesktop ? 0.0 : (UPower.displayDevice.ready ? UPower.displayDevice.percentage : 0.0)
        property color accentColor: sideBatRoot.batDynamicColor
        property bool initAnimTrigger: false

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

        property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        property real fillY: height * (1.0 - fillRatio)
        property real maxWaveAmp: sideBatRoot.isCharging ? (barWindow ? barWindow.s(2.5) : 2.5) : (barWindow ? barWindow.s(0.5) : 0.5)
        property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? maxWaveAmp * Math.sin(fillRatio * Math.PI) : 0
        property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(sideBatRoot.globalWavePhase) - Math.cos(sideBatRoot.globalWavePhase))

        Timer {
            running: sideBatRoot.moduleActive && sideBatRoot.showLayout && !batBtn.initAnimTrigger
            interval: 150
            onTriggered: batBtn.initAnimTrigger = true
        }

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            y: batBtn.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
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
                if (batBtn.fillRatio <= 0) return;

                ctx.save();
                var r = batBtn.radius;
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
                ctx.moveTo(0, batBtn.fillY);
                if (batBtn.waveAmp > 0) {
                    var cp1y = batBtn.fillY + Math.sin(sideBatRoot.globalWavePhase) * batBtn.waveAmp;
                    var cp2y = batBtn.fillY + Math.cos(sideBatRoot.globalWavePhase + Math.PI) * batBtn.waveAmp;
                    ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, batBtn.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                } else {
                    ctx.lineTo(width, batBtn.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                }
                ctx.closePath();

                var grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.lighter(batBtn.accentColor, 1.25).toString());
                grad.addColorStop(1, batBtn.accentColor.toString());
                ctx.fillStyle = grad;
                ctx.globalAlpha = 0.95;
                ctx.fill();
                ctx.restore();
            }

            Connections {
                target: sideBatRoot
                enabled: (sideBatRoot.showLayout && sideBatRoot.moduleActive) && batBtn.waveAmp > 0
                function onGlobalWavePhaseChanged() { pillCanvas.requestPaint(); }
            }

            Connections {
                target: batBtn
                enabled: sideBatRoot.showLayout && sideBatRoot.moduleActive
                function onFillRatioChanged() { pillCanvas.requestPaint(); }
                function onAccentColorChanged() { pillCanvas.requestPaint(); }
                function onWaveAmpChanged() { pillCanvas.requestPaint(); }
            }
        }

        Text {
            anchors.centerIn: parent
            text: sideBatRoot.batIcon
            font.family: ThemeBackend.fontFamily
            font.pixelSize: sideBatRoot.isDesktop ? (barWindow ? barWindow.s(sideBatRoot.isCompact ? 15 : 16) : (sideBatRoot.isCompact ? 15 : 16)) : (barWindow ? barWindow.s(sideBatRoot.isCompact ? 12 : 13.5) : (sideBatRoot.isCompact ? 12 : 13.5))
            color: sideBatRoot.isDesktop ? ThemeBackend.red : (sideBatRoot.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)
        }

        Item {
            id: waveClipBox
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height, Math.max(0, (parent.height * batBtn.fillRatio) - batBtn.waveCenterOffset))
            clip: true
            visible: batBtn.fillRatio > 0

            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: batBtn.height

                Text {
                    anchors.centerIn: parent
                    text: sideBatRoot.batIcon
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: sideBatRoot.isDesktop ? (barWindow ? barWindow.s(sideBatRoot.isCompact ? 15 : 16) : (sideBatRoot.isCompact ? 15 : 16)) : (barWindow ? barWindow.s(sideBatRoot.isCompact ? 12 : 13.5) : (sideBatRoot.isCompact ? 12 : 13.5))
                    color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.75)
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle system"])
        }
    }
}
