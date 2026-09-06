pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property int barCount: 64
    property var barLevels: {
        let arr = [];
        for (let i = 0; i < barCount; i++) arr.push(0.0);
        return arr;
    }
    property int activeConsumers: 0
    property bool isPlaying: MprisController.isPlaying
    property bool isRestarting: false
    property bool processEnabled: activeConsumers > 0 && (isPlaying || decayTimer.running) && !isRestarting

    function registerConsumer() {
        activeConsumers++;
    }

    function unregisterConsumer() {
        activeConsumers = Math.max(0, activeConsumers - 1);
    }

    function resetBars() {
        let empty = [];
        for (let i = 0; i < root.barCount; i++) {
            empty.push(0.0);
        }
        root.barLevels = empty;
    }

    function restartCava() {
        if (!processEnabled) return;
        isRestarting = true;
        restartTimer.restart();
    }

    onIsPlayingChanged: {
        if (isPlaying) {
            decayTimer.stop();
        } else if (activeConsumers > 0) {
            decayTimer.restart();
        } else {
            resetBars();
        }
    }

    onProcessEnabledChanged: {
        if (!processEnabled) {
            resetBars();
        }
    }

    Timer {
        id: decayTimer
        interval: 1000
        repeat: false
    }

    Timer {
        id: restartTimer
        interval: 500
        repeat: false
        onTriggered: root.isRestarting = false
    }

    Timer {
        id: dataWatchdog
        interval: 2000
        running: cavaProcess.running && root.isPlaying
        repeat: false
        onTriggered: root.restartCava()
    }

    Process {
        id: cavaProcess
        running: root.processEnabled
        onExited: root.restartCava()
        command: [
            "bash", "-c",
            "cava -p <(printf '[general]\\nbars = %d\\nframerate = 60\\nsensitivity = 150\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 1000\\nbar_delimiter = 59\\n' " + root.barCount + ")"
        ]
        stdout: SplitParser {
            onRead: data => {
                if (!root.processEnabled) return;
                dataWatchdog.restart();
                let str = data.trim();
                if (str.length === 0) return;
                let parts = str.split(";");
                let count = Math.min(parts.length, root.barCount);
                let newLevels = [];
                for (let i = 0; i < root.barCount; i++) {
                    let val = i < count ? (parseInt(parts[i]) || 0) : 0;
                    newLevels.push(Math.max(0.0, Math.min(1.0, val / 1000.0)));
                }
                root.barLevels = newLevels;
            }
        }
    }
}
