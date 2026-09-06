pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property bool isChecking: false
    property string localVersion: "2.0.0"
    property string remoteVersion: ""
    property bool updateAvailable: false
    property string lastNotifiedVersion: ""

    property string stateVersion: ""
    property string packageVersion: ""

    Connections {
        target: typeof SystemInfo !== "undefined" ? SystemInfo : null
        function onOsNameChanged() {
            root.reevaluateUpdate();
        }
    }

    function syncLocalVersion() {
        if (root.stateVersion !== "") {
            root.localVersion = root.stateVersion;
        } else if (root.packageVersion !== "") {
            root.localVersion = root.packageVersion;
        }
        root.reevaluateUpdate();
    }

    function parseVersion(v) {
        if (!v) return [0];
        let matches = v.match(/\d+/g);
        if (!matches) return [0];
        return matches.map(function(n) { return parseInt(n, 10); });
    }

    function isRemoteNewer(remote, local) {
        let r = parseVersion(remote);
        let l = parseVersion(local);
        let len = Math.max(r.length, l.length);
        for (let i = 0; i < len; i++) {
            let rv = i < r.length ? r[i] : 0;
            let lv = i < l.length ? l[i] : 0;
            if (rv > lv) return true;
            if (rv < lv) return false;
        }
        return false;
    }

    function reevaluateUpdate() {
        if (typeof SystemInfo !== "undefined" && SystemInfo.osName.toLowerCase().indexOf("nixos") !== -1) {
            root.updateAvailable = false;
            return;
        }
        if (!root.remoteVersion) {
            root.updateAvailable = false;
            return;
        }
        root.updateAvailable = isRemoteNewer(root.remoteVersion, root.localVersion);
    }

    function saveNotifiedVersion(ver) {
        if (typeof Caching === "undefined" || !Caching.serpantinumDir) return;
        let stateDir = Caching.getStateDir();
        Quickshell.execDetached([
            "python3",
            Caching.serpantinumDir + "/scripts/updater.py",
            "--state-dir",
            stateDir,
            "--save-notified",
            ver
        ]);
    }

    function sendNotification() {
        let serpDir = (typeof Caching !== "undefined" && Caching.serpantinumDir) ? Caching.serpantinumDir : "";
        let guideDir = (typeof Caching !== "undefined") ? Caching.getCacheDir("guide") : "";
        let appName = I18n.t("updater.notification.app_name");
        let actionText = I18n.t("updater.notification.action_open_guide");
        let notifTitle = I18n.t("updater.notification.update_available_title", { "remote": root.remoteVersion });
        let notifBody = I18n.t("updater.notification.update_available_body", { "local": root.localVersion });
        let actionArg = "default=" + actionText;

        let script = 'if command -v notify-send >/dev/null 2>&1; then ' +
            'ACTION=$(notify-send -a "' + appName.replace(/"/g, '\\"') + '" ' +
            '-i "software-update-available" ' +
            '-A "' + actionArg.replace(/"/g, '\\"') + '" ' +
            '"' + notifTitle.replace(/"/g, '\\"') + '" ' +
            '"' + notifBody.replace(/"/g, '\\"') + '"); ' +
            'if [ "$ACTION" = "default" ]; then ' +
            'echo "about" > "' + guideDir + '/last_tab.txt"; ' +
            'DIR="' + serpDir + '"; ' +
            'if [ -n "$DIR" ] && [ -f "$DIR/scripts/qs_manager.sh" ]; then ' +
            'bash "$DIR/scripts/qs_manager.sh" toggle guide; ' +
            'fi; fi; fi';
        Quickshell.execDetached(["bash", "-c", script]);
    }

    function checkUpdate() {
        if (typeof SystemInfo !== "undefined" && SystemInfo.osName.toLowerCase().indexOf("nixos") !== -1) return;
        if (typeof Caching === "undefined" || !Caching.serpantinumDir) return;
        if (updateProc.running) return;
        root.isChecking = true;
        updateProc.running = true;
    }

    function scheduleInitialCheck() {
        if (typeof SystemInfo !== "undefined" && SystemInfo.osName.toLowerCase().indexOf("nixos") !== -1) return;
        if (typeof Caching === "undefined" || !Caching.serpantinumDir) return;
        if (checkDelayProc.running) return;
        checkDelayProc.running = true;
    }

    FileView {
        id: pkgVersionFileView
        path: (typeof Caching !== "undefined" && Caching.serpantinumDir ? Caching.serpantinumDir : "") + "/version.txt"
        onFileChanged: {
            pkgVersionFileView.reload();
        }
        onLoaded: {
            let content = this.text();
            if (!content) return;
            let v = content.trim();
            if (v) {
                root.packageVersion = v;
                root.syncLocalVersion();
            }
        }
    }

    FileView {
        id: versionFileView
        path: (typeof Caching !== "undefined" ? Caching.getStateDir() : "") + "/version"
        onFileChanged: {
            versionFileView.reload();
        }
        onLoaded: {
            let content = this.text();
            if (!content) return;
            let lines = content.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("SERPANTINUM_VERSION=") === 0) {
                    let v = line.substring("SERPANTINUM_VERSION=".length).replace(/["']/g, "").trim();
                    if (v) {
                        root.stateVersion = v;
                        root.syncLocalVersion();
                    }
                    break;
                }
            }
        }
    }

    Timer {
        id: startupTimer
        interval: 500
        repeat: false
        running: true
        onTriggered: root.scheduleInitialCheck()
    }

    Timer {
        id: initialDelayTimer
        interval: 1500
        repeat: false
        running: false
        onTriggered: {
            root.checkUpdate();
            periodicTimer.restart();
        }
    }

    Timer {
        id: periodicTimer
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.checkUpdate()
    }

    Process {
        id: checkDelayProc
        running: false
        command: [
            "python3",
            (typeof Caching !== "undefined" ? Caching.serpantinumDir : "") + "/scripts/updater.py",
            "--state-dir",
            (typeof Caching !== "undefined" ? Caching.getStateDir() : ""),
            "--delay"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                let delay = parseInt(out, 10);
                if (isNaN(delay) || delay <= 0) {
                    initialDelayTimer.interval = 1500;
                } else {
                    initialDelayTimer.interval = Math.max(1500, delay);
                }
                initialDelayTimer.running = true;
            }
        }
    }

    Process {
        id: updateProc
        running: false
        command: [
            "python3",
            (typeof Caching !== "undefined" ? Caching.serpantinumDir : "") + "/scripts/updater.py",
            "--state-dir",
            (typeof Caching !== "undefined" ? Caching.getStateDir() : "")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") {
                    try {
                        let data = JSON.parse(out);
                        if (data.local) root.localVersion = data.local;
                        if (data.remote) root.remoteVersion = data.remote;
                        if (data.last_notified !== undefined) root.lastNotifiedVersion = data.last_notified;
                        root.reevaluateUpdate();

                        if (root.updateAvailable && root.remoteVersion !== root.lastNotifiedVersion) {
                            root.lastNotifiedVersion = root.remoteVersion;
                            root.saveNotifiedVersion(root.remoteVersion);
                            root.sendNotification();
                        }
                    } catch (e) {}
                }
            }
        }
        onExited: {
            root.isChecking = false;
        }
    }
}
