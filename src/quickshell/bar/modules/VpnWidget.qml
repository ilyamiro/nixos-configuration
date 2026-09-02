import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

// The VPN chip.
//
// It reads Mihomo, which is what actually keeps the state; referencing it here
// is also what constructs it, since a QML singleton is built on first use.
Rectangle {
    id: vpnWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool moduleActive: true
    property bool isGrouped: false
    property real targetX: 0
    property bool showLayout: false
    property alias vpnPill: vpnPill

    readonly property bool isUp: Mihomo.running

    readonly property string label: {
        if (!Mihomo.running) return I18n.t("vpn.chip_off");
        return Mihomo.currentNode !== "" ? Mihomo.currentNode : I18n.t("vpn.chip_on");
    }

    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }
    y: barWindow ? barWindow.baseOffsetY : 0
    height: barWindow ? barWindow.barHeight : 0
    radius: ThemeBackend.borderRadius
    border.color: (isGrouped || isSolid) ? "transparent" : ThemeBackend.surface0
    border.width: (isGrouped || isSolid) ? 0 : 1
    color: (isGrouped || isSolid) ? "transparent" : ThemeBackend.base
    clip: true

    property real targetWidth: (moduleActive && vpnLayout.implicitWidth > 0)
        ? (vpnLayout.implicitWidth + (barWindow ? barWindow.s(10) : 10)) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive)
        ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: vpnWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: vpnWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: vpnWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: vpnLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(30) : 30

        ClickButton {
            id: vpnPill
            property bool initAnimTrigger: false

            height: vpnLayout.pillHeight
            maxWidth: barWindow ? barWindow.s(170) : 170
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - 2)
            horizontalPadding: barWindow ? barWindow.s(12) : 12
            buttonIcon: vpnWidgetRoot.isUp ? "󰦝" : "󰦞"
            iconFontSize: barWindow ? barWindow.s(15) : 15
            buttonText: vpnWidgetRoot.label
            textFontSize: barWindow ? barWindow.s(12) : 12

            accentColor: vpnWidgetRoot.isUp ? ThemeBackend.teal : ThemeBackend.surface0
            textColor: vpnWidgetRoot.isUp ? ThemeBackend.base : ThemeBackend.text

            property real targetWidth: implicitWidth
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Timer {
                running: vpnWidgetRoot.moduleActive && vpnWidgetRoot.showLayout && !vpnPill.initAnimTrigger
                interval: 130
                onTriggered: vpnPill.initAnimTrigger = true
            }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate {
                y: vpnPill.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
                Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
            }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: Quickshell.execDetached(["bash", "-c",
                Caching.serpantinumDir + "/scripts/qs_manager.sh toggle vpn"])
        }
    }
}
