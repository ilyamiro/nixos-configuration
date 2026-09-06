pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property int refreshInterval: {
        let gs = (typeof Config !== "undefined" && typeof Config.getSetting === "function")
            ? Config.getSetting("general", {})
            : ((typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings.general : null);
        let mins = (gs && gs.weatherInterval !== undefined) ? Number(gs.weatherInterval) : 15;
        return (!isNaN(mins) && mins > 0 ? mins : 15) * 60000;
    }
    property string unit: {
        let gs = (typeof Config !== "undefined" && typeof Config.getSetting === "function")
            ? Config.getSetting("general", {})
            : ((typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings.general : null);
        return (gs && gs.weatherUnit !== undefined) ? gs.weatherUnit : "metric";
    }
    property var customLocation: null

    readonly property var activeLocation: customLocation !== null 
        ? customLocation 
        : ((typeof Location !== "undefined" && Location.locationData && Object.keys(Location.locationData).length > 0) 
            ? Location.locationData 
            : ((typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general && Config.rawSettings.general.location) 
                ? Config.rawSettings.general.location 
                : null))

    property var data: ({})
    property var forecast: []
    property string currentIcon: ""
    property string currentTemp: ""
    property string currentTempFormatted: "--°"
    property string currentHex: (typeof ThemeBackend !== "undefined" && ThemeBackend.yellow) ? ThemeBackend.yellow.toString() : "#f9e2af"
    property string unitSym: "°C"
    property real latitude: 0.0
    property real longitude: 0.0

    property bool isLoading: false
    property bool isReady: false
    property bool _forceFetchMode: false

    property string _lastLocationFingerprint: ""
    property string _lastUnit: ""

    signal weatherUpdated()

    onActiveLocationChanged: {
        checkLocationUpdate();
    }

    onUnitChanged: {
        if (root._lastUnit !== "" && root._lastUnit !== root.unit) {
            root._lastUnit = root.unit;
            root.refresh(true);
        } else if (root._lastUnit === "") {
            root._lastUnit = root.unit;
        }
    }

    Connections {
        target: typeof Location !== "undefined" ? Location : null
        function onLocationUpdated() {
            root.checkLocationUpdate();
        }
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            root.checkLocationUpdate();
            let gs = (typeof Config !== "undefined" && typeof Config.getSetting === "function")
                ? Config.getSetting("general", {})
                : ((typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings.general : null);
            if (gs) {
                if (gs.weatherInterval !== undefined) {
                    let mins = Number(gs.weatherInterval);
                    if (!isNaN(mins) && mins > 0) {
                        root.refreshInterval = mins * 60000;
                    }
                }
                if (gs.weatherUnit !== undefined && gs.weatherUnit !== root.unit) {
                    root.unit = gs.weatherUnit;
                }
            }
            root.refresh(false);
        }
    }

    function checkLocationUpdate() {
        let fp = JSON.stringify(root.activeLocation || {});
        if (root._lastLocationFingerprint !== "" && root._lastLocationFingerprint !== fp) {
            root._lastLocationFingerprint = fp;
            root.refresh(true);
        } else if (root._lastLocationFingerprint === "") {
            root._lastLocationFingerprint = fp;
        }
    }

    function refresh(showLoader) {
        if (!Caching.serpantinumDir) return;
        let shouldShowLoader = showLoader !== undefined ? !!showLoader : true;
        root._forceFetchMode = shouldShowLoader;
        if (shouldShowLoader) {
            root.isLoading = true;
        }
        fetchProcess.running = false;
        fetchProcess.running = true;
    }

    function forceFetch() {
        refresh(true);
        return root.data;
    }

    function getData() {
        return root.data;
    }

    function parseJson(rawText) {
        if (!rawText) {
            root.isLoading = false;
            return;
        }
        let txt = typeof rawText === "function" ? rawText() : rawText;
        if (typeof txt !== "string") txt = String(txt || "");
        txt = txt.trim();
        if (txt === "") {
            root.isLoading = false;
            return;
        }

        try {
            let parsed = JSON.parse(txt);
            root.data = parsed;

            if (parsed.current_icon !== undefined) {
                root.currentIcon = parsed.current_icon;
            }
            if (parsed.current_temp_formatted !== undefined) {
                root.currentTempFormatted = parsed.current_temp_formatted;
            } else if (parsed.current_temp !== undefined && parsed.current_temp !== null) {
                let sym = parsed.unit_sym || "°C";
                root.currentTempFormatted = parsed.current_temp.toString() + sym;
            }
            if (parsed.current_temp !== undefined) {
                root.currentTemp = parsed.current_temp.toString();
            }
            if (parsed.current_hex !== undefined) {
                root.currentHex = parsed.current_hex;
            }
            if (parsed.unit_sym !== undefined) {
                root.unitSym = parsed.unit_sym;
            }
            if (parsed.latitude !== undefined) {
                root.latitude = Number(parsed.latitude);
            }
            if (parsed.longitude !== undefined) {
                root.longitude = Number(parsed.longitude);
            }
            if (parsed.forecast && Array.isArray(parsed.forecast)) {
                root.forecast = parsed.forecast;
            }

            root.isReady = true;
            root.isLoading = false;
            root.weatherUpdated();
        } catch(e) {
            root.isLoading = false;
        }
    }

    Process {
        id: fetchProcess
        command: {
            if (!Caching.serpantinumDir) return [];
            let locObj = root.activeLocation || {};
            let locJson = JSON.stringify(locObj);
            let locEscaped = locJson.replace(/'/g, "'\\''");
            let curUnit = root.unit || "metric";
            let cmd = "";
            if (root._forceFetchMode) {
                let cacheFile = (Caching.getCacheDir("weather") || (Caching.cacheDir + "/weather")) + "/weather.json";
                cmd = Caching.serpantinumDir + "/scripts/weather.sh --getdata --location '" + locEscaped + "' --unit '" + curUnit + "' && cat \"" + cacheFile + "\"";
            } else {
                cmd = Caching.serpantinumDir + "/scripts/weather.sh --json --location '" + locEscaped + "' --unit '" + curUnit + "'";
            }
            return ["bash", "-c", cmd];
        }
        stdout: StdioCollector {
            id: fetchOut
            onStreamFinished: {
                root.parseJson(fetchOut.text);
            }
        }
        onExited: {
            root.isLoading = false;
            root._forceFetchMode = false;
        }
    }

    FileView {
        id: weatherWatcher
        path: Caching.cacheDir ? (Caching.getCacheDir("weather") + "/weather.json") : ""
        watchChanges: true
        onLoaded: root.parseJson(typeof weatherWatcher.text === "function" ? weatherWatcher.text() : weatherWatcher.text)
        onFileChanged: root.parseJson(typeof weatherWatcher.text === "function" ? weatherWatcher.text() : weatherWatcher.text)
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refresh(false)
    }

    Component.onCompleted: {
        root._lastLocationFingerprint = JSON.stringify(root.activeLocation || {});
        root._lastUnit = root.unit;
        if (typeof Config !== "undefined" && Config.dataReady) {
            root.refresh(false);
        }
    }
}
