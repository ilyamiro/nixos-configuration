import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 220
    property real minHeight: 130
    property real maxWidth: 500
    property real maxHeight: 300
    property real minAspect: 1.2
    property real maxAspect: 2.8
    property bool isRound: false

    Rectangle {
        anchors.fill: parent
        color: ThemeBackend.surface0
        radius: ThemeBackend.clampedBorderRadius
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(10)
            spacing: Scaler.s(8)

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Scaler.s(10)

                ImageBox {
                    id: avatarBox
                    Layout.preferredWidth: Scaler.s(70)
                    Layout.preferredHeight: Scaler.s(70)
                    size: Scaler.s(70)
                    cornerRadius: ThemeBackend.borderRadius > 0 ? Math.min(ThemeBackend.borderRadius, Scaler.s(12)) : Scaler.s(12)
                    imageRadius: cornerRadius
                    source: SystemInfo.avatarPath !== "" ? "file://" + SystemInfo.avatarPath : ""
                    backgroundColor: SystemInfo.avatarPath === "" ? ThemeBackend.surface1 : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: Scaler.s(30)
                        color: ThemeBackend.text
                        visible: SystemInfo.avatarPath === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Scaler.s(6)

                    ClickButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Scaler.s(32)
                        cornerRadius: ThemeBackend.borderRadius > 0 ? Math.min(ThemeBackend.borderRadius, Scaler.s(8)) : Scaler.s(8)
                        horizontalPadding: Scaler.s(10)
                        contentAlignment: Qt.AlignLeft
                        buttonIcon: ""
                        iconFontSize: Scaler.s(15)
                        buttonText: SystemInfo.username !== "" ? SystemInfo.username : "User"
                        textFontSize: Scaler.s(12)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle guide"])
                    }

                    ClickButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Scaler.s(32)
                        cornerRadius: ThemeBackend.borderRadius > 0 ? Math.min(ThemeBackend.borderRadius, Scaler.s(8)) : Scaler.s(8)
                        horizontalPadding: Scaler.s(10)
                        contentAlignment: Qt.AlignLeft
                        buttonIcon: ""
                        iconFontSize: Scaler.s(15)
                        buttonText: "Lock"
                        textFontSize: Scaler.s(12)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.mauve

                        onClicked: {
                            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/lock.sh"]);
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(36)
                spacing: Scaler.s(6)

                Repeater {
                    model: [
                        { cmd: "sleep", icon: "󰤄", weight: 1.0, color: ThemeBackend.blue },
                        { cmd: "reboot", icon: "󰑓", weight: 2.0, color: ThemeBackend.peach },
                        { cmd: "poweroff", icon: "", weight: 3.0, color: ThemeBackend.red }
                    ]

                    delegate: Rectangle {
                        id: actionCapsule
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: ThemeBackend.borderRadius > 0 ? Math.min(ThemeBackend.borderRadius, Scaler.s(8)) : Scaler.s(8)
                        clip: true

                        property real fillLevel: 0.0
                        property bool triggered: false
                        property real flashOpacity: 0.0
                        property int chargingSoundHandle: -1
                        property color fillColor: modelData.color
                        property real weight: modelData.weight
                        property string cmd: modelData.cmd
                        property string icon: modelData.icon

                        color: actionMa.containsMouse ? (ThemeBackend.surface2 !== undefined ? ThemeBackend.surface2 : Qt.lighter(ThemeBackend.surface1, 1.12)) : ThemeBackend.surface1
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }

                        scale: actionMa.pressed ? (0.98 - (0.01 * weight)) : (actionMa.containsMouse ? 1.02 : 1.0)
                        Behavior on scale {
                            NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                        }

                        Canvas {
                            id: actionWaveCanvas
                            anchors.fill: parent
                            visible: actionCapsule.fillLevel > 0.001
                            renderTarget: Canvas.Image
                            renderStrategy: Canvas.Immediate

                            property real wavePhase: 0.0
                            NumberAnimation on wavePhase {
                                running: actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                loops: Animation.Infinite
                                from: 0
                                to: Math.PI * 2
                                duration: 800
                            }

                            onWavePhaseChanged: requestPaint()

                            Connections {
                                target: actionCapsule
                                function onFillLevelChanged() { actionWaveCanvas.requestPaint() }
                                function onRadiusChanged() { actionWaveCanvas.requestPaint() }
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                if (actionCapsule.fillLevel <= 0.001) return;

                                var r = Math.min(actionCapsule.radius, Math.min(width, height) / 2);
                                var fillY = height * (1.0 - actionCapsule.fillLevel);

                                ctx.save();
                                ctx.beginPath();
                                ctx.moveTo(r, 0);
                                ctx.lineTo(width - r, 0);
                                ctx.arcTo(width, 0, width, r, r);
                                ctx.lineTo(width, height - r);
                                ctx.arcTo(width, height, width - r, height, r);
                                ctx.lineTo(r, height);
                                ctx.arcTo(0, height, 0, height - r, r);
                                ctx.lineTo(0, r);
                                ctx.arcTo(0, 0, r, 0, r);
                                ctx.closePath();
                                ctx.clip();

                                ctx.beginPath();
                                ctx.moveTo(0, fillY);
                                if (actionCapsule.fillLevel < 0.99) {
                                    var waveAmp = Scaler.s(8) * Math.sin(actionCapsule.fillLevel * Math.PI);
                                    var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                    var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                    ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                    ctx.lineTo(width, height);
                                    ctx.lineTo(0, height);
                                } else {
                                    ctx.lineTo(width, 0);
                                    ctx.lineTo(width, height);
                                    ctx.lineTo(0, height);
                                }
                                ctx.closePath();

                                ctx.fillStyle = actionCapsule.fillColor.toString();
                                ctx.fill();
                                ctx.restore();
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: actionCapsule.radius
                            color: "#ffffff"
                            opacity: actionCapsule.flashOpacity
                            PropertyAnimation on opacity {
                                id: cardFlashAnim
                                to: 0
                                duration: 500
                                easing.type: Easing.OutExpo
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: Scaler.s(16)
                            color: actionMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0
                            text: actionCapsule.icon
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }

                        Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: actionCapsule.height * actionCapsule.fillLevel
                            clip: true

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Scaler.s(16)
                                color: ThemeBackend.crust
                                text: actionCapsule.icon
                            }
                        }

                        MouseArea {
                            id: actionMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor

                            onPressed: {
                                if (!actionCapsule.triggered) {
                                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                        actionCapsule.chargingSoundHandle = -1;
                                    }
                                    if (typeof Sounds !== "undefined") {
                                        actionCapsule.chargingSoundHandle = Sounds.playUntilStopped("reusables/fillbutton/charge_loop.wav", 0.6, false);
                                    }
                                    drainAnim.stop();
                                    fillAnim.start();
                                }
                            }

                            onReleased: {
                                if (!actionCapsule.triggered && actionCapsule.fillLevel < 1.0) {
                                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                        actionCapsule.chargingSoundHandle = -1;
                                    }
                                    fillAnim.stop();
                                    drainAnim.start();
                                }
                            }

                            onCanceled: {
                                if (!actionCapsule.triggered) {
                                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                        actionCapsule.chargingSoundHandle = -1;
                                    }
                                    fillAnim.stop();
                                    drainAnim.start();
                                }
                            }
                        }

                        NumberAnimation {
                            id: fillAnim
                            target: actionCapsule
                            property: "fillLevel"
                            to: 1.0
                            duration: (550 * weight) * (1.0 - actionCapsule.fillLevel)
                            easing.type: Easing.InSine
                            onFinished: {
                                actionCapsule.triggered = true;
                                actionCapsule.flashOpacity = 0.6;
                                if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                    Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                    actionCapsule.chargingSoundHandle = -1;
                                }
                                if (typeof Sounds !== "undefined") {
                                    Sounds.playSfx("reusables/fillbutton/button.wav");
                                }
                                cardFlashAnim.start();
                                drainAnim.start();
                                exitTimer.start();
                            }
                        }

                        NumberAnimation {
                            id: drainAnim
                            target: actionCapsule
                            property: "fillLevel"
                            to: 0.0
                            duration: 1500 * actionCapsule.fillLevel
                            easing.type: Easing.OutQuad
                        }

                        Timer {
                            id: exitTimer
                            interval: 450
                            onTriggered: {
                                if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                    Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                    actionCapsule.chargingSoundHandle = -1;
                                }
                                let scriptPath = Caching.serpantinumDir + "/scripts/system/" + (cmd === "sleep" ? "suspend.sh" : cmd + ".sh");
                                Quickshell.execDetached(["bash", scriptPath]);
                                actionCapsule.fillLevel = 0.0;
                                actionCapsule.triggered = false;
                            }
                        }

                        Component.onDestruction: {
                            if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                actionCapsule.chargingSoundHandle = -1;
                            }
                        }
                    }
                }
            }
        }
    }
}
