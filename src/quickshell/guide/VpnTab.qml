import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

// Settings and documentation for the VPN panel.
//
// The panel needs to be told where the controller is, and there is no safe
// default to guess for a secret or for how somebody's core is supervised. So
// the settings live here, next to an explanation of what the panel does and,
// just as importantly, what it does not.
Item {
    id: vpnTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    readonly property var settings: Config.getSetting("vpn", ({}))

    function put(key, value) {
        let cur = JSON.parse(JSON.stringify(Config.getSetting("vpn", ({})) || ({})));
        cur[key] = value;
        Config.setSetting("vpn", cur);
    }

    function valueOf(key, fallback) {
        const v = vpnTabRoot.settings ? vpnTabRoot.settings[key] : undefined;
        return (v === undefined || v === null) ? fallback : String(v);
    }

    // One delegate for every text setting: they differ by label and key, not
    // by shape, and nine hand-written copies of the same row would drift.
    readonly property var textSettings: [
        { key: "controller", fallback: "http://127.0.0.1:9090",
          label: I18n.t("guide.vpn.controller"), desc: I18n.t("guide.vpn.controller_desc") },
        { key: "secret", fallback: "",
          label: I18n.t("guide.vpn.secret"), desc: I18n.t("guide.vpn.secret_desc") },
        { key: "primaryGroup", fallback: "PROXY",
          label: I18n.t("guide.vpn.primary_group"), desc: I18n.t("guide.vpn.primary_group_desc") },
        { key: "startCommand", fallback: "",
          label: I18n.t("guide.vpn.start_command"), desc: I18n.t("guide.vpn.start_command_desc") },
        { key: "stopCommand", fallback: "",
          label: I18n.t("guide.vpn.stop_command"), desc: I18n.t("guide.vpn.stop_command_desc") },
        { key: "profilesDir", fallback: "",
          label: I18n.t("guide.vpn.profiles_dir"), desc: I18n.t("guide.vpn.profiles_dir_desc") },
        { key: "tunDevice", fallback: "",
          label: I18n.t("guide.vpn.tun_device"), desc: I18n.t("guide.vpn.tun_device_desc") },
        { key: "egressUrl", fallback: "https://ipinfo.io/json",
          label: I18n.t("guide.vpn.egress_url"), desc: I18n.t("guide.vpn.egress_url_desc") }
    ]

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: settingsCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: rootObj.s(12)

            // -- what this is --
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(4)
                implicitHeight: docCol.implicitHeight + rootObj.s(28)
                radius: ThemeBackend.borderRadius
                color: ThemeBackend.surface0

                ColumnLayout {
                    id: docCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(8)

                    Text {
                        text: I18n.t("guide.vpn.doc_title")
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: rootObj.s(14)
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: I18n.t("guide.vpn.doc_body")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext1
                        lineHeight: 1.25
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: I18n.t("guide.vpn.doc_scope")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext0
                        lineHeight: 1.25
                    }
                }
            }

            // -- what the controller says right now, so the settings above can
            //    be checked without leaving the page --
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rootObj.s(48)
                radius: ThemeBackend.borderRadius
                color: Mihomo.running
                    ? Qt.alpha(ThemeBackend.green, 0.12)
                    : Qt.alpha(ThemeBackend.surface2, 0.5)
                border.width: 1
                border.color: Mihomo.running ? Qt.alpha(ThemeBackend.green, 0.4) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: rootObj.s(14)
                    anchors.rightMargin: rootObj.s(14)
                    spacing: rootObj.s(10)

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Mihomo.running
                            ? I18n.t("guide.vpn.status_up", {
                                url: MihomoApi.base, groups: Mihomo.groups.length })
                            : I18n.t("guide.vpn.status_down", { url: MihomoApi.base })
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.text
                    }

                    ClickButton {
                        height: rootObj.s(30)
                        cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
                        horizontalPadding: rootObj.s(14)
                        buttonText: I18n.t("guide.vpn.recheck")
                        textFontSize: rootObj.s(11)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: Mihomo.refresh()
                    }
                }
            }

            // -- text settings --
            Repeater {
                model: vpnTabRoot.textSettings

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: rowCol.implicitHeight + rootObj.s(24)
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0

                    ColumnLayout {
                        id: rowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: rootObj.s(12)
                        spacing: rootObj.s(6)

                        Text {
                            text: modelData.label
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: rootObj.s(12)
                            color: ThemeBackend.text
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: modelData.desc
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                        Input {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            text: vpnTabRoot.valueOf(modelData.key, "")
                            placeholderText: modelData.fallback !== ""
                                ? modelData.fallback : I18n.t("guide.vpn.unset")
                            fontPixelSize: rootObj.s(12)
                            baseColor: ThemeBackend.base
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.text
                            subTextColor: ThemeBackend.subtext0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            cornerRadius: ThemeBackend.borderRadius
                            onAccepted: function(t) {
                                vpnTabRoot.put(modelData.key, (typeof t === "string") ? t : text);
                            }
                        }
                    }
                }
            }

            // -- the one boolean --
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: rootObj.s(8)
                implicitHeight: resetRow.implicitHeight + rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: ThemeBackend.surface0

                RowLayout {
                    id: resetRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: rootObj.s(12)
                    anchors.rightMargin: rootObj.s(12)
                    spacing: rootObj.s(12)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(4)
                        Text {
                            text: I18n.t("guide.vpn.reset_on_switch")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: rootObj.s(12)
                            color: ThemeBackend.text
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: I18n.t("guide.vpn.reset_on_switch_desc")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignVCenter
                        checked: Mihomo.resetOnSwitch
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) { vpnTabRoot.put("resetOnSwitch", c); }
                    }
                }
            }
        }
    }
}
