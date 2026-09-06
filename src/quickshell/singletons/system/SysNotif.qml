pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../../"

Item {
    id: root

    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : (typeof SystemInfo !== "undefined" ? SystemInfo.isDesktop : true)
    readonly property int batteryPercentage: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)

    property bool notifiedFull: false
    property bool notifiedLow: false
    property bool notifiedCritical: false

    function sendNotification(summary, body, icon, urgency) {
        let u = urgency ? urgency : "normal";
        let ic = icon ? icon : "battery";
        let appName = I18n.t("sysnotif.battery.app_name");
        Quickshell.execDetached([
            "notify-send",
            "-a", appName,
            "-u", u,
            "-i", ic,
            summary,
            body
        ]);
    }

    function checkBattery() {
        if (root.isDesktop || !UPower.displayDevice.ready) return;

        let pct = root.batteryPercentage;
        let state = UPower.displayDevice.state;
        let charging = state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged;

        if (charging) {
            root.notifiedLow = false;
            root.notifiedCritical = false;

            if ((pct >= 100 || state === UPowerDeviceState.FullyCharged) && !root.notifiedFull) {
                root.notifiedFull = true;
                root.sendNotification(
                    I18n.t("sysnotif.battery.full_title"),
                    I18n.t("sysnotif.battery.full_body"),
                    "battery-full-charged",
                    "normal"
                );
            } else if (pct < 98) {
                root.notifiedFull = false;
            }
        } else {
            root.notifiedFull = false;

            if (pct <= 5) {
                if (!root.notifiedCritical) {
                    root.notifiedCritical = true;
                    root.notifiedLow = true;
                    root.sendNotification(
                        I18n.t("sysnotif.battery.critical_title"),
                        I18n.t("sysnotif.battery.critical_body", { "pct": pct.toString() }),
                        "battery-level-0-symbolic",
                        "critical"
                    );
                }
            } else if (pct <= 20) {
                if (!root.notifiedLow) {
                    root.notifiedLow = true;
                    root.sendNotification(
                        I18n.t("sysnotif.battery.low_title"),
                        I18n.t("sysnotif.battery.low_body", { "pct": pct.toString() }),
                        "battery-level-20-symbolic",
                        "critical"
                    );
                }
            } else {
                root.notifiedLow = false;
                root.notifiedCritical = false;
            }
        }
    }

    Connections {
        target: UPower.displayDevice
        function onPercentageChanged() { root.checkBattery(); }
        function onStateChanged() { root.checkBattery(); }
        function onReadyChanged() { root.checkBattery(); }
    }

    Component.onCompleted: {
        root.checkBattery();
    }
}
