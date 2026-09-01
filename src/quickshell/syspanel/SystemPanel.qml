import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "../"
import "../reusables"
import "../notifications"

Item {
    id: root
    focus: true

    function s(val) {
        return Scaler.s(val);
    }

    readonly property string barPosition: {
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.position !== undefined) {
            return Config.rawSettings.bar.position;
        }
        return "top";
    }

    readonly property bool isLeftAnchored: barPosition === "right"

    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : SystemInfo.isDesktop

    readonly property real boxRadius: Math.min(ThemeBackend.borderRadius, root.s(20))
    readonly property real cardRadius: Math.min(ThemeBackend.borderRadius, root.s(14))

    readonly property color briColor: Qt.lighter(ThemeBackend.mauve, 1.1)
    readonly property color volColor: Qt.lighter(ThemeBackend.sapphire, 1.5)
    readonly property color profileColor: Qt.lighter(ThemeBackend.blue, 1.55)
    readonly property int batCapacity: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0

    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)

    readonly property string batStatus: {
        if (!UPower.displayDevice.ready) return "Unknown";
        switch (UPower.displayDevice.state) {
            case UPowerDeviceState.FullyCharged: return "Fully Charged";
            case UPowerDeviceState.Charging: return "Charging";
            case UPowerDeviceState.Discharging: return "Discharging";
            default: return "Unknown";
        }
    }

    readonly property int batHours: {
        if (!UPower.displayDevice.ready) return 0;
        let secs = isCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty;
        return Math.floor(secs / 3600);
    }

    readonly property int batMins: {
        if (!UPower.displayDevice.ready) return 0;
        let secs = isCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty;
        return Math.round((secs % 3600) / 60);
    }

    readonly property string batTimeLabel: {
        if (!UPower.displayDevice.ready || (batHours === 0 && batMins === 0) || batCapacity === 100) return "";
        if (UPower.displayDevice.state === UPowerDeviceState.Charging) return I18n.t("syspanel.battery.until_full");
        if (UPower.displayDevice.state === UPowerDeviceState.Discharging) return I18n.t("syspanel.battery.remaining");
        return "";
    }

    readonly property string powerProfile: {
        switch (PowerProfiles.profile) {
            case PowerProfile.Performance: return "performance";
            case PowerProfile.PowerSaver: return "power-saver";
            default: return "balanced";
        }
    }

    readonly property real sysVolume: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    readonly property bool sysMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false

    property real sysBrightness: 0

    property bool wifiRadioEnabled: Networking.wifiEnabled
    property bool btRadioEnabled: Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)

    property bool isDraggingVol: false
    property bool isDraggingBri: false
    property bool usesDdcBrightness: false

    property bool btStateBeforeAirplane: false
    property bool wifiStateBeforeAirplane: true

    property bool canHibernate: false

    readonly property color batColorFlat: {
        if (!UPower.displayDevice.ready) return ThemeBackend.blue;
        if (isCharging) return ThemeBackend.green;
        if (batCapacity <= 20) return ThemeBackend.red;
        return ThemeBackend.blue;
    }

    property real animCapacity: 0
    Behavior on animCapacity { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }

    onBatCapacityChanged: {
        animCapacity = batCapacity;
    }

    onSysVolumeChanged: {
        if (typeof volSlider !== "undefined" && volSlider && !root.isDraggingVol && volSlider.value !== sysVolume) {
            volSlider.value = sysVolume;
        }
    }

    onSysBrightnessChanged: {
        if (typeof briSlider !== "undefined" && briSlider && !root.isDraggingBri && briSlider.value !== sysBrightness) {
            briSlider.value = sysBrightness;
        }
    }

    Process {
        id: hibernateCheck
        running: false
        command: ["bash", Caching.serpantinumDir + "/scripts/system/can_hibernate.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                root.canHibernate = (out === "yes");
            }
        }
    }

    property real introContent: 0.0
    property real introTop: 0.0
    property real introCore: 0.0
    property real introSliders: 0.0
    property real introNotifs: 0.0
    property real introActions: 0.0

    function resetAndPlayIntro() {
        introContent = 0.0;
        introTop = 0.0;
        introCore = 0.0;
        introSliders = 0.0;
        introNotifs = 0.0;
        introActions = 0.0;
        closeSequence.stop();
        startupSequence.restart();
    }

    onVisibleChanged: {
        NotificationManager.sysPanelOpen = visible;
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();

            animCapacity = batCapacity;
            if (typeof waveCanvas !== "undefined" && waveCanvas) {
                waveCanvas.requestPaint();
            }

            if (typeof volSlider !== "undefined" && volSlider && !root.isDraggingVol) {
                volSlider.value = root.sysVolume;
            }

            if (nightLightBtn) nightLightBtn.updateState();
            if (coffeeBtn) coffeeBtn.updateState();

            hibernateCheck.running = false;
            hibernateCheck.running = true;

            briPollerTimer.stop();
            briPoller.running = false;
            briPoller.running = true;
        } else {
            briPollerTimer.stop();
            briPoller.running = false;
            startupSequence.stop();
            closeSequence.stop();
        }
    }

    Timer {
        id: focusTimer
        interval: 50
        running: false
        repeat: false
        onTriggered: root.forceActiveFocus()
    }

    Timer {
        id: volSyncDelay
        interval: 800
        repeat: false
        onTriggered: root.isDraggingVol = false
    }

    Timer {
        id: briSyncDelay
        interval: 800
        repeat: false
        onTriggered: root.isDraggingBri = false
    }

    Component.onCompleted: {
        if (visible) {
            NotificationManager.sysPanelOpen = true;
            if (nightLightBtn) nightLightBtn.updateState();
            if (coffeeBtn) coffeeBtn.updateState();
            resetAndPlayIntro();
            focusTimer.start();
            briPoller.running = true;
            hibernateCheck.running = true;
            animCapacity = batCapacity;
        }
    }

    Component.onDestruction: {
        NotificationManager.sysPanelOpen = false;
        briPollerTimer.stop();
    }

    Timer {
        id: briPollerTimer
        interval: root.usesDdcBrightness ? 10000 : 1500
        repeat: false
        onTriggered: {
            if (root.visible) briPoller.running = true;
        }
    }

    Process {
        id: briBackend
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "backend"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.usesDdcBrightness = this.text.trim() === "ddc"
        }
    }

    Process {
        id: briPoller
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                if (out !== "" && !root.isDraggingBri) {
                    root.sysBrightness = parseInt(out) || 0;
                }
                if (root.visible) briPollerTimer.start();
            }
        }
    }

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introContent"; to: 1.0; duration: 600; easing.type: Easing.OutQuart }

        SequentialAnimation {
            PauseAnimation { duration: 50 }
            NumberAnimation { target: root; property: "introTop"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: root; property: "introSliders"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introNotifs"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: root; property: "introActions"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: root; property: "introCore"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
        }
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation {
            NumberAnimation { target: root; property: "introContent"; to: 0.0; duration: 500; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "introTop"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "introSliders"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "introNotifs"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "introActions"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "introCore"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
        }
        ScriptAction {
            script: {
                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        closeSequence.start();
        event.accepted = true;
    }

    component BatteryContent : Item {
        id: bRoot
        property color contentTextColor: ThemeBackend.text
        property color iconColor: root.batColorFlat

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.s(20)
            anchors.rightMargin: root.s(20)
            spacing: root.s(16)

            Text {
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(32)
                color: bRoot.iconColor
                text: root.isCharging ? "󰂄" : (root.batCapacity > 20 ? "󰁹" : "󰂃")
                Behavior on color { ColorAnimation { duration: 400 } }
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                spacing: root.s(2)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(20)
                    color: bRoot.contentTextColor
                    text: Math.round(root.animCapacity) + "%"
                    Behavior on color { ColorAnimation { duration: 400 } }
                }

                Text {
                    property string timeString: {
                        if (root.batStatus === "Fully Charged") return I18n.t("syspanel.battery.fully_charged");
                        if (root.batStatus === "Charging") {
                            if (root.batHours === 0 && root.batMins === 0) return I18n.t("syspanel.battery.charging");
                            return I18n.t("syspanel.battery.charging_time", { hours: root.batHours, mins: root.batMins });
                        }
                        if (root.batHours === 0 && root.batMins === 0) return I18n.t("syspanel.battery.discharging");
                        return I18n.t("syspanel.battery.left_time", { hours: root.batHours, mins: root.batMins });
                    }

                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(10)
                    color: bRoot.contentTextColor === ThemeBackend.crust ? Qt.alpha(ThemeBackend.crust, 0.85) : (root.isCharging ? ThemeBackend.green : ThemeBackend.subtext0)
                    text: timeString
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    component QuickActionBtn : Rectangle {
        id: qaBtn
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: root.cardRadius

        property bool isActive: false
        property string iconText: ""
        property color activeColor: ThemeBackend.blue

        signal leftClicked()
        signal rightClicked()

        color: isActive ? activeColor : (qaMa.containsMouse ? ThemeBackend.surface1 : Qt.darker(ThemeBackend.surface0, 1.04))
        Behavior on color { ColorAnimation { duration: 150 } }

        scale: qaMa.pressed ? 0.95 : (qaMa.containsMouse ? 1.01 : 1.0)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }

        Text {
            anchors.centerIn: parent
            font.family: "Iosevka Nerd Font"
            font.pixelSize: root.s(22)
            color: qaBtn.isActive ? ThemeBackend.crust : (qaMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
            text: qaBtn.iconText
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: qaMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) qaBtn.rightClicked();
                else qaBtn.leftClicked();
            }
        }
    }

    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.97)
        radius: Math.min(ThemeBackend.borderRadius, root.s(28))
        border.width: 0
        clip: true
        opacity: root.introContent
        transform: Translate { x: (root.isLeftAnchored ? -root.s(75) : root.s(75)) * (1.0 - root.introContent) }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: root.isLeftAnchored ? parent.left : undefined
            anchors.right: root.isLeftAnchored ? undefined : parent.right
            width: sidebarPanel.radius + root.s(2)
            color: sidebarPanel.color
            visible: sidebarPanel.radius > 0
        }

        Item {
            anchors.fill: parent
            scale: 0.96 + (0.04 * root.introContent)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(8)
                spacing: root.s(5)

                Rectangle {
                    id: userBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(54)
                    Layout.maximumHeight: root.s(54)
                    radius: root.boxRadius
                    color: Qt.darker(ThemeBackend.surface0, 1.04)

                    opacity: root.introTop
                    transform: [
                        Translate { y: root.s(-20) * (1.0 - root.introTop) },
                        Scale { origin.x: userBox.width / 2; origin.y: userBox.height / 2; xScale: 0.95 + (0.05 * root.introTop); yScale: 0.95 + (0.05 * root.introTop) }
                    ]

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: root.s(10)
                        spacing: root.s(10)

                        ImageBox {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: root.s(34)
                            Layout.preferredHeight: root.s(34)
                            size: root.s(34)
                            cornerRadius: root.s(8)
                            imageRadius: root.s(8)
                            source: SystemInfo.avatarPath !== "" ? "file://" + SystemInfo.avatarPath : ""
                            backgroundColor: SystemInfo.avatarPath === "" ? ThemeBackend.surface1 : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(18)
                                color: ThemeBackend.text
                                visible: SystemInfo.avatarPath === ""
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            spacing: 0

                            Text {
                                text: SystemInfo.username !== "" ? SystemInfo.username : I18n.t("syspanel.user.default_name")
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: root.s(15)
                                color: ThemeBackend.text
                            }

                            Text {
                                text: SystemInfo.osName !== "" ? SystemInfo.osName : I18n.t("syspanel.user.default_os")
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Medium
                                font.pixelSize: root.s(10)
                                color: ThemeBackend.subtext0
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ClickButton {
                            id: logoutBtn
                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                            Layout.preferredWidth: root.s(92)
                            Layout.preferredHeight: root.s(34)
                            horizontalPadding: root.s(10)
                            cornerRadius: root.s(12)
                            buttonText: I18n.t("syspanel.user.logout")
                            textFontSize: root.s(11)
                            buttonIcon: "󰍃"
                            iconFontSize: root.s(14)
                            accentColor: ThemeBackend.surface2
                            textColor: ThemeBackend.text

                            Timer {
                                id: logoutOpenTimer
                                interval: 150
                                onTriggered: {
                                    closeSequence.start();
                                    Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/system/exit.sh"]);
                                    Quickshell.execDetached(["sh", "-c", "echo 'close' > " + Caching.runDir + "/widget_state"]);
                                }
                            }

                            onTriggered: {
                                logoutOpenTimer.start();
                            }
                        }
                    }
                }

                Rectangle {
                    id: slidersBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: slidersCol.implicitHeight + root.s(20)
                    Layout.maximumHeight: slidersCol.implicitHeight + root.s(20)
                    radius: root.boxRadius
                    color: Qt.darker(ThemeBackend.surface0, 1.04)

                    opacity: root.introSliders
                    transform: [
                        Translate { y: root.s(20) * (1.0 - root.introSliders) },
                        Scale { origin.x: slidersBox.width / 2; origin.y: slidersBox.height / 2; xScale: 0.95 + (0.05 * root.introSliders); yScale: 0.95 + (0.05 * root.introSliders) }
                    ]

                    ColumnLayout {
                        id: slidersCol
                        anchors.fill: parent
                        anchors.margins: root.s(12)
                        spacing: root.s(6)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)

                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                size: root.s(26)
                                iconOffsetX: -1
                                cornerRadius: root.s(8)
                                buttonIcon: root.sysMuted || root.sysVolume === 0 ? "󰖁" : (root.sysVolume > 50 ? "󰕾" : "󰖀")
                                iconFontSize: root.s(15)
                                accentColor: ThemeBackend.surface1
                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : (root.sysMuted ? ThemeBackend.overlay0 : root.volColor)
                                onClicked: {
                                    if (Audio.defaultSink) {
                                        Audio.toggleMute(Audio.defaultSink);
                                    }
                                }
                            }

                            Timer {
                                id: volCmdThrottle
                                interval: 50
                                property int targetPct: -1
                                onTriggered: {
                                    if (targetPct >= 0) {
                                        if (targetPct > 0 && root.sysMuted) {
                                            if (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) {
                                                Audio.toggleMute(Audio.defaultSink);
                                            }
                                        }
                                        if (Audio.defaultSink) {
                                            Audio.setVolume(Audio.defaultSink, targetPct);
                                        }
                                        targetPct = -1;
                                    }
                                }
                            }

                            Draggable {
                                id: volSlider
                                Layout.fillWidth: true
                                implicitHeight: root.s(18)
                                from: 0.0
                                to: 100.0
                                stepSize: 1.0
                                showValueBubble: true
                                valueFormatter: function(v) { return Math.round(v) }
                                value: root.sysVolume
                                backgroundColor: ThemeBackend.surface1
                                accentColor: root.sysMuted ? ThemeBackend.surface2 : root.volColor
                                gradColor1: root.sysMuted ? ThemeBackend.surface2 : root.volColor
                                gradColor2: root.sysMuted ? ThemeBackend.surface2 : Qt.lighter(root.volColor, 1.05)
                                gradColor3: root.sysMuted ? ThemeBackend.surface2 : Qt.lighter(root.volColor, 1.10)
                                cornerRadius: root.s(6)
                                handleSize: root.s(22)

                                handleColor: root.sysMuted ? ThemeBackend.overlay0 : Qt.lighter(root.volColor, 1.15)
                                handleHoverColor: root.sysMuted ? ThemeBackend.subtext0 : Qt.lighter(root.volColor, 1.5)
                                handleDragColor: root.sysMuted ? ThemeBackend.text : Qt.lighter(root.volColor, 1.45)
                                handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                                onDragStarted: {
                                    volSyncDelay.stop();
                                    root.isDraggingVol = true;
                                }
                                onDragFinished: {
                                    if (volCmdThrottle.running && volCmdThrottle.targetPct >= 0) {
                                        volCmdThrottle.stop();
                                        if (volCmdThrottle.targetPct > 0 && root.sysMuted) {
                                            if (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) {
                                                Audio.toggleMute(Audio.defaultSink);
                                            }
                                        }
                                        if (Audio.defaultSink) {
                                            Audio.setVolume(Audio.defaultSink, volCmdThrottle.targetPct);
                                        }
                                        volCmdThrottle.targetPct = -1;
                                    }
                                    volSyncDelay.restart();
                                }
                                onMoved: (val) => {
                                    let pct = Math.max(0, Math.min(100, Math.round(val)));
                                    volSlider.value = pct;
                                    volCmdThrottle.targetPct = pct;
                                    if (!volCmdThrottle.running) volCmdThrottle.start();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)

                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                size: root.s(26)
                                cornerRadius: root.s(8)
                                iconOffsetX: -3
                                buttonIcon: root.sysBrightness > 66 ? "󰃠" : (root.sysBrightness > 33 ? "󰃟" : "󰃞")
                                iconFontSize: root.s(15)
                                accentColor: ThemeBackend.surface1
                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : root.briColor
                                onClicked: {
                                    briCmdThrottle.stop();
                                    briCmdThrottle.targetPct = -1;
                                    let target = root.sysBrightness > 0 ? 0 : 100;
                                    root.sysBrightness = target;
                                    Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", target.toString()]);
                                }
                            }

                            Timer {
                                id: briCmdThrottle
                                interval: 400
                                property int targetPct: -1
                                onTriggered: {
                                    if (targetPct >= 0) {
                                        Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", targetPct.toString()]);
                                        targetPct = -1;
                                    }
                                }
                            }

                            Draggable {
                                id: briSlider
                                Layout.fillWidth: true
                                implicitHeight: root.s(18)
                                from: 0.0
                                to: 100.0
                                stepSize: 1.0
                                showValueBubble: true
                                valueFormatter: function(v) { return Math.round(v) }
                                value: root.sysBrightness
                                backgroundColor: ThemeBackend.surface1
                                accentColor: root.briColor
                                gradColor1: root.briColor
                                gradColor2: Qt.lighter(root.briColor, 1.05)
                                gradColor3: Qt.lighter(root.briColor, 1.10)
                                cornerRadius: root.s(6)
                                handleSize: root.s(22)

                                handleColor: Qt.lighter(root.briColor, 1.15)
                                handleHoverColor: Qt.lighter(root.briColor, 1.3)
                                handleDragColor: Qt.lighter(root.briColor, 1.45)
                                handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                                onDragStarted: {
                                    briSyncDelay.stop();
                                    root.isDraggingBri = true;
                                }
                                onDragFinished: {
                                    if (briCmdThrottle.targetPct >= 0) {
                                        briCmdThrottle.stop();
                                        Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", briCmdThrottle.targetPct.toString()]);
                                        briCmdThrottle.targetPct = -1;
                                    }
                                    briSyncDelay.restart();
                                }
                                onMoved: (val) => {
                                    let pct = Math.max(0, Math.min(100, Math.round(val)));
                                    root.sysBrightness = pct;
                                    briSlider.value = pct;
                                    briCmdThrottle.targetPct = pct;
                                    if (!briSlider.isDragging) briCmdThrottle.restart();
                                }
                            }
                        }
                    }
                }

                Item {
                    id: quickActionsBox
                    z: 5
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(73)
                    Layout.maximumHeight: root.s(73)

                    opacity: root.introSliders
                    transform: [
                        Translate { y: root.s(20) * (1.0 - root.introSliders) },
                        Scale { origin.x: quickActionsBox.width / 2; origin.y: quickActionsBox.height / 2; xScale: 0.95 + (0.05 * root.introSliders); yScale: 0.95 + (0.05 * root.introSliders) }
                    ]

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.s(6)

                        QuickActionBtn {
                            id: nightLightBtn
                            iconText: "󰖔"
                            activeColor: ThemeBackend.peach

                            function updateState() {
                                let ds = Config.getSetting("display", {"monitors": {}});
                                let mons = ds.monitors || {};
                                let anyEnabled = false;
                                for (let mName in mons) {
                                    if (mons[mName].enabled) {
                                        anyEnabled = true;
                                        break;
                                    }
                                }
                                isActive = anyEnabled;
                            }

                            Component.onCompleted: updateState()

                            Connections {
                                target: Config
                                function onSettingsLoaded() {
                                    nightLightBtn.updateState();
                                }
                            }

                            onLeftClicked: {
                                Sounds.playSfx("system/quick_click.wav");
                                isActive = !isActive;
                                let ds = Config.getSetting("display", {"monitors": {}});
                                let mons = ds.monitors || {};
                                let temp = 50;
                                for (let mName in mons) {
                                    let mSet = mons[mName] || {};
                                    if (mSet.temperature !== undefined) {
                                        temp = mSet.temperature;
                                    }
                                    let kelvin = Math.round(6500 - (temp / 100) * (6500 - 2500));

                                    if (isActive) {
                                        Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/blue_light_filter.sh", "set", kelvin.toString(), mName]);
                                    } else {
                                        Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/blue_light_filter.sh", "reset", mName]);
                                    }
                                    mSet.enabled = isActive;
                                    mons[mName] = mSet;
                                }
                                ds.monitors = mons;
                                Config.setSetting("display", ds);
                            }

                            onRightClicked: {
                                closeSequence.start();
                                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "guide", "display"]);
                            }
                        }

                        QuickActionBtn {
                            id: coffeeBtn
                            iconText: "󰅶"
                            activeColor: Qt.tint(ThemeBackend.peach, "#5c3016")

                            function updateState() {
                                let idleObj = Config.getSetting("idle", {"manualInhibit": false});
                                isActive = Boolean(idleObj && idleObj.manualInhibit);
                            }

                            Component.onCompleted: updateState()

                            Connections {
                                target: Config
                                function onSettingsLoaded() {
                                    coffeeBtn.updateState();
                                }
                            }

                            onLeftClicked: {
                                Sounds.playSfx("system/quick_click.wav");
                                isActive = !isActive;
                                let idleObj = Object.assign({}, Config.getSetting("idle", {}));
                                idleObj.manualInhibit = isActive;
                                Config.setSetting("idle", idleObj);
                            }

                            onRightClicked: {
                                closeSequence.start();
                                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "guide", "idle"]);
                            }
                        }

                        QuickActionBtn {
                            iconText: isActive ? "󰤨" : "󰤮"
                            activeColor: ThemeBackend.blue
                            isActive: root.wifiRadioEnabled
                            onLeftClicked: {
                                Sounds.playSfx("system/quick_click.wav");
                                Networking.wifiEnabled = !Networking.wifiEnabled;
                            }
                            onRightClicked: {
                                closeSequence.start();
                                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "network", "wifi"]);
                            }
                        }

                        QuickActionBtn {
                            iconText: isActive ? "󰂯" : "󰂲"
                            activeColor: ThemeBackend.mauve
                            isActive: root.btRadioEnabled
                            onLeftClicked: {
                                Sounds.playSfx("system/quick_click.wav");
                                if (Bluetooth.defaultAdapter) {
                                    Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                                }
                            }
                            onRightClicked: {
                                closeSequence.start();
                                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "network", "bt"]);
                            }
                        }

                        QuickActionBtn {
                            iconText: "󰀝"
                            activeColor: ThemeBackend.red
                            isActive: !root.wifiRadioEnabled && !root.btRadioEnabled
                            onLeftClicked: {
                                Sounds.playSfx("system/quick_click.wav");
                                let enableAirplane = !isActive;
                                if (enableAirplane) {
                                    root.btStateBeforeAirplane = root.btRadioEnabled;
                                    root.wifiStateBeforeAirplane = root.wifiRadioEnabled;
                                    Networking.wifiEnabled = false;
                                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = false;
                                } else {
                                    let restoreWifi = root.wifiStateBeforeAirplane;
                                    let restoreBt = root.btStateBeforeAirplane;
                                    if (!restoreWifi && !restoreBt) {
                                        restoreWifi = true;
                                    }
                                    Networking.wifiEnabled = restoreWifi;
                                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = restoreBt;
                                }
                            }
                        }
                    }
                }

                NotificationBox {
                    id: notifsBox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: root.s(68)
                    cornerRadius: root.boxRadius
                    cardRadius: root.cardRadius
                    baseColor: Qt.darker(ThemeBackend.surface0, 1.04)
                    rootContext: root

                    opacity: root.introNotifs
                    transform: [
                        Translate { y: root.s(20) * (1.0 - root.introNotifs) },
                        Scale { origin.x: notifsBox.width / 2; origin.y: notifsBox.height / 2; xScale: 0.95 + (0.05 * root.introNotifs); yScale: 0.95 + (0.05 * root.introNotifs) }
                    ]
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(73)
                    Layout.maximumHeight: root.s(73)
                    spacing: root.s(6)

                    Repeater {
                        model: ListModel {
                            ListElement { cmd: "lock"; icon: ""; weight: 1.0 }
                            ListElement { cmd: "sleep"; icon: "ᶻ 𝗓 𝗓"; weight: 1.0 }
                            ListElement { cmd: "hibernate"; icon: "󰤄"; weight: 1.5 }
                            ListElement { cmd: "reboot"; icon: "󰑓"; weight: 2.5 }
                            ListElement { cmd: "poweroff"; icon: ""; weight: 3.5 }
                        }

                        delegate: Rectangle {
                            id: actionCapsule
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: root.boxRadius
                            clip: true

                            property bool isHibernate: cmd === "hibernate"
                            property bool isDisabled: isHibernate && !root.canHibernate
                            property bool showError: false
                            property int chargingSoundHandle: -1

                            opacity: root.introActions
                            transform: [
                                Translate { id: shakeTranslate; x: 0 },
                                Translate { y: root.s(30) * (1.0 - root.introActions) + (index * root.s(12) * (1.0 - root.introActions)) },
                                Scale { origin.x: actionCapsule.width / 2; origin.y: actionCapsule.height / 2; xScale: 0.90 + (0.10 * root.introActions); yScale: 0.90 + (0.10 * root.introActions) }
                            ]

                            color: (actionMa.containsMouse && !isDisabled) ? ThemeBackend.surface1 : Qt.darker(ThemeBackend.surface0, 1.04)
                            Behavior on color { ColorAnimation { duration: 200 } }

                            scale: (actionMa.pressed && !isDisabled) ? (0.98 - (0.01 * weight)) : ((actionMa.containsMouse && !isDisabled) ? 1.02 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                            property real fillLevel: 0.0
                            property bool triggered: false
                            property real flashOpacity: 0.0

                            Connections {
                                target: root
                                function onVisibleChanged() {
                                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                        actionCapsule.chargingSoundHandle = -1;
                                    }
                                    actionCapsule.fillLevel = 0.0;
                                    actionCapsule.triggered = false;
                                    actionCapsule.flashOpacity = 0.0;
                                    fillAnim.stop();
                                    drainAnim.stop();
                                }
                            }

                            SequentialAnimation {
                                id: shakeAnim
                                NumberAnimation { target: shakeTranslate; property: "x"; to: -root.s(3); duration: 50 }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: root.s(3); duration: 50 }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: -root.s(3); duration: 50 }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: root.s(3); duration: 50 }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 50 }
                                onStarted: actionCapsule.showError = true
                                onStopped: actionCapsule.showError = false
                            }

                            function triggerError() {
                                shakeAnim.stop();
                                shakeAnim.start();
                            }

                            Canvas {
                                id: actionWaveCanvas
                                anchors.fill: parent
                                visible: actionCapsule.fillLevel > 0.001
                                renderTarget: Canvas.Image
                                renderStrategy: Canvas.Immediate

                                property real wavePhase: 0.0
                                NumberAnimation on wavePhase {
                                    running: root.visible && actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                    loops: Animation.Infinite
                                    from: 0; to: Math.PI * 2; duration: 800
                                }
                                onWavePhaseChanged: requestPaint()
                                Connections { target: actionCapsule; function onFillLevelChanged() { actionWaveCanvas.requestPaint() } }
                                Connections { target: actionCapsule; function onRadiusChanged() { actionWaveCanvas.requestPaint() } }

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
                                        var waveAmp = root.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI);
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

                                    ctx.fillStyle = (cmd === "poweroff" || cmd === "hibernate" ? ThemeBackend.red : ThemeBackend.blue).toString();
                                    ctx.fill();
                                    ctx.restore();
                                }
                            }

                            Rectangle {
                                anchors.fill: parent; radius: actionCapsule.radius; color: "#ffffff"
                                opacity: actionCapsule.flashOpacity
                                PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: ThemeBackend.red
                                opacity: actionCapsule.showError ? 0.15 : 0.0
                                radius: actionCapsule.radius
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                z: 4
                            }

                            Text {
                                anchors.centerIn: parent
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(24)
                                color: isDisabled ? ThemeBackend.surface2 : (actionMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                text: icon
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Item {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: actionCapsule.height * actionCapsule.fillLevel
                                clip: true

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(24)
                                    color: ThemeBackend.crust
                                    text: icon
                                }
                            }

                            MouseArea {
                                id: actionMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: isDisabled ? Qt.ForbiddenCursor : (actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor)

                                onPressed: {
                                    if (isDisabled) {
                                        actionCapsule.triggerError();
                                        Quickshell.execDetached([
                                            "notify-send",
                                            "-a", I18n.t("syspanel.actions.system_name"),
                                            "-u", "normal",
                                            "-i", "dialog-warning",
                                            I18n.t("syspanel.actions.hibernate_error_title"),
                                            I18n.t("syspanel.actions.hibernate_error_body")
                                        ]);
                                    } else if (!actionCapsule.triggered) {
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
                                    if (!isDisabled && !actionCapsule.triggered && actionCapsule.fillLevel < 1.0) {
                                        if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                            Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                            actionCapsule.chargingSoundHandle = -1;
                                        }
                                        fillAnim.stop();
                                        drainAnim.start();
                                    }
                                }
                                onCanceled: {
                                    if (!isDisabled && !actionCapsule.triggered) {
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
                                id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0
                                duration: (550 * weight) * (1.0 - actionCapsule.fillLevel); easing.type: Easing.InSine
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
                                    closeSequence.start();
                                    exitTimer.start();
                                }
                            }

                            NumberAnimation {
                                id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0
                                duration: 1500 * actionCapsule.fillLevel; easing.type: Easing.OutQuad
                            }

                            Timer {
                                id: exitTimer; interval: 500
                                onTriggered: {
                                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                                        actionCapsule.chargingSoundHandle = -1;
                                    }
                                    let scriptPath = cmd === "lock" ? Caching.serpantinumDir + "/scripts/lock.sh" : Caching.serpantinumDir + "/scripts/system/" + (cmd === "sleep" ? "suspend.sh" : cmd + ".sh");
                                    Quickshell.execDetached(["bash", scriptPath]);
                                    Quickshell.execDetached(["sh", "-c", "echo 'close' > " + Caching.runDir + "/widget_state"]);

                                    actionCapsule.fillLevel = 0.0;
                                    actionCapsule.triggered = false;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: batteryBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isDesktop ? root.s(52) : root.s(72)
                    Layout.maximumHeight: Layout.preferredHeight
                    radius: root.isDesktop ? root.s(15) : root.boxRadius
                    color: root.isDesktop ? "transparent" : Qt.darker(ThemeBackend.surface0, 1.04)
                    clip: true

                    opacity: root.introCore
                    transform: [
                        Translate { y: root.s(15) * (1 - root.introCore) },
                        Scale { origin.x: batteryBox.width / 2; origin.y: batteryBox.height / 2; xScale: 0.95 + (0.05 * root.introCore); yScale: 0.95 + (0.05 * root.introCore) }
                    ]

                    property real fillLevel: root.animCapacity / 100
                    property real maxWaveAmp: root.isCharging ? root.s(9) : root.s(1.8)
                    property real waveAmp: (fillLevel < 0.99 && fillLevel > 0.01) ? maxWaveAmp * Math.sin(fillLevel * Math.PI) : 0

                    Canvas {
                        id: waveCanvas
                        anchors.fill: parent
                        visible: !root.isDesktop && batteryBox.fillLevel > 0.001
                        renderTarget: Canvas.Image
                        renderStrategy: Canvas.Immediate
                        property real wavePhase: 0.0
                        NumberAnimation on wavePhase {
                            running: root.visible && !root.isDesktop && batteryBox.fillLevel > 0.0 && batteryBox.fillLevel < 1.0
                            loops: Animation.Infinite
                            from: 0; to: Math.PI * 2; duration: root.isCharging ? 1200 : 3400
                        }

                        onWavePhaseChanged: requestPaint()
                        Connections { target: batteryBox; function onFillLevelChanged() { waveCanvas.requestPaint() } }
                        Connections { target: batteryBox; function onWaveAmpChanged() { waveCanvas.requestPaint() } }
                        Connections { target: root; function onBatColorFlatChanged() { waveCanvas.requestPaint() } }
                        Connections { target: root; function onIsChargingChanged() { waveCanvas.requestPaint() } }
                        Connections { target: batteryBox; function onRadiusChanged() { waveCanvas.requestPaint() } }
                        Connections {
                            target: UPower.displayDevice
                            function onReadyChanged() { waveCanvas.requestPaint() }
                            function onStateChanged() { waveCanvas.requestPaint() }
                            function onPercentageChanged() { waveCanvas.requestPaint() }
                        }
                        Connections {
                            target: root
                            function onVisibleChanged() {
                                if (root.visible) waveCanvas.requestPaint();
                            }
                        }

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            if (batteryBox.fillLevel <= 0.001) return;

                            var r = Math.min(batteryBox.radius, Math.min(width, height) / 2);
                            var currentW = width * batteryBox.fillLevel;

                            ctx.save();
                            ctx.beginPath();
                            ctx.moveTo(0, 0);
                            if (batteryBox.fillLevel < 0.99 && batteryBox.waveAmp > 0) {
                                var waveAmp = batteryBox.waveAmp;
                                if (currentW - waveAmp < 0) waveAmp = currentW;
                                var cp1x = currentW + Math.sin(wavePhase) * waveAmp;
                                var cp2x = currentW + Math.cos(wavePhase + Math.PI) * waveAmp;

                                ctx.lineTo(currentW, 0);
                                ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, currentW, height);
                                ctx.lineTo(0, height);
                            } else {
                                ctx.lineTo(currentW, 0);
                                ctx.lineTo(currentW, height);
                                ctx.lineTo(0, height);
                            }
                            ctx.closePath();
                            ctx.clip();

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

                            ctx.fillStyle = root.batColorFlat.toString();
                            ctx.fill();
                            ctx.restore();
                        }
                    }

                    BatteryContent {
                        anchors.fill: parent
                        contentTextColor: ThemeBackend.text
                        iconColor: root.batColorFlat
                        visible: !root.isDesktop
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: !root.isDesktop

                        property real phaseOffset: Math.sin(waveCanvas.wavePhase) - Math.cos(waveCanvas.wavePhase)
                        property real centerOffset: batteryBox.fillLevel > 0.01 && batteryBox.fillLevel < 0.99 ? 0.375 * batteryBox.waveAmp * phaseOffset : 0

                        width: Math.max(0, Math.min(parent.width, (parent.width * batteryBox.fillLevel) + centerOffset))
                        clip: true

                        BatteryContent {
                            width: batteryBox.width
                            height: batteryBox.height
                            contentTextColor: ThemeBackend.crust
                            iconColor: ThemeBackend.crust
                        }
                    }

                    Item {
                        id: profileSwitchWrapper
                        anchors.fill: root.isDesktop ? parent : undefined
                        anchors.right: root.isDesktop ? undefined : parent.right
                        anchors.verticalCenter: root.isDesktop ? undefined : parent.verticalCenter
                        anchors.rightMargin: root.isDesktop ? 0 : root.s(12)
                        implicitWidth: root.isDesktop ? parent.width : profileSwitch.implicitWidth
                        implicitHeight: profileSwitch.implicitHeight

                        Rectangle {
                            id: profileSwitchShadow
                            visible: !root.isDesktop
                            anchors.fill: parent
                            anchors.topMargin: root.s(1.5)
                            anchors.bottomMargin: -root.s(1.5)
                            radius: profileSwitch.cornerRadius
                            color: Qt.rgba(0, 0, 0, 0.25)
                        }

                        Switch {
                            id: profileSwitch
                            anchors.fill: parent
                            implicitWidth: root.isDesktop ? parent.width : (PowerProfiles.hasPerformanceProfile ? root.s(240) : root.s(162))
                            implicitHeight: root.isDesktop ? root.s(48) : root.s(52)
                            cornerRadius: root.s(15)
                            fontPixelSize: root.isDesktop ? root.s(14) : root.s(22)
                            options: {
                                if (root.isDesktop) {
                                    return PowerProfiles.hasPerformanceProfile
                                        ? ["󰓅 " + I18n.t("syspanel.profiles.performance"), "󰗑 " + I18n.t("syspanel.profiles.balanced"), "󰌪 " + I18n.t("syspanel.profiles.power_saver")]
                                        : ["󰗑 " + I18n.t("syspanel.profiles.balanced"), "󰌪 " + I18n.t("syspanel.profiles.power_saver")];
                                } else {
                                    return PowerProfiles.hasPerformanceProfile
                                        ? ["󰓅", "󰗑", "󰌪"]
                                        : ["󰗑", "󰌪"];
                                }
                            }
                            accentColor: root.profileColor
                            baseColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            currentIndex: {
                                if (PowerProfiles.hasPerformanceProfile) {
                                    if (root.powerProfile === "performance") return 0;
                                    if (root.powerProfile === "balanced") return 1;
                                    return 2;
                                } else {
                                    if (root.powerProfile === "balanced") return 0;
                                    return 1;
                                }
                            }

                            onValueChanged: (idx, val) => {
                                if (PowerProfiles.hasPerformanceProfile) {
                                    if (idx === 0) PowerProfiles.profile = PowerProfile.Performance;
                                    else if (idx === 1) PowerProfiles.profile = PowerProfile.Balanced;
                                    else PowerProfiles.profile = PowerProfile.PowerSaver;
                                } else {
                                    if (idx === 0) PowerProfiles.profile = PowerProfile.Balanced;
                                    else PowerProfiles.profile = PowerProfile.PowerSaver;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
