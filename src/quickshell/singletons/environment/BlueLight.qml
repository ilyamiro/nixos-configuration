pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    signal settingsChanged()

    readonly property string compositor: {
        let de = (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv.toLowerCase() : "";
        if (de.indexOf("niri") !== -1) return "niri";
        if (de.indexOf("sway") !== -1) return "sway";
        return "hyprland";
    }

    property var defaultDisplaySettings: ({ "monitors": {} })
    property var pendingTargets: ({})
    property var appliedStates: ({})
    property var currentJob: null
    property bool isBusy: false
    property bool initialSettingsApplied: false

    function getCoordinates() {
        let lat = 0;
        let lon = 0;
        if (typeof Location !== "undefined") {
            if (Location.latitude !== undefined && Location.latitude !== 0) lat = Number(Location.latitude);
            if (Location.longitude !== undefined && Location.longitude !== 0) lon = Number(Location.longitude);
            if (lat === 0 && lon === 0 && Location.locationData) {
                if (Location.locationData.latitude !== undefined) lat = Number(Location.locationData.latitude);
                if (Location.locationData.longitude !== undefined) lon = Number(Location.locationData.longitude);
            }
        }
        if (lat === 0 && lon === 0) {
            let genSet = typeof Config !== "undefined" ? Config.getSetting("general", {}) : {};
            let loc = genSet.location || {};
            if (loc.latitude !== undefined) lat = Number(loc.latitude);
            if (loc.longitude !== undefined) lon = Number(loc.longitude);
        }
        return { "lat": lat, "lon": lon };
    }

    function getSavedTemperature(monName) {
        if (typeof Config === "undefined") return 50;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) return 50;
        if (monName && ds.monitors && ds.monitors[monName] && ds.monitors[monName].temperature !== undefined) {
            return ds.monitors[monName].temperature;
        }
        if (ds.temperature !== undefined) {
            return ds.temperature;
        }
        if (ds.monitors) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let m = ds.monitors[keys[i]];
                if (m && m.temperature !== undefined) {
                    return m.temperature;
                }
            }
        }
        return 50;
    }

    function getSavedAuto(monName) {
        if (typeof Config === "undefined") return false;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) return false;
        if (monName && ds.monitors && ds.monitors[monName] && ds.monitors[monName].auto !== undefined) {
            return ds.monitors[monName].auto;
        }
        if (ds.auto !== undefined) {
            return ds.auto;
        }
        if (ds.monitors) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let m = ds.monitors[keys[i]];
                if (m && m.auto !== undefined) {
                    return m.auto;
                }
            }
        }
        return false;
    }

    function kelvinFromTemp(temp) {
        let t = (temp !== undefined && temp !== null) ? Number(temp) : 50;
        if (t >= 1000) {
            return Math.min(Math.max(Math.round(t), 1000), 10000);
        }
        return Math.round(6500 - (t / 100) * (6500 - 2500));
    }

    function scheduleNext() {
        if (isBusy || runnerProcess.running || retryTimer.running) return;

        let keys = Object.keys(pendingTargets);
        if (keys.length === 0) return;

        let scriptPath = (typeof Caching !== "undefined" && Caching.serpantinumDir)
            ? Caching.serpantinumDir + "/scripts/blue_light_filter.sh"
            : "";

        if (!scriptPath) {
            let resolved = Qt.resolvedUrl("../../scripts/blue_light_filter.sh").toString();
            if (resolved.indexOf("file://") === 0) {
                resolved = resolved.substring(7);
            }
            scriptPath = resolved;
        }

        if (!scriptPath) {
            retryTimer.interval = 100;
            retryTimer.restart();
            return;
        }

        let key = keys[0];
        let target = pendingTargets[key];
        delete pendingTargets[key];

        currentJob = target;
        isBusy = true;

        let cmd = ["bash", scriptPath];
        if (target.enabled) {
            let kelvin = kelvinFromTemp(target.temp);
            let modeStr = target.autoMode ? "auto" : "manual";
            let coords = getCoordinates();
            cmd.push("set", kelvin.toString(), target.monName, modeStr, coords.lat.toString(), coords.lon.toString());
        } else {
            cmd.push("reset", target.monName);
        }

        runnerProcess.command = cmd;
        runnerProcess.running = true;
    }

    function onJobFinished(exitCode) {
        isBusy = false;
        if (!currentJob) {
            scheduleNext();
            return;
        }

        let finishedJob = currentJob;
        let key = finishedJob.monName || "global";

        if (exitCode !== 0) {
            if (finishedJob.retries > 0) {
                finishedJob.retries -= 1;
                currentJob = null;
                if (!pendingTargets[key]) {
                    pendingTargets[key] = finishedJob;
                }
                retryTimer.interval = 200;
                retryTimer.restart();
                return;
            } else {
                delete appliedStates[key];
            }
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
        interval: 200
        repeat: false
        onTriggered: root.scheduleNext()
    }

    function apply(monName, enabled, temp, autoMode) {
        let key = monName || "global";
        let normEn = !!enabled;
        let normTemp = (temp !== undefined && temp !== null) ? Number(temp) : getSavedTemperature(monName);
        let normAu = !!autoMode;

        let prev = appliedStates[key];
        if (prev && prev.enabled === normEn && prev.temp === normTemp && prev.autoMode === normAu) {
            return;
        }

        appliedStates[key] = {
            "enabled": normEn,
            "temp": normTemp,
            "autoMode": normAu
        };

        pendingTargets[key] = {
            "monName": monName || "",
            "enabled": normEn,
            "temp": normTemp,
            "autoMode": normAu,
            "retries": 3
        };
        scheduleNext();
    }

    function applyForMonitor(monName) {
        if (!monName) return;
        let ds = typeof Config !== "undefined" ? Config.getSetting("display", defaultDisplaySettings) : defaultDisplaySettings;
        let mSet = (ds && ds.monitors && ds.monitors[monName]) ? ds.monitors[monName] : {};
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : getSavedTemperature(monName);
        apply(monName, isEn, temp, isAu);
    }

    function setEnabled(monName, enabled) {
        if (typeof enabled === "undefined" && typeof monName === "boolean") {
            enabled = monName;
            monName = "";
        }
        if (!monName) {
            let temp = getSavedTemperature("");
            let autoMode = getSavedAuto("");
            if (typeof Config !== "undefined") {
                let current = Config.getSetting("display", defaultDisplaySettings);
                current.enabled = enabled;
                if (current.monitors) {
                    let keys = Object.keys(current.monitors);
                    for (let i = 0; i < keys.length; i++) {
                        current.monitors[keys[i]].enabled = enabled;
                        let mTemp = current.monitors[keys[i]].temperature !== undefined ? current.monitors[keys[i]].temperature : temp;
                        let mAuto = current.monitors[keys[i]].auto !== undefined ? current.monitors[keys[i]].auto : autoMode;
                        apply(keys[i], enabled, mTemp, mAuto);
                    }
                }
                Config.setSetting("display", current);
            }
            apply("", enabled, temp, autoMode);
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "enabled", enabled);
    }

    function setAuto(monName, autoMode) {
        if (typeof autoMode === "undefined" && typeof monName === "boolean") {
            autoMode = monName;
            monName = "";
        }
        if (!monName) {
            let temp = getSavedTemperature("");
            let anyEnabled = isAnyEnabled();
            if (typeof Config !== "undefined") {
                let current = Config.getSetting("display", defaultDisplaySettings);
                current.auto = autoMode;
                if (current.monitors) {
                    let keys = Object.keys(current.monitors);
                    for (let i = 0; i < keys.length; i++) {
                        current.monitors[keys[i]].auto = autoMode;
                        let mEn = current.monitors[keys[i]].enabled !== undefined ? current.monitors[keys[i]].enabled : anyEnabled;
                        let mTemp = current.monitors[keys[i]].temperature !== undefined ? current.monitors[keys[i]].temperature : temp;
                        apply(keys[i], mEn, mTemp, autoMode);
                    }
                }
                Config.setSetting("display", current);
            }
            apply("", anyEnabled, temp, autoMode);
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "auto", autoMode);
    }

    function setTemperature(monName, temp) {
        if (typeof temp === "undefined" && (typeof monName === "number" || typeof monName === "string")) {
            temp = monName;
            monName = "";
        }
        let numTemp = Number(temp);
        if (!monName) {
            let autoMode = getSavedAuto("");
            let anyEnabled = isAnyEnabled();
            if (typeof Config !== "undefined") {
                let current = Config.getSetting("display", defaultDisplaySettings);
                current.temperature = numTemp;
                if (current.monitors) {
                    let keys = Object.keys(current.monitors);
                    for (let i = 0; i < keys.length; i++) {
                        current.monitors[keys[i]].temperature = numTemp;
                        let mEn = current.monitors[keys[i]].enabled !== undefined ? current.monitors[keys[i]].enabled : anyEnabled;
                        let mAuto = current.monitors[keys[i]].auto !== undefined ? current.monitors[keys[i]].auto : autoMode;
                        apply(keys[i], mEn, numTemp, mAuto);
                    }
                }
                Config.setSetting("display", current);
            }
            apply("", anyEnabled, numTemp, autoMode);
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "temperature", numTemp);
    }

    function reset(monName) {
        let key = monName || "global";
        let prev = appliedStates[key];
        if (prev && !prev.enabled) {
            return;
        }
        let temp = getSavedTemperature(monName);
        appliedStates[key] = {
            "enabled": false,
            "temp": temp,
            "autoMode": false
        };
        pendingTargets[key] = {
            "monName": monName || "",
            "enabled": false,
            "temp": temp,
            "autoMode": false,
            "retries": 3
        };
        scheduleNext();
        root.settingsChanged();
    }

    function isAnyEnabled() {
        if (typeof Config === "undefined") return false;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (ds && ds.enabled) return true;
        if (!ds || !ds.monitors) return false;
        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let m = ds.monitors[keys[i]];
            if (m && m.enabled) return true;
        }
        return false;
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName || typeof Config === "undefined") return;
        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current.monitors) current.monitors = {};
        if (!current.monitors[monName]) current.monitors[monName] = {};

        if (current.monitors[monName][key] === value) return;

        current.monitors[monName][key] = value;
        Config.setSetting("display", current);

        let mSet = current.monitors[monName];
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : getSavedTemperature(monName);

        apply(monName, isEn, temp, isAu);
        root.settingsChanged();
    }

    function applyAll() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) return;

        if (ds.monitors && Object.keys(ds.monitors).length > 0) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let mName = keys[i];
                let mSet = ds.monitors[mName];
                if (mSet) {
                    let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
                    let isAu = mSet.auto !== undefined ? mSet.auto : false;
                    let temp = mSet.temperature !== undefined ? mSet.temperature : getSavedTemperature(mName);
                    let prev = appliedStates[mName];

                    if (isEn || (prev && prev.enabled)) {
                        apply(mName, isEn, temp, isAu);
                    }
                }
            }
        } else if (ds.enabled !== undefined) {
            let temp = ds.temperature !== undefined ? ds.temperature : getSavedTemperature("");
            let autoMode = ds.auto !== undefined ? ds.auto : false;
            apply("", ds.enabled, temp, autoMode);
        }
        root.settingsChanged();
    }

    function ensureInitialApply() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", null);
        if (!ds) return;
        if ((!ds.monitors || Object.keys(ds.monitors).length === 0) && ds.enabled === undefined) return;
        root.initialSettingsApplied = true;
        root.applyAll();
    }

    function applyAllAutoOnly() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds || !ds.monitors) return;
        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let mName = keys[i];
            let mSet = ds.monitors[mName];
            if (mSet && mSet.enabled && mSet.auto) {
                let temp = mSet.temperature !== undefined ? mSet.temperature : getSavedTemperature(mName);
                let prev = appliedStates[mName];
                if (prev) delete appliedStates[mName];
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
        ignoreUnknownSignals: true
        function onSettingsLoaded() {
            root.ensureInitialApply();
        }
    }

    Connections {
        target: typeof Location !== "undefined" ? Location : null
        ignoreUnknownSignals: true
        function onLocationUpdated() {
            locationDebounce.restart();
        }
    }

    Connections {
        target: typeof Quickshell !== "undefined" ? Quickshell : null
        ignoreUnknownSignals: true
        function onScreensChanged() {
            root.applyAll();
        }
    }

    Component.onCompleted: {
        root.ensureInitialApply();
    }
}
