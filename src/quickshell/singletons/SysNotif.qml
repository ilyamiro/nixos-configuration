pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../"
import "../info"

Item {
    id: root

    readonly property bool hasBattery: {
        if (UPower.displayDevice.ready) {
            return UPower.displayDevice.isLaptopBattery || UPower.displayDevice.type === UPowerDeviceType.Battery;
        }
        return typeof SystemInfo !== "undefined" ? !SystemInfo.isDesktop : false;
    }

    readonly property int batteryPercentage: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool isCharging: root.hasBattery && UPower.displayDevice.ready && (
        UPower.displayDevice.state === UPowerDeviceState.Charging ||
        UPower.displayDevice.state === UPowerDeviceState.FullyCharged
    )

    property int firedLevel: 101
    property bool notifiedFull: false
    property bool isInitialized: false

    function sendNotification(summary, body, icon, urgency, timeoutMs) {
        let u = urgency ? urgency : "normal";
        let ic = icon ? icon : "battery";
        let appName = "Battery";
        let t = (timeoutMs !== undefined) ? timeoutMs.toString() : "5000";

        Quickshell.execDetached([
            "notify-send",
            "-a", appName,
            "-u", u,
            "-i", ic,
            "-t", t,
            summary,
            body
        ]);
    }

    function checkBattery() {
        if (!root.hasBattery || !UPower.displayDevice.ready) return;

        let pct = root.batteryPercentage;
        if (pct <= 0) return;

        if (!root.isInitialized) {
            root.isInitialized = true;
            if (pct >= 98) {
                root.notifiedFull = true;
            }
        }

        if (root.isCharging) {
            root.firedLevel = 101;

            if ((pct >= 100 || UPower.displayDevice.state === UPowerDeviceState.FullyCharged) && !root.notifiedFull) {
                root.notifiedFull = true;
                root.sendNotification(
                    I18n.t("sysnotif.battery.full_title"),
                    I18n.t("sysnotif.battery.full_body"),
                    "battery-full-charged",
                    "normal",
                    5000
                );
            } else if (pct < 98) {
                root.notifiedFull = false;
            }
            return;
        }

        root.notifiedFull = false;

        if (pct <= 2) {
            if (root.firedLevel > 2) {
                root.firedLevel = 2;
                let emergencyTitle = I18n.t("sysnotif.battery.emergency_title");
                let emergencyBody = I18n.t("sysnotif.battery.emergency_body", { "pct": pct.toString() });
                root.sendNotification(
                    emergencyTitle,
                    emergencyBody,
                    "battery-level-0-symbolic",
                    "critical",
                    0
                );
            }
        } else if (pct <= 5) {
            if (root.firedLevel > 5) {
                root.firedLevel = 5;
                root.sendNotification(
                    I18n.t("sysnotif.battery.critical_title"),
                    I18n.t("sysnotif.battery.critical_body", { "pct": pct.toString() }),
                    "battery-level-0-symbolic",
                    "critical",
                    10000
                );
            }
        } else if (pct <= 20) {
            if (root.firedLevel > 20) {
                root.firedLevel = 20;
                root.sendNotification(
                    I18n.t("sysnotif.battery.low_title"),
                    I18n.t("sysnotif.battery.low_body", { "pct": pct.toString() }),
                    "battery-level-20-symbolic",
                    "normal",
                    5000
                );
            }
        } else if (pct >= 23) {
            root.firedLevel = 101;
        }
    }

    function init() {
        checkBattery();
    }

    onIsChargingChanged: root.checkBattery()
    onBatteryPercentageChanged: root.checkBattery()

    Connections {
        target: UPower.displayDevice
        function onReadyChanged() { root.checkBattery(); }
    }

    Component.onCompleted: {
        root.checkBattery();
    }
}
