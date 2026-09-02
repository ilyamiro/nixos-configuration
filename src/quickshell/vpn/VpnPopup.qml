import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../reusables"
import "../"

// The VPN panel.
//
// Everything on screen comes from the controller: the shell asks a running
// core what it has and tells it what to change. It does not own the core, its
// configs or its subscriptions -- see Mihomo.qml for where that line is drawn
// and why.
Item {
    id: window
    focus: true

    function s(val) { return Scaler.s(val); }

    // Which group's members are listed. The primary one is what carries
    // traffic on an ordinary config; the rest are reachable through the tabs
    // when a config has them.
    property string viewGroup: ""
    readonly property var currentGroup: {
        if (window.viewGroup !== "") {
            const g = Mihomo.groupNamed(window.viewGroup);
            if (g) return g;
        }
        return Mihomo.primary || (Mihomo.groups.length > 0 ? Mihomo.groups[0] : null);
    }
    readonly property var nodeList: currentGroup ? (currentGroup.nodes || []) : []

    // Profiles are a second-order thing and stay folded: the nodes are what
    // the panel is for, and giving a list that gets touched once a month half
    // the height would be the wrong trade.
    property bool profilesOpen: false

    // Measure on arrival rather than on a button. The list is worth nothing
    // without the numbers, and probeDelaysIfStale only spends a round of
    // requests when some node in the group has never been measured -- so
    // reopening the panel, or flipping back to a tab already seen, is free.
    // Groups land asynchronously, so this hangs off the group becoming known
    // rather than off Component.onCompleted, which is too early.
    onCurrentGroupChanged: {
        if (window.visible && currentGroup) Mihomo.probeDelaysIfStale(currentGroup.name);
    }

    // Latency is a judgement, not a number: the thresholds are where a tunnel
    // stops being usable for a call, then for a page.
    function delayColor(ms) {
        if (ms === undefined || ms === null) return ThemeBackend.subtext0;
        if (ms < 150) return ThemeBackend.green;
        if (ms < 400) return ThemeBackend.yellow;
        return ThemeBackend.red;
    }
    function delayText(name) {
        if (!Mihomo.measurable(name)) return "";
        const d = Mihomo.delays[name];
        if (d === undefined) return "—";
        if (d === null) return I18n.t("vpn.delay_failed");
        return I18n.t("vpn.delay_ms", { ms: d });
    }

    // The panel may be built ahead of time and sit invisible in a preloader,
    // and waking the tunnel then would spend a traffic stream and a round of
    // requests on an answer nobody is looking at. Visibility is the signal,
    // not construction.
    function _wake() {
        if (!window.visible) return;
        Mihomo.refresh();
        Mihomo.checkTunDns();
        Mihomo.refreshProfiles();
        if (window.currentGroup) Mihomo.probeDelaysIfStale(window.currentGroup.name);
    }

    onVisibleChanged: {
        Mihomo.watched = window.visible;
        if (window.visible) window._wake();
    }

    Component.onCompleted: if (window.visible) { Mihomo.watched = true; window._wake(); }
    Component.onDestruction: Mihomo.watched = false

    // The footer's own line. A message from the core is a log line, not a
    // verdict the panel is passing, and it is labelled as such.
    readonly property bool footerBad: Mihomo.lastError !== ""
    readonly property string footerText: {
        if (Mihomo.lastError !== "") return I18n.t("vpn.core_says", { message: Mihomo.lastError });
        if (Mihomo.checking) return I18n.t("vpn.exit_checking");
        if (!Mihomo.egress) return I18n.t("vpn.exit_unchecked");
        const e = Mihomo.egress;
        return I18n.t("vpn.exit_is", {
            where: (e.ip || "?") + (e.country ? " · " + e.country : "")
        });
    }

    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo; running: window.visible
    }
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: window.visible
    }
    readonly property color moodColor: Mihomo.running ? ThemeBackend.teal : ThemeBackend.surface2

    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * window.introMain)
        opacity: window.introMain
        transform: Translate { y: window.s(20) * (1 - window.introMain) }

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
                opacity: Mihomo.running ? 0.05 : 0.02
                color: window.moodColor
                Behavior on color { ColorAnimation { duration: 800 } }
            }
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-120)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(90)
                opacity: Mihomo.running ? 0.04 : 0.015
                color: window.moodColor
                Behavior on color { ColorAnimation { duration: 800 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(14)
                spacing: window.s(10)

                // -- state --
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(76)
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: window.s(16)
                        anchors.rightMargin: window.s(16)
                        spacing: window.s(14)

                        Rectangle {
                            Layout.preferredWidth: window.s(44)
                            Layout.preferredHeight: window.s(44)
                            radius: width / 2
                            color: Mihomo.running ? ThemeBackend.teal : ThemeBackend.surface1
                            Behavior on color { ColorAnimation { duration: 220 } }
                            Text {
                                anchors.centerIn: parent
                                text: Mihomo.running ? "󰦝" : "󰦞"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(20)
                                color: Mihomo.running ? ThemeBackend.base : ThemeBackend.subtext0
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: window.s(2)
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Mihomo.running
                                    ? (Mihomo.currentNode !== "" ? Mihomo.currentNode : I18n.t("vpn.state_on"))
                                    : I18n.t("vpn.state_off")
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: window.s(15)
                                color: ThemeBackend.text
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Mihomo.running
                                    ? (Mihomo.mode !== "" ? I18n.t("vpn.mode_is", { mode: Mihomo.mode }) : MihomoApi.base)
                                    : I18n.t("vpn.controller_at", { url: MihomoApi.base })
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }

                        ColumnLayout {
                            visible: Mihomo.running
                            spacing: window.s(2)
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: "↓ " + Mihomo.formatSpeed(Mihomo.downSpeed)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(11)
                                color: ThemeBackend.subtext1
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: "↑ " + Mihomo.formatSpeed(Mihomo.upSpeed)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(11)
                                color: ThemeBackend.subtext1
                            }
                        }
                    }
                }

                // -- the tunnel is up but names do not resolve, which from
                // outside looks like a working VPN with no internet --
                Rectangle {
                    visible: Mihomo.running && Mihomo.resolvedHijacked
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(52)
                    radius: ThemeBackend.borderRadius
                    color: Qt.rgba(ThemeBackend.peach.r, ThemeBackend.peach.g, ThemeBackend.peach.b, 0.14)
                    border.width: 1
                    border.color: ThemeBackend.peach

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: window.s(14)
                        anchors.rightMargin: window.s(14)
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        text: I18n.t("vpn.dns_hijacked", { device: Mihomo.tunDevice })
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(12)
                        color: ThemeBackend.text
                    }
                }

                // -- actions --
                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(8)

                    ClickButton {
                        visible: Mihomo.canControlService
                        Layout.fillWidth: true
                        height: window.s(38)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: Mihomo.running ? "󰓛" : "󰐊"
                        iconFontSize: window.s(14)
                        buttonText: Mihomo.busy
                            ? I18n.t("vpn.working")
                            : (Mihomo.running ? I18n.t("vpn.stop") : I18n.t("vpn.start"))
                        textFontSize: window.s(12)
                        accentColor: Mihomo.running ? ThemeBackend.surface1 : ThemeBackend.teal
                        textColor: Mihomo.running ? ThemeBackend.text : ThemeBackend.base
                        onClicked: Mihomo.running ? Mihomo.stop() : Mihomo.start()
                    }

                    ClickButton {
                        Layout.fillWidth: !Mihomo.canControlService
                        height: window.s(38)
                        cornerRadius: ThemeBackend.borderRadius
                        horizontalPadding: window.s(14)
                        buttonIcon: "󱎫"
                        iconFontSize: window.s(14)
                        buttonText: Mihomo.probing ? I18n.t("vpn.probing") : I18n.t("vpn.probe")
                        textFontSize: window.s(12)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: {
                            if (window.currentGroup) Mihomo.probeDelays(window.currentGroup.name);
                        }
                    }

                    ClickButton {
                        height: window.s(38)
                        cornerRadius: ThemeBackend.borderRadius
                        horizontalPadding: window.s(14)
                        buttonIcon: "󰇧"
                        iconFontSize: window.s(14)
                        buttonText: Mihomo.checking ? I18n.t("vpn.exit_checking_short") : I18n.t("vpn.exit")
                        textFontSize: window.s(12)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: Mihomo.check()
                    }
                }

                // -- how much of the traffic goes through the rules at all --
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mihomo.running && Mihomo.mode !== ""
                    spacing: window.s(6)

                    Repeater {
                        model: ["rule", "global", "direct"]
                        ClickButton {
                            required property var modelData
                            height: window.s(28)
                            cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
                            horizontalPadding: window.s(14)
                            buttonText: I18n.t("vpn.mode_" + modelData)
                            textFontSize: window.s(11)
                            property bool picked: Mihomo.mode === modelData
                            accentColor: picked ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: picked ? ThemeBackend.base : ThemeBackend.subtext1
                            onClicked: Mihomo.setMode(modelData)
                        }
                    }
                }

                // -- groups, only when a config actually has more than one --
                Flow {
                    Layout.fillWidth: true
                    visible: Mihomo.groups.length > 1
                    spacing: window.s(6)
                    Repeater {
                        model: Mihomo.groups
                        ClickButton {
                            required property var modelData
                            height: window.s(28)
                            cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
                            horizontalPadding: window.s(12)
                            buttonText: modelData.name
                            textFontSize: window.s(11)
                            property bool picked: window.currentGroup && window.currentGroup.name === modelData.name
                            accentColor: picked ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: picked ? ThemeBackend.base : ThemeBackend.subtext1
                            onClicked: window.viewGroup = modelData.name
                        }
                    }
                }

                // -- nodes --
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - window.s(40)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: window.nodeList.length === 0
                        text: Mihomo.running ? I18n.t("vpn.no_nodes_yet")
                                             : I18n.t("vpn.no_controller", { url: MihomoApi.base })
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(12)
                        color: ThemeBackend.subtext0
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: window.s(6)
                        visible: window.nodeList.length > 0
                        model: window.nodeList
                        spacing: window.s(2)
                        clip: true

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: window.s(40)
                            radius: Math.max(0, ThemeBackend.borderRadius - 2)
                            readonly property bool picked: window.currentGroup
                                && window.currentGroup.now === modelData
                            color: picked ? ThemeBackend.surface2
                                          : (nodeMouse.containsMouse ? ThemeBackend.surface1 : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: window.s(12)
                                anchors.rightMargin: window.s(12)
                                spacing: window.s(10)

                                Text {
                                    text: parent.parent.picked ? "󰄬" : ""
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(13)
                                    color: ThemeBackend.teal
                                    Layout.preferredWidth: window.s(14)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(12)
                                    color: ThemeBackend.text
                                }
                                Text {
                                    text: window.delayText(modelData)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(11)
                                    color: window.delayColor(Mihomo.delays[modelData])
                                }
                            }

                            MouseArea {
                                id: nodeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (window.currentGroup)
                                        Mihomo.select(window.currentGroup.name, modelData);
                                }
                            }
                        }
                    }
                }

                // -- profiles the core already has on disk --
                Rectangle {
                    visible: Mihomo.profilesDir !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: profilesCol.implicitHeight + window.s(16)
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: profilesCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: window.s(8)
                        spacing: window.s(6)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: window.s(8)

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: window.s(6)
                                text: I18n.t("vpn.profiles") + " · " + Mihomo.profiles.length
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(12)
                                color: ThemeBackend.subtext1
                            }
                            ClickButton {
                                height: window.s(26)
                                cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
                                horizontalPadding: window.s(10)
                                buttonIcon: "󰑐"
                                iconFontSize: window.s(13)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.text
                                onClicked: Mihomo.refreshProfiles()
                            }
                            ClickButton {
                                height: window.s(26)
                                cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
                                horizontalPadding: window.s(10)
                                buttonIcon: window.profilesOpen ? "󰅃" : "󰅀"
                                iconFontSize: window.s(13)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.text
                                onClicked: window.profilesOpen = !window.profilesOpen
                            }
                        }

                        Repeater {
                            model: window.profilesOpen ? Mihomo.profiles : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(34)
                                radius: Math.max(0, ThemeBackend.borderRadius - 2)
                                readonly property bool picked: Mihomo.currentProfile === modelData
                                color: picked ? ThemeBackend.surface2
                                              : (profMouse.containsMouse ? ThemeBackend.surface1 : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: window.s(10)
                                    anchors.rightMargin: window.s(10)
                                    spacing: window.s(8)
                                    Text {
                                        text: parent.parent.picked ? "󰄬" : ""
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: window.s(12)
                                        color: ThemeBackend.teal
                                        Layout.preferredWidth: window.s(14)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: String(modelData).split("/").pop()
                                        elide: Text.ElideMiddle
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: window.s(11)
                                        color: ThemeBackend.text
                                    }
                                }

                                MouseArea {
                                    id: profMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!Mihomo.busy) Mihomo.loadProfile(modelData)
                                }
                            }
                        }

                        Text {
                            visible: window.profilesOpen && Mihomo.profiles.length === 0
                            Layout.fillWidth: true
                            Layout.leftMargin: window.s(6)
                            wrapMode: Text.WordWrap
                            text: I18n.t("vpn.no_profiles", { dir: Mihomo.profilesDir })
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: window.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }
                }

                // -- where traffic comes out --
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(32)
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: window.s(12)
                        anchors.rightMargin: window.s(12)
                        spacing: window.s(8)

                        Text {
                            text: window.footerBad ? "󰀦" : "󰇧"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: window.s(12)
                            color: window.footerBad ? ThemeBackend.red : ThemeBackend.subtext0
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: window.footerText
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: window.s(11)
                            color: window.footerBad ? ThemeBackend.red : ThemeBackend.subtext0
                        }
                    }
                }
            }
        }
    }
}
