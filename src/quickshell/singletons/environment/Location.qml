pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property var locationData: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general && Config.rawSettings.general.location) ? Config.rawSettings.general.location : ({})
    property bool isDetecting: false

    readonly property string ip: locationData.ip || ""
    readonly property real latitude: locationData.latitude !== undefined ? Number(locationData.latitude) : 0.0
    readonly property real longitude: locationData.longitude !== undefined ? Number(locationData.longitude) : 0.0
    readonly property string city: locationData.city || "Unknown"
    readonly property string region: locationData.region || "Unknown"
    readonly property string regionCode: locationData.region_code || ""
    readonly property string countryName: locationData.country_name || locationData.country || "Unknown"
    readonly property string countryCode: locationData.country_code || ""
    readonly property string postal: locationData.postal || locationData.zip || ""
    readonly property string timezone: locationData.timezone || "UTC"
    readonly property string utcOffset: locationData.utc_offset || ""
    readonly property string currency: locationData.currency || ""
    readonly property string languages: locationData.languages || ""
    readonly property string asn: locationData.asn || ""
    readonly property string org: locationData.org || ""
    readonly property string source: locationData.source || "unknown"
    readonly property var updatedAt: locationData.updated_at !== undefined ? locationData.updated_at : 0

    readonly property var entries: {
        let arr = [];
        if (root.locationData) {
            for (let key in root.locationData) {
                let val = root.locationData[key];
                if (key === "updated_at" && typeof val === "number") {
                    val = new Date(val * 1000).toLocaleString();
                }
                arr.push({ label: key, value: String(val) });
            }
        }
        return arr;
    }

    signal locationUpdated()

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            let gs = Config.getSetting("general", {});
            root.locationData = gs && gs.location ? gs.location : {};
            root.isDetecting = false;
            root.locationUpdated();
        }
    }

    onLocationDataChanged: {
        root.locationUpdated();
    }

    function get(key, fallbackValue) {
        if (root.locationData && root.locationData.hasOwnProperty(key)) {
            return root.locationData[key];
        }
        return fallbackValue !== undefined ? fallbackValue : "";
    }

    function detectAuto() {
        if (!Caching.serpantinumDir) return;
        root.isDetecting = true;
        autoProcess.running = false;
        autoProcess.running = true;
    }

    function setManual(lat, lon) {
        if (!Caching.serpantinumDir) return;
        root.isDetecting = true;
        manualProcess.lat = lat.toString();
        manualProcess.lon = lon.toString();
        manualProcess.running = false;
        manualProcess.running = true;
    }

    Process {
        id: autoProcess
        command: ["bash", "-c", Caching.serpantinumDir + "/scripts/location.sh --refresh"]
        onExited: {
            root.isDetecting = false;
        }
    }

    Process {
        id: manualProcess
        property string lat: ""
        property string lon: ""
        command: ["bash", "-c", Caching.serpantinumDir + "/scripts/location_manual.sh '" + lat + "' '" + lon + "'"]
        onExited: {
            root.isDetecting = false;
        }
    }

    Component.onCompleted: {
        if (typeof Config !== "undefined" && Config.dataReady) {
            let gs = Config.getSetting("general", {});
            if (gs && gs.location) {
                root.locationData = gs.location;
            }
        }
    }
}
