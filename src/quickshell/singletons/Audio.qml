pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property var outputs: {
        let arr = [];
        for (const n of Pipewire.nodes.values) {
            if (!n.isStream && n.isSink && n.audio) arr.push(n);
        }
        return arr;
    }

    readonly property var inputs: {
        let arr = [];
        for (const n of Pipewire.nodes.values) {
            if (!n.isStream && !n.isSink && n.audio
                && n.properties?.["device.class"] !== "monitor"
                && !n.name?.endsWith(".monitor")) {
                arr.push(n);
            }
        }
        return arr;
    }

    readonly property var apps: {
        let arr = [];
        for (const n of Pipewire.nodes.values) {
            if (n.isStream && n.audio
                && n.properties?.["application.id"] !== "org.PulseAudio.pavucontrol") {
                arr.push(n);
            }
        }
        return arr;
    }

    readonly property PwNode defaultSink: Pipewire.defaultAudioSink
    readonly property PwNode defaultSource: Pipewire.defaultAudioSource

    // Upper limit for every volume surface (popup sliders, OSD, bar widget) and
    // for scripts/volume.sh. Percentage; 100 keeps the classic behaviour.
    property var generalSettings: Config.getSetting("general", { "maxVolume": 100 })
    readonly property int maxVolume: {
        let v = (generalSettings && generalSettings.maxVolume !== undefined) ? Number(generalSettings.maxVolume) : 100;
        if (isNaN(v)) return 100;
        return Math.max(100, Math.min(200, Math.round(v)));
    }
    readonly property real maxVolumeFactor: maxVolume / 100.0

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.generalSettings = Config.getSetting("general", { "maxVolume": 100 });
        }
    }

    function setDefaultOutput(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultInput(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }

    function toggleMute(node) {
        if (node && node.audio) node.audio.muted = !node.audio.muted;
    }

    function setVolume(node, pct) {
        if (node && node.audio) node.audio.volume = Math.max(0, Math.min(root.maxVolumeFactor, pct / 100.0));
    }

    function getNodeName(node) {
        if (!node) return "";
        return node.properties?.["device.description"] || node.description || node.name || "Unknown Device";
    }

    function getNodeSubDesc(node) {
        if (!node) return "";
        if (node.isStream) {
            return node.properties?.["media.name"] || node.properties?.["window.title"] || node.properties?.["media.role"] || "Audio Stream";
        }
        return node.name || "Unknown";
    }

    function getNodeAppName(node) {
        if (!node) return "";
        return node.properties?.["application.name"] || node.properties?.["application.process.binary"] || node.description || "Unknown App";
    }
}
