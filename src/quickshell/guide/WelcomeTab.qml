import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../"
import "../reusables"

Item {
    id: welcomeTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex

    property bool revealed: false
    opacity: revealed ? 1.0 : 0.0
    property real slideY: revealed ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    function activateTab() {
        revealed = true;
        logoFillLevel = 0.0;
        logoFillAnim.restart();
    }

    onVisibleChanged: {
        if (visible) activateTab();
    }

    Component.onCompleted: {
        if (visible) activateTab();
    }

    property real titleWavePhase: 0.0
    NumberAnimation on titleWavePhase {
        running: welcomeTabRoot.visible
        loops: Animation.Infinite
        from: 0
        to: Math.PI * 2
        duration: 7000
    }

    component StartButtonContent : Item {
        id: bRoot
        property color textColor: ThemeBackend.blue
        property real fillLevel: 0.0
        property bool isHovered: false

        RowLayout {
            anchors.centerIn: parent
            spacing: rootObj.s(10)

            Text {
                id: iconText
                text: "󰐊"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: rootObj.s(18)
                color: bRoot.textColor
                Behavior on color { ColorAnimation { duration: 150 } }

                property real charNorm: 0.15
                property real bump: bRoot.fillLevel > 0.001 && bRoot.fillLevel < 0.999
                                    ? Math.exp(-Math.pow((bRoot.fillLevel - charNorm) * 12, 2))
                                    : 0.0

                transform: [
                    Translate { y: -iconText.bump * rootObj.s(2.5) },
                    Scale { origin.x: width / 2; origin.y: height / 2; xScale: 1.0 + iconText.bump * 0.08; yScale: 1.0 + iconText.bump * 0.08 }
                ]
            }

            Row {
                spacing: 0
                Repeater {
                    model: Array.from(I18n.t("guide.welcome.start_tutorial"))
                    Text {
                        id: charText
                        required property string modelData
                        required property int index

                        text: modelData === " " ? "\u00A0" : modelData
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: rootObj.s(14)

                        color: bRoot.textColor
                        Behavior on color { ColorAnimation { duration: 150 } }

                        property real charNorm: 0.25 + (index / 14) * 0.65
                        property real bump: bRoot.fillLevel > 0.001 && bRoot.fillLevel < 0.999
                                            ? Math.exp(-Math.pow((bRoot.fillLevel - charNorm) * 12, 2))
                                            : 0.0

                        transform: [
                            Translate { y: -charText.bump * rootObj.s(2.5) },
                            Scale { origin.x: width / 2; origin.y: height / 2; xScale: 1.0 + charText.bump * 0.08; yScale: 1.0 + charText.bump * 0.08 }
                        ]
                    }
                }
            }
        }
    }

    Connections {
        target: rootObj
        function onActivationCounterChanged() {
            if (welcomeTabRoot.visible) {
                activateTab();
            }
        }
    }

    property real logoFillLevel: 0.0

    NumberAnimation {
        id: logoFillAnim
        target: welcomeTabRoot
        property: "logoFillLevel"
        from: 0.0
        to: 1.15
        duration: 6500
        easing.type: Easing.OutCubic
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: rootObj.s(25)

        Item {
            id: logoContainer
            Layout.alignment: Qt.AlignHCenter
            width: rootObj.s(240)
            height: rootObj.s(240)

            Item {
                id: paddedMaskSource
                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.smooth: true

                Image {
                    anchors.centerIn: parent
                    width: rootObj.s(210)
                    height: rootObj.s(210)
                    source: "file://" + rootObj.appPaths.serpantinumDir + "/assets/logo.svg"
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    antialiasing: true
                }
            }

            Item {
                id: logoColorBlock
                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.smooth: true

                Rectangle { anchors.fill: parent; color: ThemeBackend.text }

                Canvas {
                    id: logoWaveCanvas
                    anchors.fill: parent

                    property real wavePhase: 0.0
                    NumberAnimation on wavePhase {
                        running: welcomeTabRoot.visible && welcomeTabRoot.logoFillLevel < 1.14
                        loops: Animation.Infinite
                        from: 0; to: Math.PI * 2; duration: 4500
                    }

                    onWavePhaseChanged: requestPaint()
                    Connections {
                        target: welcomeTabRoot
                        function onLogoFillLevelChanged() { logoWaveCanvas.requestPaint() }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        var prog = welcomeTabRoot.logoFillLevel;
                        if (prog <= 0.001) return;

                        function drawWaterWipe(p, colorStr, ampMult, phaseOffset, waveCount) {
                            if (p <= 0.0) return;
                            if (p >= 1.0) {
                                ctx.fillStyle = colorStr;
                                ctx.fillRect(0, 0, width, height);
                                return;
                            }

                            var fillY = height * (1.0 - p);
                            var baseAmp = rootObj.s(12) * Math.sin(p * Math.PI) * ampMult;

                            ctx.beginPath();
                            ctx.moveTo(0, height);
                            ctx.lineTo(0, fillY);

                            var segments = 80;
                            var localPhase = wavePhase + phaseOffset;

                            for (var i = 0; i <= segments; i++) {
                                var x = (i / segments) * width;
                                var waveHeight = 0;

                                for (var w = 1; w <= waveCount; w++) {
                                    var frequency = w * 1.5;
                                    var wAmp = baseAmp * (1.0 - (w - 1) * 0.3);
                                    waveHeight += Math.sin(localPhase * frequency + x * 0.015 * frequency) * wAmp;
                                }

                                var y = fillY + waveHeight * 0.5;
                                ctx.lineTo(x, y);
                            }

                            ctx.lineTo(width, height);
                            ctx.closePath();
                            ctx.fillStyle = colorStr;
                            ctx.fill();
                        }

                        var speedFact = 1.15;
                        var p1 = Math.max(0.0, Math.min(1.0, prog * speedFact));
                        var p2 = Math.max(0.0, Math.min(1.0, (prog - 0.1) * speedFact));
                        var p3 = Math.max(0.0, Math.min(1.0, (prog - 0.2) * speedFact));

                        var baseColor = ThemeBackend.mauve;
                        drawWaterWipe(p1, Qt.darker(baseColor, 2.2).toString(), 1.5, 0.0, 3);
                        drawWaterWipe(p2, Qt.darker(baseColor, 1.6).toString(), 1.2, 0.8, 3);
                        drawWaterWipe(p3, baseColor.toString(), 0.9, 1.6, 3);
                    }
                }
            }

            MultiEffect {
                source: logoColorBlock
                anchors.fill: parent
                maskEnabled: true
                maskSource: paddedMaskSource
                autoPaddingEnabled: false
                shadowEnabled: true
                shadowColor: ThemeBackend.mauve
                shadowBlur: 1.0
                shadowOpacity: 0.45
                shadowVerticalOffset: 0
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: rootObj.s(4)

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 0

                property string mainTitle: I18n.t("guide.about.title")
                property string verText: " v" + (Updater.localVersion !== "..." ? Updater.localVersion : (rootObj.dotsVersion !== "Loading..." && rootObj.dotsVersion !== I18n.t("guide.about.loading") ? rootObj.dotsVersion : "2.0.0"))
                property string fullText: mainTitle + verText

                Repeater {
                    model: Array.from(parent.fullText)
                    Text {
                        required property string modelData
                        required property int index

                        text: modelData === " " ? "\u00A0" : modelData
                        font.family: ThemeBackend.fontFamily
                        font.weight: index < 11 ? Font.Black : Font.Bold
                        font.pixelSize: index < 11 ? rootObj.s(32) : rootObj.s(14)
                        color: index < 11 ? ThemeBackend.text : ThemeBackend.subtext0

                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: index < 11 ? 0 : rootObj.s(4)

                        transform: Translate {
                            y: Math.sin(welcomeTabRoot.titleWavePhase - index * 0.35) * rootObj.s(2.5)
                        }
                    }
                }
            }

            Text {
                text: I18n.t("guide.welcome.by_author", { author: "ilyamiro" })
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(14)
                color: ThemeBackend.subtext0
                Layout.alignment: Qt.AlignHCenter
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: rootObj.s(16)

            ClickButton {
                id: aboutBtn
                Layout.preferredWidth: rootObj.s(130)
                Layout.preferredHeight: rootObj.s(48)
                horizontalPadding: rootObj.s(12)
                cornerRadius: rootObj.s(12)
                buttonText: I18n.t("guide.welcome.about")
                textFontSize: rootObj.s(14)
                buttonIcon: ""
                iconFontSize: rootObj.s(16)
                accentColor: ThemeBackend.surface0
                textColor: ThemeBackend.text

                onTriggered: rootObj.gotoTab("About")
            }
        }
    }
}
