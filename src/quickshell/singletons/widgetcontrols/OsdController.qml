pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../"

Item {
    id: controller

    property bool isVisible: false
    property string kind: "volume"
    property int briVal: 0
    property var screen: null
    property bool isHovered: false
    property bool isFullscreen: false

    readonly property real sysVolume: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    readonly property bool sysMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false

    property int sysBrightness: 0

    property real lastVolume: -1
    property bool lastMuted: false
    property int lastBrightness: -1
    property bool brightnessInitialized: false
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

    onSysBrightnessChanged: {
        if (!controller.isInitialized) return;
        if (controller.lastBrightness !== controller.sysBrightness) {
            controller.lastBrightness = controller.sysBrightness;
            controller.show("brightness");
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
        if (controller.kind !== "volume" && v !== undefined) {
            controller.briVal = parseInt(v) || 0;
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
