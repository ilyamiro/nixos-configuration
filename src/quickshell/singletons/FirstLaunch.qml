pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "./"

Item {
    id: root

    readonly property string serpantinumDir: {
        if (typeof Caching !== "undefined" && Caching.serpantinumDir) {
            return Caching.serpantinumDir;
        }
        return "";
    }

    readonly property string helperScript: root.serpantinumDir + "/scripts/first_launch.sh"

    property bool isFirstLaunch: false
    property bool executed: false
    property string pendingStartQml: ""

    signal firstLaunchStarted()
    signal startAnimations()
    signal firstLaunchFinished()

    Timer {
        id: startupDelayTimer
        interval: 350
        repeat: false
        onTriggered: {
            initProcess.running = true;
        }
    }

    Timer {
        id: launchStageTimer
        interval: 850
        repeat: false
        onTriggered: {
            root.firstLaunchStarted();
            root.startAnimations();

            if (root.pendingStartQml.length > 0) {
                startLoader.source = "file://" + root.pendingStartQml;
            } else {
                startLoader.source = Qt.resolvedUrl("../serp/Start.qml");
            }
            startLoader.active = true;
        }
    }

    IpcHandler {
        target: "firstlaunch"

        function trigger(): bool {
            root.runSetup("", "");
            return true;
        }

        function reset(): bool {
            Quickshell.execDetached(["bash", root.helperScript, "--reset"]);
            root.executed = false;
            root.isFirstLaunch = false;
            return true;
        }
    }

    function checkFirstLaunch() {
        if (executed) return;
        executed = true;
        startupDelayTimer.start();
    }

    function runSetup(customWp, startQml) {
        root.isFirstLaunch = true;
        root.pendingStartQml = startQml || "";

        let wp = (customWp || "").trim();
        if (wp.startsWith("file://")) {
            wp = wp.substring(7).trim();
        }

        if (wp.length > 0) {
            try {
                if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                    Matugen.generate(wp, "", "");
                }
            } catch (e) {}

            Wallpaper.setWallpaper("all", wp, "fade");
            launchStageTimer.interval = 900;
        } else {
            launchStageTimer.interval = 100;
        }

        launchStageTimer.start();
    }

    Loader {
        id: startLoader
        active: false
        onLoaded: {
            if (item && typeof item.start === "function") {
                item.start();
            } else if (item && typeof item.play === "function") {
                item.play();
            }
        }
    }

    Connections {
        target: startLoader.item
        ignoreUnknownSignals: true
        function onFinished() {
            startLoader.active = false;
            Quickshell.execDetached(["bash", root.helperScript, "--open-guide"]);
            root.firstLaunchFinished();
        }
        function onClosed() {
            startLoader.active = false;
            Quickshell.execDetached(["bash", root.helperScript, "--open-guide"]);
            root.firstLaunchFinished();
        }
    }

    Process {
        id: initProcess
        running: false
        command: ["bash", root.helperScript, "--check"]
        stdout: StdioCollector {
            id: initOut
            onStreamFinished: {
                let lines = initOut.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.startsWith("FIRST|")) {
                        let parts = line.split("|");
                        let wp = parts.length > 1 ? parts[1] : "";
                        let startQml = parts.length > 2 ? parts[2] : "";
                        root.runSetup(wp, startQml);
                        break;
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        root.checkFirstLaunch();
    }
}
