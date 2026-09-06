pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string soundsDir: Caching.qsDir + "/../assets/sounds/"

    property var activeHandles: ({})
    property int nextHandleId: 1

    property var _pendingQueue: []

    property var generalSettings: Config.getSetting("general", { "muteSfx": false, "sfxVolume": 100 })
    readonly property bool isMuted: generalSettings && generalSettings.muteSfx === true
    readonly property real masterVolume: {
        let v = (generalSettings && generalSettings.sfxVolume !== undefined) ? Number(generalSettings.sfxVolume) : 100;
        return Math.max(0.0, Math.min(1.0, v / 100.0));
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.generalSettings = Config.getSetting("general", { "muteSfx": false, "sfxVolume": 100 });
        }
    }

    function play(filePath, volume, duration, overrideSfxBlock) {
        if ((root.isMuted || root.masterVolume <= 0.0) && overrideSfxBlock !== true) return;
        if (!filePath || filePath.trim() === "") return;
        let vol = volume === undefined ? 1.0 : Math.max(0.0, Math.min(2.0, volume));
        let finalVol = overrideSfxBlock === true ? vol : (vol * root.masterVolume);
        let dur = duration === undefined ? 0 : duration;
        root._pendingQueue.push({ filePath: filePath, volume: finalVol, duration: dur });
        Qt.callLater(root._drainQueue);
    }

    function playSfx(filename, volume, duration, overrideSfxBlock) {
        root.play(root.soundsDir + filename, volume, duration, overrideSfxBlock);
    }

    function _drainQueue() {
        let q = root._pendingQueue;
        root._pendingQueue = [];
        for (let i = 0; i < q.length; i++) {
            root._reallyPlay(q[i].filePath, q[i].volume, q[i].duration);
        }
    }

    function _reallyPlay(filePath, vol, dur) {
        let cleanPath = filePath.startsWith("file://") ? filePath.substring(7) : filePath;
        try {
            if (dur > 0) {
                let escaped = cleanPath.replace(/'/g, "'\\''");
                Quickshell.execDetached(["sh", "-c",
                    "exec timeout " + dur + " pw-play --volume=" + vol + " '" + escaped + "' >/dev/null 2>&1"]);
            } else {
                Quickshell.execDetached(["pw-play", "--volume=" + vol.toString(), cleanPath]);
            }
        } catch(e) {}
    }

    Component {
        id: stoppableProcess
        Process {
            property int handleId: -1
            stdinEnabled: false
        }
    }

    function playUntilStopped(filenameOrPath, volume, loop, overrideSfxBlock) {
        if ((root.isMuted || root.masterVolume <= 0.0) && overrideSfxBlock !== true) return -1;
        let vol = Math.max(0.0, Math.min(2.0, volume === undefined ? 1.0 : volume));
        let finalVol = overrideSfxBlock === true ? vol : (vol * root.masterVolume);
        let doLoop = loop === true;
        let cleanPath = (filenameOrPath.startsWith("/") || filenameOrPath.startsWith("file://")) ?
            (filenameOrPath.startsWith("file://") ? filenameOrPath.substring(7) : filenameOrPath) :
            (root.soundsDir + filenameOrPath);
        let volFlag = "--volume=" + finalVol;

        let id = root.nextHandleId++;

        let script;
        if (doLoop) {
            script =
                "trap 'kill $CPID 2>/dev/null; exit' TERM; " +
                "while :; do pw-play " + volFlag + " '" + cleanPath + "' & CPID=$!; wait $CPID; done";
        } else {
            script = "exec pw-play " + volFlag + " '" + cleanPath + "'";
        }

        let proc = stoppableProcess.createObject(root, {
            "command": ["sh", "-c", script],
            "handleId": id
        });
        proc.running = true;

        proc.exited.connect(function() {
            delete root.activeHandles[id];
            proc.destroy();
        });

        root.activeHandles[id] = proc;
        return id;
    }

    function stopSfx(handleId) {
        let entry = root.activeHandles[handleId];
        if (!entry) return;
        entry.running = false;
        delete root.activeHandles[handleId];
    }

    function stopAllSfx() {
        for (let id in root.activeHandles) {
            root.activeHandles[id].running = false;
        }
        root.activeHandles = ({});
    }
}
