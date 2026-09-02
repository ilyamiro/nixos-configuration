pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    readonly property string compositor: {
        let de = (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv.toLowerCase() : "";
        if (de.indexOf("niri") !== -1) return "niri";
        if (de.indexOf("sway") !== -1) return "sway";
        return "hyprland";
    }

    property var defaultDisplaySettings: ({ "monitors": {} })
    property var pendingTargets: ({})
    property var currentJob: null
    property bool isBusy: false
    property bool initialSettingsApplied: false

    function getCoordinates() {
        let lat = 0;
        let lon = 0;
        if (typeof Location !== "undefined" && Location.locationData) {
            if (Location.locationData.latitude !== undefined) lat = Location.locationData.latitude;
            if (Location.locationData.longitude !== undefined) lon = Location.locationData.longitude;
        }
        if (lat === 0 && lon === 0) {
            let genSet = Config.getSetting("general", {});
            let loc = genSet.location || {};
            if (loc.latitude !== undefined) lat = loc.latitude;
            if (loc.longitude !== undefined) lon = loc.longitude;
        }
        return { "lat": lat, "lon": lon };
    }

    function kelvinFromTemp(temp) {
        let t = (temp !== undefined && temp !== null) ? Number(temp) : 50;
        return Math.round(6500 - (t / 100) * (6500 - 2500));
    }

    function scheduleNext() {
        if (isBusy || retryTimer.running) return;

        let keys = Object.keys(pendingTargets);
        if (keys.length === 0) return;

        let key = keys[0];
        let target = pendingTargets[key];
        delete pendingTargets[key];

        currentJob = target;
        isBusy = true;

        let cmd = ["bash", Caching.serpantinumDir + "/scripts/blue_light_filter.sh"];
        if (target.enabled) {
            let kelvin = kelvinFromTemp(target.temp);
            let modeStr = target.autoMode ? "auto" : "manual";
            let coords = getCoordinates();
            cmd.push("set", kelvin.toString(), target.monName, modeStr, coords.lat.toString(), coords.lon.toString());
        } else {
            cmd.push("reset", target.monName);
        }

        runnerProcess.command = cmd;
        runnerProcess.running = false;
        runnerProcess.running = true;
    }

    function onJobFinished(exitCode) {
        isBusy = false;
        if (!currentJob) {
            scheduleNext();
            return;
        }

        if (exitCode !== 0 && currentJob.retries > 0) {
            let retryJob = currentJob;
            retryJob.retries -= 1;
            currentJob = null;
            let key = retryJob.monName || "global";
            if (!pendingTargets[key]) {
                pendingTargets[key] = retryJob;
            }
            retryTimer.restart();
            return;
        }

        currentJob = null;
        scheduleNext();
    }

    Process {
        id: runnerProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            root.onJobFinished(exitCode);
        }
    }

    Timer {
        id: retryTimer
        interval: 1000
        repeat: false
        onTriggered: root.scheduleNext()
    }

    function apply(monName, enabled, temp, autoMode) {
        if (!monName || !Caching.serpantinumDir) return;
        let key = monName || "global";
        pendingTargets[key] = {
            "monName": monName,
            "enabled": !!enabled,
            "temp": (temp !== undefined && temp !== null) ? Number(temp) : 50,
            "autoMode": !!autoMode,
            "retries": 3
        };
        scheduleNext();
    }

    function applyForMonitor(monName) {
        if (!monName) return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        let mSet = (ds && ds.monitors && ds.monitors[monName]) ? ds.monitors[monName] : {};
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : 50;
        apply(monName, isEn, temp, isAu);
    }

    function setEnabled(monName, enabled) {
        updateMonitorSetting(monName, "enabled", enabled);
    }

    function setAuto(monName, autoMode) {
        updateMonitorSetting(monName, "auto", autoMode);
    }

    function setTemperature(monName, temp) {
        updateMonitorSetting(monName, "temperature", temp);
    }

    function reset(monName) {
        if (!Caching.serpantinumDir) return;
        let key = monName || "global";
        pendingTargets[key] = {
            "monName": monName || "",
            "enabled": false,
            "retries": 3
        };
        scheduleNext();
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName) return;
        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current.monitors) current.monitors = {};
        if (!current.monitors[monName]) current.monitors[monName] = {};

        current.monitors[monName][key] = value;
        Config.setSetting("display", current);

        let mSet = current.monitors[monName];
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : 50;

        apply(monName, isEn, temp, isAu);
    }

    function applyAll() {
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds || !ds.monitors) return;
        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let mName = keys[i];
            let mSet = ds.monitors[mName];
            if (mSet) {
                let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
                let isAu = mSet.auto !== undefined ? mSet.auto : false;
                let temp = mSet.temperature !== undefined ? mSet.temperature : 50;
                apply(mName, isEn, temp, isAu);
            }
        }
    }

    Process {
        id: outputDetector
        running: false
        command: [
            "bash",
            "-c",
            root.compositor === "niri"
                ? "niri msg -j outputs 2>/dev/null"
                : (root.compositor === "sway"
                    ? "swaymsg -t get_outputs -r 2>/dev/null"
                    : "hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j 2>/dev/null")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyAll();
            }
        }
    }

    function reload() {
        outputDetector.running = false;
        outputDetector.running = true;
    }

    function ensureInitialApply() {
        if (root.initialSettingsApplied) return;
        root.initialSettingsApplied = true;
        root.applyAll();
    }

    function applyAllAutoOnly() {
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds || !ds.monitors) return;
        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let mName = keys[i];
            let mSet = ds.monitors[mName];
            if (mSet && mSet.enabled && mSet.auto) {
                let temp = mSet.temperature !== undefined ? mSet.temperature : 50;
                apply(mName, true, temp, true);
            }
        }
    }

    Timer {
        id: locationDebounce
        interval: 5 * 60 * 1000
        repeat: false
        onTriggered: root.applyAllAutoOnly()
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            root.ensureInitialApply();
        }
    }

    Connections {
        target: typeof Location !== "undefined" ? Location : null
        function onLocationUpdated() {
            locationDebounce.restart();
        }
    }

    Component.onCompleted: {
        root.ensureInitialApply();
    }
}
