import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: blStartup

    readonly property string compositor: {
        let de = (SystemInfo.desktopEnv || "").toLowerCase();
        if (de.indexOf("niri") !== -1) return "niri";
        if (de.indexOf("sway") !== -1) return "sway";
        return "hyprland";
    }

    function manageWarmProcess(monName, enabled, temp, autoMode) {
        if (!monName) return;
        if (enabled) {
            let kelvin = Math.round(6500 - (temp / 100) * (6500 - 2500));
            let modeStr = autoMode ? "auto" : "manual";
            let genSet = Config.getSetting("general", {});
            let loc = genSet.location || {};
            let lat = loc.latitude !== undefined ? loc.latitude : 0;
            let lon = loc.longitude !== undefined ? loc.longitude : 0;
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/blue_light_filter.sh", "set", kelvin.toString(), monName, modeStr, lat.toString(), lon.toString()]);
        } else {
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/blue_light_filter.sh", "reset", monName]);
        }
    }

    function applyAllMonitorsSettings(monNames) {
        let ds = Config.getSetting("display", {});
        if (!ds || !ds.monitors) return;
        for (let i = 0; i < monNames.length; i++) {
            let mName = monNames[i];
            let mSet = ds.monitors[mName];
            if (mSet) {
                let startAtBoot = mSet.startAtBoot !== undefined ? mSet.startAtBoot : true;
                if (!startAtBoot) continue;
                let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
                let isAu = mSet.auto !== undefined ? mSet.auto : false;
                let temp = mSet.temperature !== undefined ? mSet.temperature : 50;
                blStartup.manageWarmProcess(mName, isEn, temp, isAu);
            }
        }
    }

    Process {
        id: outputDetector
        running: false
        command: [
            "bash",
            "-c",
            blStartup.compositor === "niri"
                ? "niri msg -j outputs 2>/dev/null"
                : (blStartup.compositor === "sway"
                    ? "swaymsg -t get_outputs -r 2>/dev/null"
                    : "hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j 2>/dev/null")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                let names = [];
                if (out) {
                    try {
                        let data = JSON.parse(out);
                        if (blStartup.compositor === "niri" && data && typeof data === "object") {
                            names = Object.keys(data);
                        } else if (Array.isArray(data)) {
                            names = data.map(x => x.name).filter(n => !!n);
                        }
                    } catch (e) {
                    }
                }
                if (names.length === 0) {
                    let cfg = Config.getSetting("display", {});
                    names = Object.keys((cfg && cfg.monitors) || {});
                }
                blStartup.applyAllMonitorsSettings(names);
            }
        }
    }

    function run() {
        outputDetector.running = false;
        outputDetector.running = true;
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            blStartup.run();
        }
    }

    Component.onCompleted: blStartup.run()
}
