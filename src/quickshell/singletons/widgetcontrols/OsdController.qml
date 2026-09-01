pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import "../../"

Item {
    id: controller

    property bool isVisible: false
    property string kind: "volume"
    property int briVal: 0
    property string stateVal: "off"
    property var screen: null
    property bool isHovered: false
    property bool isFullscreen: false

    readonly property PwNode activeSink: Audio.defaultSink || (Audio.outputs && Audio.outputs.length > 0 ? Audio.outputs[0] : null)
    readonly property real sysVolume: activeSink && activeSink.audio ? Math.round(activeSink.audio.volume * 100) : 0
    readonly property bool sysMuted: activeSink && activeSink.audio ? activeSink.audio.muted : false

    readonly property PwNode activeSource: Audio.defaultSource || (Audio.inputs && Audio.inputs.length > 0 ? Audio.inputs[0] : null)
    readonly property real sysMicVolume: activeSource && activeSource.audio ? Math.round(activeSource.audio.volume * 100) : 0
    readonly property bool sysMicMuted: activeSource && activeSource.audio ? activeSource.audio.muted : false

    readonly property bool wifiRadioEnabled: Networking.wifiEnabled
    readonly property bool btRadioEnabled: Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
    readonly property bool sysAirplane: !wifiRadioEnabled && !btRadioEnabled

    property int sysBrightness: 0

    property real lastVolume: -1
    property bool lastMuted: false
    property real lastMicVolume: -1
    property bool lastMicMuted: false
    property bool lastAirplane: false
    property int lastCapsLock: -1
    property int lastNumLock: -1
    property int lastBrightness: -1
    property bool brightnessInitialized: false
    property bool kbInitialized: false
    property bool isInitialized: false

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (!controller.isHovered) {
                controller.isVisible = false;
            }
        }
    }

    Timer {
        id: initTimer
        interval: 1000
        running: true
        repeat: false
        onTriggered: {
            controller.lastVolume = controller.sysVolume;
            controller.lastMuted = controller.sysMuted;
            controller.lastMicVolume = controller.sysMicVolume;
            controller.lastMicMuted = controller.sysMicMuted;
            controller.lastAirplane = controller.sysAirplane;
            controller.lastBrightness = controller.sysBrightness;
            controller.isInitialized = true;
        }
    }

    onSysVolumeChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastVolume !== controller.sysVolume) {
            controller.lastVolume = controller.sysVolume;
            controller.show("volume");
        }
    }

    onSysMutedChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMuted !== controller.sysMuted) {
            controller.lastMuted = controller.sysMuted;
            controller.show("volume");
        }
    }

    onSysMicVolumeChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMicVolume !== controller.sysMicVolume) {
            controller.lastMicVolume = controller.sysMicVolume;
            controller.show("mic");
        }
    }

    onSysMicMutedChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastMicMuted !== controller.sysMicMuted) {
            controller.lastMicMuted = controller.sysMicMuted;
            controller.show("mic");
        }
    }

    onSysAirplaneChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastAirplane !== controller.sysAirplane) {
            controller.lastAirplane = controller.sysAirplane;
            controller.show("airplane", controller.sysAirplane ? "on" : "off");
        }
    }

    onSysBrightnessChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastBrightness !== controller.sysBrightness) {
            controller.lastBrightness = controller.sysBrightness;
            controller.show("brightness");
        }
    }

    Process {
        id: kbWatcher
        running: true
        command: ["bash", Caching.qsDir + "/../scripts/kb_locks.sh", "watch"]
        stdout: SplitParser {
            onRead: data => {
                kbFetchDebounce.restart();
            }
        }
    }

    Timer {
        id: kbFetchDebounce
        interval: 30
        repeat: false
        onTriggered: {
            kbFetcher.running = false;
            kbFetcher.running = true;
        }
    }

    Timer {
        id: kbPollTimer
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (controller.isInitialized && !kbFetcher.running) {
                kbFetcher.running = true;
            }
        }
    }

    Process {
        id: kbFetcher
        running: true
        command: ["bash", Caching.qsDir + "/../scripts/kb_locks.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim().split(/\s+/);
                if (out.length >= 2) {
                    let caps = parseInt(out[0]);
                    let num = parseInt(out[1]);
                    if (!isNaN(caps) && !isNaN(num)) {
                        if (!controller.kbInitialized) {
                            controller.lastCapsLock = caps;
                            controller.lastNumLock = num;
                            controller.kbInitialized = true;
                            return;
                        }
                        if (controller.isInitialized) {
                            if (caps !== controller.lastCapsLock) {
                                controller.lastCapsLock = caps;
                                controller.show("capslock", caps === 1 ? "on" : "off");
                            } else if (num !== controller.lastNumLock) {
                                controller.lastNumLock = num;
                                controller.show("numlock", num === 1 ? "on" : "off");
                            }
                        }
                    }
                }
            }
        }
    }

    Process {
        id: briWatcher
        running: true
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "watch"]
        stdout: SplitParser {
            onRead: data => {
                briFetchDebounce.restart();
            }
        }
    }

    Timer {
        id: briFetchDebounce
        interval: 50
        repeat: false
        onTriggered: {
            briFetcher.running = false;
            briFetcher.running = true;
        }
    }

    Process {
        id: briFetcher
        running: true
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                if (out !== "") {
                    let val = parseInt(out);
                    if (!isNaN(val)) {
                        if (!controller.brightnessInitialized) {
                            controller.lastBrightness = val;
                            controller.brightnessInitialized = true;
                        }
                        controller.sysBrightness = val;
                        controller.briVal = val;
                    }
                }
            }
        }
    }

    function show(k, v, scr) {
        controller.kind = k || "volume";
        if (controller.kind === "brightness" && v !== undefined) {
            controller.briVal = parseInt(v) || 0;
        } else if (v !== undefined) {
            controller.stateVal = v.toString();
        }
        if (scr !== undefined && scr !== null) {
            controller.screen = scr;
        }
        controller.isVisible = true;
        hideTimer.restart();
    }

    function display(k, v, scr) {
        show(k, v, scr);
    }

    function hide() {
        hideTimer.stop();
        controller.isVisible = false;
    }

    function requestHide() {
        if (!controller.isHovered) {
            hideTimer.restart();
        }
    }

    function cancelHide() {
        hideTimer.stop();
    }

    function restartTimer() {
        if (controller.isVisible) {
            hideTimer.restart();
        }
    }

    function toggle(k, v, scr) {
        if (controller.isVisible && controller.kind === k) {
            hide();
        } else {
            show(k, v, scr);
        }
    }
}
