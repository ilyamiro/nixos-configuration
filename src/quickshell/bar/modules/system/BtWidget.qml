import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import "../../../reusables"
import "../../../"

Rectangle {
    id: btWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property bool isDesktop: false
    property string btStatus: "Off"
    property string btIcon: "󰂲"
    property string btDevice: "Off"
    property bool isBtOn: btStatus.toLowerCase() === "enabled" || btStatus.toLowerCase() === "on"
    property real targetX: 0
    property bool showLayout: false
    property alias btPill: btPill

    Component.onCompleted: {
        updateBtData();
    }

    onModuleActiveChanged: {
        if (!moduleActive) {
            chassisDetector.running = false;
        } else {
            chassisDetector.running = true;
            updateBtData();
        }
    }

    Process {
        id: chassisDetector
        running: btWidgetRoot.moduleActive
        command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                isDesktop = (this.text.trim() === "desktop");
            }
        }
    }

    Item {
        visible: false
        Connections {
            target: Bluetooth
            ignoreUnknownSignals: true
            function onDefaultAdapterChanged() { btWidgetRoot.updateBtData(); }
        }
        Connections {
            target: Bluetooth.defaultAdapter || null
            ignoreUnknownSignals: true
            function onEnabledChanged() { btWidgetRoot.updateBtData(); }
            function onDiscoveringChanged() { btWidgetRoot.updateBtData(); }
            function onDevicesChanged() { btWidgetRoot.updateBtData(); }
        }
        Repeater {
            id: btDeviceRepeater
            model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices : null
            Item {
                property var device: modelData
                Connections {
                    target: device || null
                    ignoreUnknownSignals: true
                    function onConnectedChanged() { btWidgetRoot.updateBtData(); }
                    function onNameChanged() { btWidgetRoot.updateBtData(); }
                    function onDeviceNameChanged() { btWidgetRoot.updateBtData(); }
                }
            }
        }
    }

    function updateBtData() {
        let adapter = Bluetooth.defaultAdapter;
        let enabled = adapter ? adapter.enabled : false;

        if (!enabled) {
            btStatus = "Off";
            btIcon = "󰂲";
            btDevice = "Off";
            return;
        }

        btStatus = "On";

        let connectedDev = null;

        if (adapter && adapter.devices) {
            for (let i = 0; i < btDeviceRepeater.count; i++) {
                let item = btDeviceRepeater.itemAt(i);
                if (item && item.device && item.device.connected) {
                    connectedDev = item.device;
                    break;
                }
            }

            if (!connectedDev) {
                let devList = adapter.devices.values || adapter.devices;
                if (devList && typeof devList.length === "number") {
                    for (let i = 0; i < devList.length; i++) {
                        let d = devList[i];
                        if (d && d.connected) {
                            connectedDev = d;
                            break;
                        }
                    }
                }
            }
        }

        if (connectedDev) {
            let name = connectedDev.name || connectedDev.deviceName || connectedDev.address || "";
            let iconType = connectedDev.icon || "";
            let typeLower = iconType.toLowerCase();
            let nameLower = name.toLowerCase();

            let icon = "󰂯";
            if (typeLower.indexOf("headset") !== -1 || typeLower.indexOf("headphone") !== -1 || nameLower.indexOf("headphone") !== -1 || nameLower.indexOf("buds") !== -1 || nameLower.indexOf("pods") !== -1) icon = "🎧";
            else if (typeLower.indexOf("audio") !== -1 || typeLower.indexOf("speaker") !== -1 || typeLower.indexOf("card") !== -1 || nameLower.indexOf("speaker") !== -1) icon = "📻";
            else if (typeLower.indexOf("phone") !== -1 || nameLower.indexOf("phone") !== -1 || nameLower.indexOf("iphone") !== -1 || nameLower.indexOf("android") !== -1) icon = "📱";
            else if (typeLower.indexOf("mouse") !== -1 || nameLower.indexOf("mouse") !== -1) icon = "󰍽";
            else if (typeLower.indexOf("keyboard") !== -1 || nameLower.indexOf("keyboard") !== -1) icon = "⌨️";
            else if (typeLower.indexOf("controller") !== -1 || nameLower.indexOf("controller") !== -1) icon = "🎮";

            btIcon = icon;
            btDevice = name;
        } else {
            btIcon = "󰂯";
            btDevice = "On";
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

    property real targetWidth: (moduleActive && !isDesktop && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    width: targetWidth

    opacity: (showLayout && moduleActive && !isDesktop) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: btWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: btWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: btWidgetRoot.showLayout ? 0 : barWindow.s(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(btWidgetRoot.isCompact ? 28 : 30) : (btWidgetRoot.isCompact ? 28 : 30)

        ClickButton {
            id: btPill
            property bool initAnimTrigger: false
            property bool isActive: isBtOn

            height: sysLayout.pillHeight
            maxWidth: barWindow ? barWindow.s(btWidgetRoot.isCompact ? 156 : 160) : (btWidgetRoot.isCompact ? 156 : 160)
            visible: targetWidth > 0
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            horizontalPadding: barWindow ? barWindow.s(btWidgetRoot.isCompact ? 10 : 12) : (btWidgetRoot.isCompact ? 10 : 12)
            buttonIcon: btIcon
            iconFontSize: barWindow ? barWindow.s(btWidgetRoot.isCompact ? 14 : 15) : (btWidgetRoot.isCompact ? 14 : 15)
            buttonText: btDevice
            textFontSize: barWindow ? barWindow.s(btWidgetRoot.isCompact ? 11 : 12) : (btWidgetRoot.isCompact ? 11 : 12)
            accentColor: isActive ? (btWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve) : (btWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0)
            textColor: isActive ? ThemeBackend.base : (btWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.text, 1.05) : ThemeBackend.text)

            property real targetWidth: isDesktop ? 0 : implicitWidth
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Timer { running: btWidgetRoot.moduleActive && btWidgetRoot.showLayout && !btPill.initAnimTrigger; interval: 190; onTriggered: btPill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: btPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle network bt"])
        }
    }
}
