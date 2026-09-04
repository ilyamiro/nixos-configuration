import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../"
import "../reusables"

Item {
    id: window
    focus: true

    function s(val) {
        return Scaler.s(val);
    }

    function gotoTab(tabName) {
        if (!tabName) return;
        let t = tabName.toLowerCase();
        if (t === "output" || t === "outputs" || t === "sink" || t === "sinks") window.activeTab = "outputs";
        else if (t === "input" || t === "inputs" || t === "source" || t === "sources") window.activeTab = "inputs";
        else if (t === "app" || t === "apps" || t === "stream" || t === "streams") window.activeTab = "apps";
    }

    function resetAndPlayIntro() {
        introMain = 0;
        introHeader = 0;
        introContent = 0;
        introAnim.restart();
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: window.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
        } else {
            introAnim.stop();
            introMain = 0;
            introHeader = 0;
            introContent = 0;
        }
    }

    Component.onCompleted: {
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
        }
    }

    Shortcut {
        sequence: "Tab"
        enabled: window.visible
        onActivated: {
            if (window.activeTab === "outputs") window.activeTab = "inputs";
            else if (window.activeTab === "inputs") window.activeTab = "apps";
            else window.activeTab = "outputs";
        }
    }

    property string activeTab: "outputs"
    onActiveTabChanged: {
        let newIndex = (activeTab === "outputs") ? 0 : ((activeTab === "inputs") ? 1 : 2);
        if (tabSwitch.currentIndex !== newIndex) {
            tabSwitch.currentIndex = newIndex;
            if (typeof Sounds !== "undefined") {
                Sounds.playSfx(tabSwitch.switchSound);
            }
        }
    }

    readonly property color tabColor: {
        if (activeTab === "outputs") return ThemeBackend.blue;
        if (activeTab === "inputs") return ThemeBackend.mauve;
        return ThemeBackend.green;
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: window.visible
    }

    readonly property PwNode activeNode: {
        if (window.activeTab === "inputs") {
            return Audio.defaultSource || (Audio.inputs.length > 0 ? Audio.inputs[0] : null);
        } else if (window.activeTab === "apps") {
            return Audio.apps.length > 0 ? Audio.apps[0] : null;
        } else {
            return Audio.defaultSink || (Audio.outputs.length > 0 ? Audio.outputs[0] : null);
        }
    }

    readonly property string activeName: {
        if (!activeNode) return I18n.t("volumepopup.no_device");
        if (activeTab === "apps") return Audio.getNodeAppName(activeNode);
        return Audio.getNodeName(activeNode);
    }

    readonly property string activeDesc: {
        if (!activeNode) return "";
        if (activeTab === "apps") return I18n.t("volumepopup.master_output_volume");
        return Audio.getNodeSubDesc(activeNode);
    }

    readonly property int activeVol: activeNode && activeNode.audio ? Math.round(activeNode.audio.volume * 100) : 0
    readonly property bool activeMute: activeNode && activeNode.audio ? activeNode.audio.muted : false

    readonly property string activeIcon: {
        if (!activeNode) return "󰓃";
        if (activeTab === "inputs") return "󰍬";
        if (activeTab === "apps") return "󰎆";
        let desc = (Audio.getNodeName(activeNode) || "").toLowerCase();
        if (desc.indexOf("headset") !== -1 || desc.indexOf("headphones") !== -1) return "󰋎";
        return "󰓃";
    }

    property real introMain: 0
    property real introHeader: 0
    property real introContent: 0

    ParallelAnimation {
        id: introAnim
        running: false
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introHeader"; from: 0; to: 1.0; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }
    }

    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(20) * (1 - introMain) }

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(120)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(80)
                opacity: 0.06
                color: window.tabColor
                Behavior on color { ColorAnimation { duration: 800 } }
            }
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-120)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-80)
                opacity: 0.04
                color: Qt.lighter(window.tabColor, 1.3)
                Behavior on color { ColorAnimation { duration: 800 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(18)
                spacing: window.s(15)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(18)
                    opacity: introHeader
                    transform: Translate { y: window.s(25) * (1.0 - introHeader) }

                    Item {
                        Layout.preferredWidth: window.s(110)
                        Layout.preferredHeight: window.s(110)

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(6)
                            height: width
                            radius: ThemeBackend.borderRadius
                            color: "transparent"
                            border.color: window.activeMute ? ThemeBackend.red : window.tabColor
                            border.width: window.s(1.5)
                            z: -2

                            property real pulseOp: 0.0
                            property real pulseSc: 1.0
                            opacity: window.activeMute ? 0.0 : pulseOp
                            scale: pulseSc

                            Timer {
                                interval: 45
                                running: window.visible && (parent.opacity > 0.01 || !window.activeMute)
                                repeat: true
                                onTriggered: {
                                    var time = Date.now() / 1000;
                                    parent.pulseOp = 0.12 + Math.sin(time * 2.5) * 0.05;
                                    parent.pulseSc = 1.008 + Math.cos(time * 3.0) * 0.005;
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(10)
                            height: width
                            radius: ThemeBackend.borderRadius
                            color: window.activeMute ? ThemeBackend.red : window.tabColor
                            opacity: window.activeMute ? 0.15 : 0.06
                            z: -1
                            Behavior on color { ColorAnimation { duration: 300 } }

                            SequentialAnimation on scale {
                                loops: Animation.Infinite; running: window.visible
                                NumberAnimation { to: 1.015; duration: 2000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
                            }
                        }

                        MultiEffect {
                            source: centralCore
                            anchors.fill: centralCore
                            shadowEnabled: true
                            shadowColor: "#000000"
                            shadowOpacity: 0.5
                            shadowBlur: 1.2
                            shadowVerticalOffset: window.s(5)
                            z: -1
                        }

                        Rectangle {
                            id: centralCore
                            anchors.fill: parent
                            radius: ThemeBackend.borderRadius
                            color: ThemeBackend.base
                            border.color: window.activeMute ? ThemeBackend.red : Qt.lighter(window.tabColor, 1.1)
                            border.width: 2
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: 300 } }

                            Canvas {
                                id: orbWave
                                anchors.fill: parent

                                property real wavePhase: 0.0
                                NumberAnimation on wavePhase {
                                    running: window.visible && window.activeVol > 0 && window.activeVol < 100
                                    loops: Animation.Infinite
                                    from: 0; to: Math.PI * 2; duration: 1200
                                }
                                onWavePhaseChanged: requestPaint()

                                Connections {
                                    target: window
                                    function onActiveVolChanged() { orbWave.requestPaint() }
                                    function onActiveMuteChanged() { orbWave.requestPaint() }
                                    function onTabColorChanged() { orbWave.requestPaint() }
                                }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    if (window.activeVol <= 0) return;

                                    var fillRatio = window.activeVol / 100.0;
                                    var fillY = height * (1.0 - fillRatio);

                                    ctx.save();

                                    ctx.beginPath();
                                    ctx.roundedRect(0, 0, width, height, ThemeBackend.borderRadius, ThemeBackend.borderRadius);
                                    ctx.clip();

                                    ctx.beginPath();
                                    ctx.moveTo(0, fillY);

                                    if (fillRatio < 0.99) {
                                        var waveAmp = window.s(6) * Math.sin(fillRatio * Math.PI);
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

                                    var grad = ctx.createLinearGradient(0, 0, 0, height);
                                    if (window.activeMute) {
                                        grad.addColorStop(0, Qt.lighter(ThemeBackend.red, 1.15).toString());
                                        grad.addColorStop(1, ThemeBackend.red.toString());
                                    } else {
                                        grad.addColorStop(0, Qt.lighter(window.tabColor, 1.15).toString());
                                        grad.addColorStop(1, window.tabColor.toString());
                                    }
                                    ctx.fillStyle = grad;
                                    ctx.globalAlpha = 1.0;
                                    ctx.fill();
                                    ctx.restore();
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                width: parent.width * 0.85
                                height: parent.height * 0.4
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                fontSizeMode: Text.Fit
                                minimumPixelSize: window.s(8)
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: window.s(26)
                                color: window.activeMute ? ThemeBackend.red : ThemeBackend.text
                                text: window.activeMute ? I18n.t("volumepopup.mute") : window.activeVol + "%"
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Item {
                                id: waveClipItem
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right

                                property real fillRatio: window.activeVol / 100.0
                                property real waveAmp: fillRatio < 0.99 ? window.s(6) * Math.sin(fillRatio * Math.PI) : 0
                                property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(orbWave.wavePhase) - Math.cos(orbWave.wavePhase))
                                property real baseClipHeight: parent.height * fillRatio

                                height: Math.min(parent.height, Math.max(0, baseClipHeight - waveCenterOffset))
                                clip: true
                                visible: window.activeVol > 0

                                Text {
                                    width: centralCore.width * 0.85
                                    height: centralCore.height * 0.4
                                    x: (centralCore.width - width) / 2
                                    y: (centralCore.height - height) / 2 - (centralCore.height - waveClipItem.height)
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    fontSizeMode: Text.Fit
                                    minimumPixelSize: window.s(8)
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Black
                                    font.pixelSize: window.s(26)
                                    color: ThemeBackend.crust
                                    text: window.activeMute ? I18n.t("volumepopup.mute") : window.activeVol + "%"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (window.activeNode) {
                                        Audio.toggleMute(window.activeNode);
                                    }
                                }
                                onWheel: (wheel) => {
                                    if (!window.activeNode) return;
                                    let delta = wheel.angleDelta.y > 0 ? 5 : -5;
                                    let newVol = Math.max(0, Math.min(Audio.maxVolume, window.activeVol + delta));
                                    if (newVol > 0 && window.activeMute) {
                                        Audio.toggleMute(window.activeNode);
                                    }
                                    Audio.setVolume(window.activeNode, newVol);
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: window.s(10)

                        ColumnLayout {
                            spacing: window.s(2)
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: window.s(17)
                                color: ThemeBackend.text
                                text: window.activeName
                            }
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(12)
                                color: ThemeBackend.subtext0
                                text: window.activeDesc
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(20)
                            spacing: window.s(10)

                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                size: window.s(26)
                                cornerRadius: window.s(8)
                                buttonIcon: window.activeMute || window.activeVol === 0 ? "󰖁" : (window.activeVol > 50 ? "󰕾" : "󰖀")
                                iconFontSize: window.s(15)
                                accentColor: ThemeBackend.surface1
                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : (window.activeMute ? ThemeBackend.overlay0 : ThemeBackend.subtext0)
                                onClicked: Audio.toggleMute(window.activeNode)
                            }

                            Draggable {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(16)
                                Layout.alignment: Qt.AlignVCenter
                                from: 0.0
                                to: Audio.maxVolume
                                value: window.activeVol
                                backgroundColor: ThemeBackend.surface1
                                accentColor: window.activeMute ? ThemeBackend.surface2 : window.tabColor
                                gradColor1: window.activeMute ? ThemeBackend.surface2 : window.tabColor
                                gradColor2: window.activeMute ? ThemeBackend.surface2 : Qt.lighter(window.tabColor, 1.05)
                                gradColor3: window.activeMute ? ThemeBackend.surface2 : Qt.lighter(window.tabColor, 1.10)
                                cornerRadius: window.s(5)
                                handleSize: window.s(18)

                                handleColor: window.activeMute ? ThemeBackend.overlay0 : Qt.lighter(window.tabColor, 1.15)
                                handleHoverColor: window.activeMute ? ThemeBackend.subtext0 : Qt.lighter(window.tabColor, 1.5)
                                handleDragColor: window.activeMute ? ThemeBackend.text : Qt.lighter(window.tabColor, 1.45)
                                handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                                onMoved: (val) => {
                                    let pct = Math.max(0, Math.min(Audio.maxVolume, Math.round(val)));
                                    if (pct > 0 && window.activeMute) Audio.toggleMute(window.activeNode);
                                    Audio.setVolume(window.activeNode, pct);
                                }
                            }

                            Text {
                                Layout.preferredWidth: window.s(32)
                                Layout.alignment: Qt.AlignVCenter
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                color: ThemeBackend.subtext0
                                text: window.activeVol + "%"
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                Switch {
                    id: tabSwitch
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(38)
                    options: [I18n.t("volumepopup.tabs.outputs"), I18n.t("volumepopup.tabs.inputs"), I18n.t("volumepopup.tabs.streams")]
                    currentIndex: 0
                    cornerRadius: ThemeBackend.borderRadius
                    baseColor: ThemeBackend.surface0
                    accentColor: window.tabColor
                    textColor: ThemeBackend.subtext0
                    activeTextColor: ThemeBackend.crust
                    fontPixelSize: window.s(12)
                    opacity: introHeader
                    transform: Translate { y: window.s(15) * (1.0 - introHeader) }

                    onValueChanged: function(index, value) {
                        if (index === 0) window.activeTab = "outputs";
                        else if (index === 1) window.activeTab = "inputs";
                        else window.activeTab = "apps";
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    opacity: introContent
                    transform: Translate { y: window.s(15) * (1.0 - introContent) }

                    ListView {
                        id: contentList
                        anchors.fill: parent
                        spacing: window.s(10)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutQuint }
                            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 400; easing.type: Easing.OutBack }
                        }
                        displaced: Transition {
                            SpringAnimation { property: "y"; spring: 3; damping: 0.2; mass: 0.2 }
                        }

                        model: window.activeTab === "outputs" ? Audio.outputs : (window.activeTab === "inputs" ? Audio.inputs : Audio.apps)

                        Item {
                            width: contentList.width; height: contentList.height
                            visible: contentList.count === 0
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(8)
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(28); color: ThemeBackend.surface2; text: "󰖁" }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(13); color: ThemeBackend.overlay0; text: I18n.t("volumepopup.no_active_streams") }
                            }
                        }

                        delegate: Rectangle {
                            id: delegateRoot
                            width: contentList.width

                            readonly property PwNode node: modelData
                            readonly property bool isActiveNode: window.activeTab === "outputs" ? (node === Audio.defaultSink) : (window.activeTab === "inputs" ? (node === Audio.defaultSource) : false)
                            readonly property int nodeVol: node && node.audio ? Math.round(node.audio.volume * 100) : 0
                            readonly property bool nodeMute: node && node.audio ? node.audio.muted : false
                            readonly property string nodeDesc: window.activeTab === "apps" ? Audio.getNodeAppName(node) : Audio.getNodeName(node)
                            readonly property string nodeNameStr: Audio.getNodeSubDesc(node)

                            property bool isLoaded: false
                            Timer {
                                id: delegateEntranceTimer
                                running: window.visible
                                interval: 40 + (index * 40)
                                onTriggered: delegateRoot.isLoaded = true
                            }

                            Connections {
                                target: window
                                function onVisibleChanged() {
                                    if (!window.visible) {
                                        delegateRoot.isLoaded = false;
                                    } else {
                                        delegateEntranceTimer.restart();
                                    }
                                }
                            }

                            Component.onCompleted: {
                                if (window.visible) {
                                    delegateEntranceTimer.restart();
                                }
                            }

                            height: isActiveNode ? window.s(52) : window.s(88)
                            Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                            opacity: isLoaded ? 1.0 : 0.0
                            transform: Translate { y: isLoaded ? 0 : window.s(12) }
                            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                            Behavior on transform { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                            radius: ThemeBackend.borderRadius

                            property bool isHovered: cardMa.containsMouse && !isActiveNode

                            color: isActiveNode ? window.tabColor : (isHovered ? ThemeBackend.surface1 : ThemeBackend.surface0)
                            border.color: isActiveNode ? window.tabColor : ThemeBackend.surface1
                            border.width: isActiveNode ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            Behavior on color { ColorAnimation { duration: 300 } }

                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: window.activeTab !== "apps"
                                cursorShape: window.activeTab !== "apps" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (window.activeTab !== "apps" && !delegateRoot.isActiveNode) {
                                        if (window.activeTab === "outputs") Audio.setDefaultOutput(delegateRoot.node);
                                        else if (window.activeTab === "inputs") Audio.setDefaultInput(delegateRoot.node);
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: window.s(12)
                                anchors.rightMargin: window.s(12)
                                anchors.topMargin: window.s(10)
                                anchors.bottomMargin: isActiveNode ? window.s(10) : window.s(12)
                                spacing: window.s(10)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(10)

                                    Text {
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                        color: isActiveNode ? ThemeBackend.crust : ThemeBackend.text
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        text: {
                                            if (window.activeTab === "inputs") return "󰍬";
                                            if (window.activeTab === "apps") return "󰎆";
                                            if (delegateRoot.nodeDesc.toLowerCase().indexOf("headset") !== -1 || delegateRoot.nodeDesc.toLowerCase().indexOf("headphones") !== -1) return "󰋎";
                                            return "󰓃";
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(2)
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(13)
                                            color: isActiveNode ? ThemeBackend.crust : ThemeBackend.text
                                            text: delegateRoot.nodeDesc
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(10.5)
                                            color: isActiveNode ? Qt.darker(ThemeBackend.crust, 1.5) : ThemeBackend.subtext0
                                            text: isActiveNode ? I18n.t("volumepopup.active_default") : delegateRoot.nodeNameStr
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: window.s(20)
                                    spacing: window.s(10)
                                    visible: !isActiveNode
                                    opacity: isActiveNode ? 0.0 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    IconButton {
                                        Layout.alignment: Qt.AlignVCenter
                                        size: window.s(24)
                                        cornerRadius: window.s(8)
                                        buttonIcon: delegateRoot.nodeMute || delegateRoot.nodeVol === 0 ? "󰖁" : (delegateRoot.nodeVol > 50 ? "󰕾" : "󰖀")
                                        iconFontSize: window.s(14)
                                        accentColor: ThemeBackend.surface1
                                        textColor: isHoveredOrHighlighted ? ThemeBackend.text : (delegateRoot.nodeMute ? ThemeBackend.overlay0 : ThemeBackend.subtext0)
                                        onClicked: Audio.toggleMute(delegateRoot.node)
                                    }

                                    Draggable {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: window.s(16)
                                        Layout.alignment: Qt.AlignVCenter
                                        from: 0.0
                                        to: Audio.maxVolume
                                        value: delegateRoot.nodeVol
                                        backgroundColor: ThemeBackend.surface1
                                        accentColor: delegateRoot.nodeMute ? ThemeBackend.surface2 : window.tabColor
                                        gradColor1: delegateRoot.nodeMute ? ThemeBackend.surface2 : window.tabColor
                                        gradColor2: delegateRoot.nodeMute ? ThemeBackend.surface2 : Qt.lighter(window.tabColor, 1.05)
                                        gradColor3: delegateRoot.nodeMute ? ThemeBackend.surface2 : Qt.lighter(window.tabColor, 1.10)
                                        cornerRadius: window.s(5)
                                        handleSize: window.s(18)

                                        handleColor: delegateRoot.nodeMute ? ThemeBackend.overlay0 : Qt.lighter(window.tabColor, 1.15)
                                        handleHoverColor: delegateRoot.nodeMute ? ThemeBackend.subtext0 : Qt.lighter(window.tabColor, 1.5)
                                        handleDragColor: delegateRoot.nodeMute ? ThemeBackend.text : Qt.lighter(window.tabColor, 1.45)
                                        handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                                        onMoved: (val) => {
                                            let pct = Math.max(0, Math.min(Audio.maxVolume, Math.round(val)));
                                            if (pct > 0 && delegateRoot.nodeMute) Audio.toggleMute(delegateRoot.node);
                                            Audio.setVolume(delegateRoot.node, pct);
                                        }
                                    }

                                    Text {
                                        Layout.preferredWidth: window.s(30)
                                        Layout.alignment: Qt.AlignVCenter
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                        color: ThemeBackend.subtext0
                                        text: delegateRoot.nodeVol + "%"
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
