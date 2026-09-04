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
    id: kbWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property string kbLayout: "us"
    property real targetX: 0
    property bool showLayout: false
    property alias kbPill: kbPill
    property bool isNiri: false
    property bool isSway: false

    Component.onCompleted: {
        let de = SystemInfo.desktopEnv ? SystemInfo.desktopEnv.toLowerCase() : "";
        kbWidgetRoot.isNiri = de.indexOf("niri") !== -1;
        kbWidgetRoot.isSway = de.indexOf("sway") !== -1;
    }

    onModuleActiveChanged: {
        if (!moduleActive) {
            kbPoller.running = false;
            kbWaiter.running = false;
        } else {
            kbPoller.running = false;
            kbPoller.running = true;
        }
    }

    Process {
        id: kbPoller
        running: kbWidgetRoot.moduleActive
        command: [
            "bash",
            "-c",
            kbWidgetRoot.isNiri
                ? "layout=$(niri msg -j keyboard-layouts 2>/dev/null | jq -r '.names[.current_idx] // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'"
                : (kbWidgetRoot.isSway
                    ? "layout=$(swaymsg -t get_inputs 2>/dev/null | jq -r '[.[] | select(.type == \"keyboard\" and .xkb_active_layout_name != null)] | .[0].xkb_active_layout_name // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'"
                    : "layout=$(LC_ALL=C hyprctl devices -j 2>/dev/null | jq -r '(.keyboards[] | select(.main == true) | .active_keymap) // .keyboards[0].active_keymap // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "" && kbLayout !== txt) kbLayout = txt;
                kbWaiter.running = false;
                if (kbWidgetRoot.moduleActive) kbWaiter.running = true;
                if (barWindow) barWindow.fastPollerLoaded = true;
            }
        }
    }

    Process {
        id: kbWaiter
        command: [
            "bash",
            Caching.qsDir + "/watchers/kb_wait.sh",
            kbWidgetRoot.isNiri ? "niri" : (kbWidgetRoot.isSway ? "sway" : "hyprland")
        ]
        onExited: {
            kbPoller.running = false;
            if (kbWidgetRoot.moduleActive) kbPoller.running = true;
        }
    }

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

    property real targetWidth: (moduleActive && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: kbWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: kbWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: kbWidgetRoot.showLayout ? 0 : barWindow.s(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 28 : 30) : (kbWidgetRoot.isCompact ? 28 : 30)

        ClickButton {
            id: kbPill
            property bool initAnimTrigger: false
            height: sysLayout.pillHeight
            maxWidth: barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 96 : 100) : (kbWidgetRoot.isCompact ? 96 : 100)
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            horizontalPadding: barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 10 : 12) : (kbWidgetRoot.isCompact ? 10 : 12)
            buttonIcon: "󰌌"
            iconFontSize: barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 14 : 15) : (kbWidgetRoot.isCompact ? 14 : 15)
            buttonText: kbLayout
            textFontSize: barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 11 : 12) : (kbWidgetRoot.isCompact ? 11 : 12)
            accentColor: kbWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (kbWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.text, 1.05) : ThemeBackend.text)

            property real targetWidth: Math.max(barWindow ? barWindow.s(kbWidgetRoot.isCompact ? 48 : 52) : (kbWidgetRoot.isCompact ? 48 : 52), implicitWidth)
            width: targetWidth

            Behavior on width {
                enabled: barWindow.startupCascadeFinished
                NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
            }

            Timer { running: kbWidgetRoot.moduleActive && kbWidgetRoot.showLayout && !kbPill.initAnimTrigger; interval: 70; onTriggered: kbPill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: kbPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: {
                if (kbWidgetRoot.isNiri) {
                    Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]);
                } else if (kbWidgetRoot.isSway) {
                    Quickshell.execDetached(["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"]);
                } else {
                    Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
                }
            }
        }
    }
}
