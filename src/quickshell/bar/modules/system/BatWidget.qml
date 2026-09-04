import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import "../../../reusables"
import "../../../"

Rectangle {
    id: batWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)

    property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : SystemInfo.isDesktop
    readonly property int batCap: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property string batPercent: batCap + "%"

    readonly property string batStatus: UPower.displayDevice.ready ? (UPower.displayDevice.state === UPowerDeviceState.FullyCharged ? "Full" : (UPower.displayDevice.state === UPowerDeviceState.Charging ? "Charging" : "Unknown")) : "Unknown"
    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property string batIcon: isDesktop ? "󰐥" : (isCharging ? "󰂄" : (batCap > 20 ? "󰁹" : "󰂃"))

    property color batDynamicColor: {
        if (isDesktop) return ThemeBackend.red;
        if (isCharging) return ThemeBackend.green;
        if (batCap <= 15) return ThemeBackend.red;
        if (batCap <= 25) return ThemeBackend.peach;
        return ThemeBackend.teal;
    }

    property real targetX: 0
    property bool showLayout: false
    property alias batPill: batPill

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
    layer.enabled: true

    property real targetWidth: (moduleActive && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property real globalWavePhase: 0.0
    NumberAnimation on globalWavePhase {
        from: 0
        to: Math.PI * 2
        duration: batWidgetRoot.isCharging ? 1800 : 3600
        loops: Animation.Infinite
        running: batWidgetRoot.showLayout && batWidgetRoot.moduleActive
    }

    Timer {
        running: batWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: batWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: batWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(batWidgetRoot.isCompact ? 28 : 30) : (batWidgetRoot.isCompact ? 28 : 30)

        Rectangle {
            id: batPill
            property bool initAnimTrigger: false

            property real value: batWidgetRoot.isDesktop ? 0.0 : (UPower.displayDevice.ready ? UPower.displayDevice.percentage : 0.0)
            property real animValue: value
            Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

            property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
            property real fillY: height * (1.0 - fillRatio)
            property real maxWaveAmp: batWidgetRoot.isCharging ? (barWindow ? barWindow.s(3.5) : 3.5) : (barWindow ? barWindow.s(0.5) : 0.5)
            property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? maxWaveAmp * Math.sin(fillRatio * Math.PI) : 0
            property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(batWidgetRoot.globalWavePhase) - Math.cos(batWidgetRoot.globalWavePhase))

            height: sysLayout.pillHeight
            property real targetWidth: batWidgetRoot.isDesktop ? (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 30 : 32) : (batWidgetRoot.isCompact ? 30 : 32)) : (baseContentRow.implicitWidth + (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 16 : 18) : (batWidgetRoot.isCompact ? 16 : 18)))
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            radius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            color: batWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
            border.color: batWidgetRoot.isCompact ? ThemeBackend.surface2 : ThemeBackend.surface1
            border.width: 1
            clip: true

            Timer {
                running: batWidgetRoot.moduleActive && batWidgetRoot.showLayout && !batPill.initAnimTrigger
                interval: 150
                onTriggered: batPill.initAnimTrigger = true
            }

            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate {
                y: batPill.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
                Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
            }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            Canvas {
                id: pillCanvas
                anchors.fill: parent
                renderTarget: Canvas.FramebufferObject
                renderStrategy: Canvas.Cooperative

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (batPill.fillRatio <= 0) return;

                    ctx.save();
                    var r = Math.max(0, Math.min(batPill.radius, Math.min(width / 2, height / 2)));
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
                    ctx.moveTo(0, batPill.fillY);
                    if (batPill.waveAmp > 0) {
                        var cp1y = batPill.fillY + Math.sin(batWidgetRoot.globalWavePhase) * batPill.waveAmp;
                        var cp2y = batPill.fillY + Math.cos(batWidgetRoot.globalWavePhase + Math.PI) * batPill.waveAmp;
                        ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, batPill.fillY);
                        ctx.lineTo(width, height);
                        ctx.lineTo(0, height);
                    } else {
                        ctx.lineTo(width, batPill.fillY);
                        ctx.lineTo(width, height);
                        ctx.lineTo(0, height);
                    }
                    ctx.closePath();

                    var grad = ctx.createLinearGradient(0, 0, 0, height);
                    grad.addColorStop(0, Qt.lighter(batWidgetRoot.batDynamicColor, 1.25).toString());
                    grad.addColorStop(1, batWidgetRoot.batDynamicColor.toString());
                    ctx.fillStyle = grad;
                    ctx.globalAlpha = 0.95;
                    ctx.fill();
                    ctx.restore();
                }

                Connections {
                    target: batWidgetRoot
                    enabled: (batWidgetRoot.showLayout && batWidgetRoot.moduleActive) && batPill.waveAmp > 0
                    function onGlobalWavePhaseChanged() { pillCanvas.requestPaint(); }
                }

                Connections {
                    target: batPill
                    enabled: batWidgetRoot.showLayout && batWidgetRoot.moduleActive
                    function onRadiusChanged() { pillCanvas.requestPaint(); }
                    function onFillRatioChanged() { pillCanvas.requestPaint(); }
                    function onWaveAmpChanged() { pillCanvas.requestPaint(); }
                }

                Connections {
                    target: batWidgetRoot
                    enabled: batWidgetRoot.showLayout && batWidgetRoot.moduleActive
                    function onBatDynamicColorChanged() { pillCanvas.requestPaint(); }
                }
            }

            Row {
                id: baseContentRow
                anchors.centerIn: parent
                spacing: batWidgetRoot.isDesktop ? 0 : (barWindow ? barWindow.s(5) : 5)

                Text {
                    text: batWidgetRoot.batIcon
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: batWidgetRoot.isDesktop ? (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 15 : 16) : (batWidgetRoot.isCompact ? 15 : 16)) : (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 12 : 13.5) : (batWidgetRoot.isCompact ? 12 : 13.5))
                    color: batWidgetRoot.isDesktop ? ThemeBackend.red : (batWidgetRoot.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: !batWidgetRoot.isDesktop
                    text: batWidgetRoot.batPercent
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: barWindow ? barWindow.s(batWidgetRoot.isCompact ? 11 : 12.6) : (batWidgetRoot.isCompact ? 11 : 12.6)
                    font.bold: true
                    color: ThemeBackend.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: waveClipBox
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.min(parent.height, Math.max(0, (parent.height * batPill.fillRatio) - batPill.waveCenterOffset))
                clip: true
                visible: batPill.fillRatio > 0

                Item {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: batPill.height

                    Row {
                        anchors.centerIn: parent
                        spacing: batWidgetRoot.isDesktop ? 0 : (barWindow ? barWindow.s(5) : 5)

                        Text {
                            text: batWidgetRoot.batIcon
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: batWidgetRoot.isDesktop ? (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 15 : 16) : (batWidgetRoot.isCompact ? 15 : 16)) : (barWindow ? barWindow.s(batWidgetRoot.isCompact ? 12 : 13.5) : (batWidgetRoot.isCompact ? 12 : 13.5))
                            color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.75)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: !batWidgetRoot.isDesktop
                            text: batWidgetRoot.batPercent
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: barWindow ? barWindow.s(batWidgetRoot.isCompact ? 11 : 12.6) : (batWidgetRoot.isCompact ? 11 : 12.6)
                            font.bold: true
                            color: ThemeBackend.crust
                            anchors.verticalCenter: parent.verticalCenter
                        }
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
}
