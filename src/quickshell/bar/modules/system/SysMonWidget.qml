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
    id: sysMonWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool moduleActive: true
    property bool isGrouped: false
    property real targetX: 0
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

    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    y: barWindow.baseOffsetY
    height: barWindow.barHeight
    radius: Math.min(ThemeBackend.borderRadius, height / 2)
    border.color: (isGrouped || isSolid) ? "transparent" : ThemeBackend.surface0
    border.width: (isGrouped || isSolid) ? 0 : 1
    color: (isGrouped || isSolid) ? "transparent" : ThemeBackend.base
    clip: true
    layer.enabled: true

    property real targetWidth: (moduleActive && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(10) : 10)) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property real globalWavePhase: 0.0
    NumberAnimation on globalWavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
        running: sysMonWidgetRoot.isSysVisible
    }

    Timer {
        running: sysMonWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: sysMonWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: sysMonWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    component SysMonPill: Rectangle {
        id: pillRoot
        property real value: 0
        property string textVal: ""
        property string icon: ""
        property color accentColor: ThemeBackend.mauve
        property bool initAnimTrigger: false

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

        property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        property real fillY: height * (1.0 - fillRatio)
        property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? (barWindow ? barWindow.s(3.5) : 3.5) * Math.sin(fillRatio * Math.PI) : 0
        property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(sysMonWidgetRoot.globalWavePhase) - Math.cos(sysMonWidgetRoot.globalWavePhase))

        height: sysLayout.pillHeight
        width: sysLayout.pillWidth
        radius: Math.min(Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2)), height / 2)
        color: ThemeBackend.surface0
        border.color: ThemeBackend.surface1
        border.width: 1
        clip: true

        Timer {
            running: sysMonWidgetRoot.moduleActive && sysMonWidgetRoot.showLayout && !initAnimTrigger
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
                    var cp1y = pillRoot.fillY + Math.sin(sysMonWidgetRoot.globalWavePhase) * pillRoot.waveAmp;
                    var cp2y = pillRoot.fillY + Math.cos(sysMonWidgetRoot.globalWavePhase + Math.PI) * pillRoot.waveAmp;
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
                target: sysMonWidgetRoot
                enabled: sysMonWidgetRoot.isSysVisible && pillRoot.waveAmp > 0
                function onGlobalWavePhaseChanged() { pillCanvas.requestPaint(); }
            }

            Connections {
                target: pillRoot
                enabled: sysMonWidgetRoot.isSysVisible
                function onFillRatioChanged() { pillCanvas.requestPaint(); }
                function onAccentColorChanged() { pillCanvas.requestPaint(); }
            }
        }

        Row {
            id: baseContentRow
            anchors.centerIn: parent
            spacing: barWindow ? barWindow.s(6) : 6

            Text {
                text: icon
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(11.55) : 11.55
                color: ThemeBackend.subtext0
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: textVal
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(12.6) : 12.6
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
            height: Math.min(parent.height, Math.max(0, (parent.height * pillRoot.fillRatio) - pillRoot.waveCenterOffset))
            clip: true
            visible: pillRoot.fillRatio > 0

            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: pillRoot.height

                Row {
                    anchors.centerIn: parent
                    spacing: barWindow ? barWindow.s(6) : 6

                    Text {
                        text: icon
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: barWindow ? barWindow.s(11.55) : 11.55
                        color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.75)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: textVal
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: barWindow ? barWindow.s(12.6) : 12.6
                        font.bold: true
                        color: ThemeBackend.crust
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(6) : 6
        property int pillHeight: barWindow ? barWindow.s(30) : 30
        property int pillWidth: barWindow ? barWindow.s(62) : 62

        SysMonPill {
            value: isNaN(SysData.cpu) ? 0 : SysData.cpu / 100.0
            textVal: (isNaN(SysData.cpu) ? 0 : Math.round(SysData.cpu)) + "%"
            icon: "\uF2DB"
            accentColor: ThemeBackend.mauve
        }

        SysMonPill {
            value: isNaN(SysData.ramPercent) ? 0 : SysData.ramPercent / 100.0
            textVal: (isNaN(SysData.ramPercent) ? 0 : Math.round(SysData.ramPercent)) + "%"
            icon: "\uF538"
            accentColor: ThemeBackend.sapphire
        }

        SysMonPill {
            value: isNaN(SysData.temp) ? 0 : Math.max(0, Math.min(1, SysData.temp / 100.0))
            textVal: (isNaN(SysData.temp) ? 0 : Math.round(SysData.temp)) + "°"
            icon: "\uF2C9"
            accentColor: ThemeBackend.red
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            FloatingController.showSystemUsage(sysMonWidgetRoot.barWindow ? sysMonWidgetRoot.barWindow.screen : null);
        }
    }
}
