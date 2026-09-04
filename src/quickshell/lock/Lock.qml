import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import "../"
import "../reusables"
import "../notifications"

Scope {
    id: root

    property string freezeTimestamp: ""
    property bool isUnlocking: false

    property bool isNiri: false
    property bool isSway: false
    property string kbLayout: "US"
    property int connectedScreenCount: 1

    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : SystemInfo.isDesktop
    readonly property int batCap: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property string batPercent: batCap + "%"
    readonly property string batStatus: UPower.displayDevice.ready ? (UPower.displayDevice.state === UPowerDeviceState.FullyCharged ? "Full" : (UPower.displayDevice.state === UPowerDeviceState.Charging ? "Charging" : "Unknown")) : "Unknown"
    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property string batIcon: isCharging ? "󰂄" : (batCap > 20 ? "󰁹" : "󰂃")

    readonly property color batDynamicColor: {
        if (batCap <= 15 && !isCharging) return ThemeBackend.red;
        if (batCap <= 25 && !isCharging) return ThemeBackend.peach;
        if (isCharging) return ThemeBackend.green;
        return ThemeBackend.text;
    }

    function updateDeInfo() {
        let de = SystemInfo.desktopEnv ? SystemInfo.desktopEnv.toLowerCase() : "";
        root.isNiri = de.indexOf("niri") !== -1;
        root.isSway = de.indexOf("sway") !== -1;
    }

    function updateScreenCount() {
        root.connectedScreenCount = Quickshell.screens ? Quickshell.screens.length : 1;
    }

    Component.onCompleted: {
        SystemInfo.fetch();
        root.updateDeInfo();
        root.updateScreenCount();
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.updateScreenCount();
        }
    }

    function switchKbLayout() {
        root.updateDeInfo();
        if (root.isNiri) {
            Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]);
        } else if (root.isSway) {
            Quickshell.execDetached(["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"]);
        } else {
            Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
        }
    }

    Timer {
        id: kbPollerRestartTimer
        interval: 400
        repeat: false
        onTriggered: {
            kbWaiter.running = false;
            kbPoller.running = false;
            if (rootLock.locked) kbPoller.running = true;
        }
    }

    Process {
        id: kbPoller
        running: rootLock.locked
        command: [
            "bash",
            "-c",
            root.isNiri
                ? "layout=$(niri msg -j keyboard-layouts 2>/dev/null | jq -r '.names[.current_idx] // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'"
                : (root.isSway
                    ? "layout=$(swaymsg -t get_inputs 2>/dev/null | jq -r '[.[] | select(.type == \"keyboard\" and .xkb_active_layout_name != null)] | .[0].xkb_active_layout_name // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'"
                    : "layout=$(LC_ALL=C hyprctl devices -j 2>/dev/null | jq -r '(.keyboards[] | select(.main == true) | .active_keymap) // .keyboards[0].active_keymap // empty' | head -n1); [[ -z \"$layout\" || \"$layout\" == \"null\" ]] && layout=\"US\"; echo \"${layout:0:2}\" | tr '[:lower:]' '[:upper:]'")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "" && root.kbLayout !== txt) root.kbLayout = txt;
                kbWaiter.running = false;
                if (rootLock.locked) kbWaiter.running = true;
            }
        }
    }

    Process {
        id: kbWaiter
        command: [
            "bash",
            Caching.qsDir + "/watchers/kb_wait.sh",
            root.isNiri ? "niri" : (root.isSway ? "sway" : "hyprland")
        ]
        onExited: {
            kbPoller.running = false;
            if (rootLock.locked) kbPoller.running = true;
        }
    }

    Process {
        id: grimLockSnapProcess
        property string timeStamp: ""
        property var screenNames: []

        command: {
            let ts = timeStamp;
            let dir = Caching.getRunDir("screenshot");
            let cmd = "dir=\"" + dir + "\"; mkdir -p \"$dir\"; ";
            let mons = screenNames;
            if (mons && mons.length > 0) {
                for (let i = 0; i < mons.length; i++) {
                    let m = mons[i];
                    cmd += "grim -o \"" + m + "\" -l 0 \"$dir/lock_freeze_" + m + "_" + ts + ".png\" & ";
                }
                cmd += "wait; ";
                let firstMon = mons[0];
                cmd += "ln -sf \"$dir/lock_freeze_" + firstMon + "_" + ts + ".png\" \"$dir/lock_freeze_default_" + ts + ".png\" 2>/dev/null || cp -f \"$dir/lock_freeze_" + firstMon + "_" + ts + ".png\" \"$dir/lock_freeze_default_" + ts + ".png\" 2>/dev/null || true;";
            } else {
                cmd += "grim -l 0 \"$dir/lock_freeze_default_" + ts + ".png\" || exit 1;";
            }
            return ["bash", "-c", cmd];
        }

        onExited: (exitCode) => {
            grimTimeoutTimer.stop();
            if (exitCode === 0) {
                root.freezeTimestamp = timeStamp;
            } else {
                root.freezeTimestamp = "";
            }
            root.doLock();
        }
    }

    Timer {
        id: grimTimeoutTimer
        interval: 500
        repeat: false
        onTriggered: {
            grimLockSnapProcess.running = false;
            root.doLock();
        }
    }

    function lock() {
        if (rootLock.locked) return;
        let ts = Date.now().toString();
        let mons = [];
        if (Quickshell.screens) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i] && Quickshell.screens[i].name) {
                    mons.push(Quickshell.screens[i].name);
                }
            }
        }
        grimLockSnapProcess.screenNames = mons;
        grimLockSnapProcess.timeStamp = ts;
        grimLockSnapProcess.running = false;
        grimLockSnapProcess.running = true;
        grimTimeoutTimer.restart();
    }

    function doLock() {
        grimTimeoutTimer.stop();
        SystemInfo.fetch();
        root.updateDeInfo();
        root.updateScreenCount();
        root.isUnlocking = false;
        lockUI.failed = false;
        lockUI.authenticating = false;
        lockUI.statusText = I18n.t("lock.status.locked");
        rootLock.locked = true;
        pamActionTimer.start();
        kbPollerRestartTimer.restart();
    }

    function startAuth() {
        lockUI.failed = false;
        lockUI.authenticating = true;
        lockUI.statusText = I18n.t("lock.status.authenticating");
        pam.start();
    }

    function finishUnlock() {
        if (root.isUnlocking) return;
        root.isUnlocking = true;
    }

    function completeUnlock() {
        if (!rootLock.locked) return;
        rootLock.locked = false;
        root.isUnlocking = false;
        kbWaiter.running = false;
        kbPoller.running = false;
        if (root.freezeTimestamp !== "") {
            Quickshell.execDetached(["bash", "-c", "rm -f " + Caching.getRunDir("screenshot") + "/lock_freeze_*_" + root.freezeTimestamp + ".png"]);
            root.freezeTimestamp = "";
        }
    }

    IpcHandler {
        target: "lock"
        function activate(): void {
            root.lock();
        }
    }

    Settings {
        id: lockSettings
        category: "LockScreen"
        property bool hidePassword: false
        property int revealDuration: 300
    }

    QtObject {
        id: lockUI
        property bool failed: false
        property bool authenticating: false
        property string statusText: I18n.t("lock.status.locked")
    }

    Timer {
        id: pamActionTimer
        interval: 350
        onTriggered: {
            if (rootLock.locked) {
                startAuth();
            }
        }
    }

    PamContext {
        id: pam

        onPamMessage: {
            if (pam.message !== "") {
                if (pam.messageIsError) {
                    lockUI.statusText = I18n.t("lock.status.fingerprint_retry");
                } else {
                    lockUI.statusText = pam.message;
                }
                lockUI.failed = pam.messageIsError;
            }
        }

        onCompleted: (result) => {
            lockUI.authenticating = false;
            if (result === PamResult.Success) {
                root.finishUnlock();
            } else {
                lockUI.failed = true;
                lockUI.statusText = I18n.t("lock.status.access_denied");
                pamActionTimer.start();
            }
        }
    }

    Process {
        id: suspendProcess
        command: ["bash", Caching.serpantinumDir + "/scripts/system/suspend.sh"]
        onExited: {
            SystemInfo.fetch();
            root.updateDeInfo();
            pamActionTimer.restart();
            kbPollerRestartTimer.restart();
            if (rootLock.locked) {
                startAuth();
            }
        }
    }

    Process {
        id: poweroffProcess
        command: ["bash", Caching.serpantinumDir + "/scripts/system/poweroff.sh"]
    }

    Process {
        id: reloadProcess
        command: ["bash", Caching.serpantinumDir + "/scripts/system/reboot.sh"]
    }

    WlSessionLock {
        id: rootLock
        locked: false

        surface: Component {
            WlSessionLockSurface {
                id: surface

                FocusScope {
                    id: screenRoot
                    anchors.fill: parent
                    focus: true

                    Rectangle {
                        anchors.fill: parent
                        color: ThemeBackend.crust
                        z: -1
                    }

                    function s(val) {
                        return Scaler.s(val);
                    }

                    property string safeScreenName: (surface.screen && surface.screen.name) ? surface.screen.name : (surface.output && surface.output.name ? surface.output.name : "")
                    property string wallpaperSource: {
                        let cacheDir = Caching.getCacheDir("wallpaper");
                        if (safeScreenName !== "" && safeScreenName !== "default") {
                            return "file://" + cacheDir + "/current_wallpaper_" + safeScreenName + ".png";
                        }
                        return "file://" + cacheDir + "/current_wallpaper.png";
                    }
                    property string currentFreezePath: {
                        if (root.freezeTimestamp === "") return "";
                        let scrName = (safeScreenName !== "" && safeScreenName !== "default") ? safeScreenName : "default";
                        return Caching.getRunDir("screenshot") + "/lock_freeze_" + scrName + "_" + root.freezeTimestamp + ".png";
                    }

                    property bool isUnlocking: root.isUnlocking
                    property real foldScaleX: 1.0
                    property real foldScaleY: 1.0

                    property bool wingsEverNeeded: false

                    onIsUnlockingChanged: {
                        if (isUnlocking) {
                            openDashboardAnim.stop();
                            closeDashboardAnim.stop();
                            unlockSequence.restart();
                        } else {
                            foldScaleX = 1.0;
                            foldScaleY = 1.0;
                            mainOpacity = 1.0;
                        }
                    }

                    property string currentUser: SystemInfo.username !== "" ? SystemInfo.username : I18n.t("lock.default_user")
                    property string faceIconPath: SystemInfo.avatarPath !== "" ? (SystemInfo.avatarPath.startsWith("file://") ? SystemInfo.avatarPath : "file://" + SystemInfo.avatarPath) : ""
                    property string weatherIcon: Weather.currentIcon
                    property string weatherTemp: Weather.currentTempFormatted

                    property bool dndEnabled: {
                        let n = Config.getSetting("notifications", { "dnd": false });
                        return Boolean(n && n.dnd);
                    }

                    property var weatherFullData: Weather.data
                    property var hourlyForecastList: []

                    function formatHour(timeStr) {
                        if (!timeStr) return "";
                        let str = String(timeStr).trim();
                        if (str.toLowerCase().indexOf("am") !== -1 || str.toLowerCase().indexOf("pm") !== -1) {
                            return str;
                        }
                        let hour = 0;
                        if (str.indexOf(":") !== -1) {
                            hour = parseInt(str.split(":")[0], 10);
                        } else {
                            let num = parseInt(str, 10);
                            if (!isNaN(num)) {
                                hour = num >= 100 ? Math.floor(num / 100) : num;
                            }
                        }
                        if (isNaN(hour)) return str;

                        if (typeof DateTime !== "undefined" && DateTime.is12Hour) {
                            let period = hour >= 12 ? "PM" : "AM";
                            let h12 = hour % 12;
                            if (h12 === 0) h12 = 12;
                            return h12 + period;
                        }

                        return (hour < 10 ? "0" + hour : hour) + ":00";
                    }

                    function getFeelsLike() {
                        let wData = Weather.data;
                        if (!wData) return Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°";
                        let fl = wData.current_feels_like ?? wData.feels_like ?? wData.current_feelslike;
                        if (fl !== undefined && fl !== null && fl !== "") {
                            return Math.round(parseFloat(fl)) + "°";
                        }
                        if (wData.forecast && wData.forecast[0]) {
                            let f0 = wData.forecast[0];
                            if (f0.feels_like !== undefined) return Math.round(parseFloat(f0.feels_like)) + "°";
                            if (f0.hourly && f0.hourly[0] && f0.hourly[0].feels_like !== undefined) {
                                return Math.round(parseFloat(f0.hourly[0].feels_like)) + "°";
                            }
                        }
                        if (Weather.currentTemp !== "") {
                            return Math.round(parseFloat(Weather.currentTemp)) + "°";
                        }
                        return "--°";
                    }

                    function updateForecastData() {
                        let wData = Weather.data;
                        if (!wData || !wData.forecast || !Array.isArray(wData.forecast) || wData.forecast.length === 0) {
                            screenRoot.hourlyForecastList = [];
                            return;
                        }

                        let allHourly = [];
                        for (let d = 0; d < wData.forecast.length; d++) {
                            if (wData.forecast[d] && wData.forecast[d].hourly) {
                                allHourly = allHourly.concat(wData.forecast[d].hourly);
                            }
                        }

                        if (allHourly.length === 0) {
                            screenRoot.hourlyForecastList = [];
                            return;
                        }

                        let ch = (typeof DateTime !== "undefined" && DateTime.now) ? DateTime.now.getHours() : new Date().getHours();
                        let bestIdx = 0;
                        let minDiff = 999;
                        for (let i = 0; i < allHourly.length; i++) {
                            let timeStr = allHourly[i].time || "00:00";
                            let h = parseInt(timeStr.split(":")[0], 10);
                            if (isNaN(h)) {
                                let n = parseInt(timeStr, 10);
                                h = n >= 100 ? Math.floor(n / 100) : n;
                            }
                            let diff = h - ch;
                            if (diff >= 0 && diff < minDiff) {
                                minDiff = diff;
                                bestIdx = i;
                            }
                        }

                        if (minDiff === 999) {
                            for (let i = 0; i < allHourly.length; i++) {
                                let timeStr = allHourly[i].time || "00:00";
                                let h = parseInt(timeStr.split(":")[0], 10);
                                if (isNaN(h)) {
                                    let n = parseInt(timeStr, 10);
                                    h = n >= 100 ? Math.floor(n / 100) : n;
                                }
                                let diff = Math.abs(h - ch);
                                if (diff < minDiff) {
                                    minDiff = diff;
                                    bestIdx = i;
                                }
                            }
                        }

                        screenRoot.hourlyForecastList = allHourly.slice(bestIdx, bestIdx + 4);
                    }

                    onWeatherFullDataChanged: updateForecastData()

                    Connections {
                        target: typeof DateTime !== "undefined" ? DateTime : null
                        function onHourChanged() {
                            screenRoot.updateForecastData();
                        }
                    }

                    property var player: MprisController.activePlayer
                    property bool isMediaActive: player !== null && player.playbackState !== MprisPlaybackState.Stopped && player.trackTitle !== ""

                    function formatMusicTime(sec) {
                        sec = Math.floor(sec || 0);
                        let m = Math.floor(sec / 60), s = sec % 60;
                        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }

                    property bool powerMenuOpen: false
                    property bool inputActive: false
                    property bool isPlayingIntro: true

                    property real centerReveal: 0.0
                    property real wingsReveal: 0.0

                    function restoreFocus() {
                        if (!rootLock.locked || screenRoot.isUnlocking) return;
                        if (screenRoot.inputActive) {
                            if (!passwordInput.activeFocus) {
                                screenRoot.focus = true;
                                screenRoot.forceActiveFocus();
                                passwordInput.focus = true;
                                passwordInput.forceInputFocus();
                            }
                        } else {
                            if (!screenRoot.activeFocus) {
                                screenRoot.focus = true;
                                screenRoot.forceActiveFocus();
                            }
                        }
                    }

                    onActiveFocusChanged: {
                        if (!activeFocus && rootLock.locked && !isUnlocking) {
                            Qt.callLater(screenRoot.restoreFocus);
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (!screenRoot.isPlayingIntro && !screenRoot.isUnlocking) {
                            if (!screenRoot.inputActive) {
                                if (event.key !== Qt.Key_Escape) {
                                    screenRoot.inputActive = true;
                                    screenRoot.restoreFocus();
                                    if (event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backspace) {
                                        passwordInput.insertText(event.text);
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    SequentialAnimation {
                        id: openDashboardAnim
                        running: false
                        NumberAnimation {
                            target: screenRoot
                            property: "centerReveal"
                            to: 1.0
                            duration: 180
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                        }
                        NumberAnimation {
                            target: screenRoot
                            property: "wingsReveal"
                            to: 1.0
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.12
                        }
                    }

                    ParallelAnimation {
                        id: closeDashboardAnim
                        running: false
                        NumberAnimation {
                            target: screenRoot
                            property: "wingsReveal"
                            to: 0.0
                            duration: 110
                            easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: screenRoot
                            property: "centerReveal"
                            to: 0.0
                            duration: 100
                            easing.type: Easing.InQuad
                        }
                    }

                    SequentialAnimation {
                        id: unlockSequence
                        running: false

                        ScriptAction {
                            script: {
                                screenRoot.powerMenuOpen = false;
                            }
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: screenRoot
                                property: "wingsReveal"
                                to: 0.0
                                duration: 130
                                easing.type: Easing.InQuad
                            }
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: screenRoot
                                property: "foldScaleX"
                                to: 0.0
                                duration: 220
                                easing.type: Easing.InBack
                                easing.overshoot: 1.3
                            }
                            NumberAnimation {
                                target: screenRoot
                                property: "foldScaleY"
                                to: 0.0
                                duration: 220
                                easing.type: Easing.InBack
                                easing.overshoot: 1.3
                            }
                            NumberAnimation {
                                target: screenRoot
                                property: "centerReveal"
                                to: 0.0
                                duration: 200
                                easing.type: Easing.InQuad
                            }
                            NumberAnimation {
                                target: screenRoot
                                property: "contentReveal"
                                to: 0.0
                                duration: 220
                                easing.type: Easing.InQuad
                            }
                            NumberAnimation {
                                target: screenRoot
                                property: "panelReveal"
                                to: 0.0
                                duration: 250
                                easing.type: Easing.InOutCubic
                            }
                            NumberAnimation {
                                target: screenRoot
                                property: "mainOpacity"
                                to: 0.0
                                duration: 250
                                easing.type: Easing.InQuad
                            }
                        }

                        ScriptAction {
                            script: {
                                root.completeUnlock();
                            }
                        }
                    }

                    onInputActiveChanged: {
                        if (screenRoot.isUnlocking) return;
                        if (inputActive) {
                            closeDashboardAnim.stop();
                            openDashboardAnim.restart();
                            screenRoot.restoreFocus();
                        } else {
                            openDashboardAnim.stop();
                            closeDashboardAnim.restart();
                            powerMenuOpen = false;
                            screenRoot.restoreFocus();
                        }
                    }

                    property real panelReveal: 0.0
                    property real contentReveal: 0.0
                    property real mainOpacity: 1.0

                    property bool isSysSubscribed: false
                    property bool isCavaSubscribed: false
                    function updateSysSubscription() {
                        if (screenRoot.wingsReveal > 0.98 && !isSysSubscribed) {
                            SysData.subscribe();
                            isSysSubscribed = true;
                        } else if (screenRoot.wingsReveal <= 0.98 && isSysSubscribed) {
                            SysData.unsubscribe();
                            isSysSubscribed = false;
                        }
                    }

                    function updateCavaConsumer() {
                        let shouldSubscribe = screenRoot.wingsReveal > 0.98;
                        if (shouldSubscribe && !screenRoot.isCavaSubscribed) {
                            Cava.registerConsumer();
                            screenRoot.isCavaSubscribed = true;
                        } else if (!shouldSubscribe && screenRoot.isCavaSubscribed) {
                            Cava.unregisterConsumer();
                            screenRoot.isCavaSubscribed = false;
                        }
                    }

                    onWingsRevealChanged: {
                        if (wingsReveal > 0 && !wingsEverNeeded) wingsEverNeeded = true;
                        updateSysSubscription();
                        updateCavaConsumer();
                    }

                    property real globalWavePhase: 0.0
                    NumberAnimation on globalWavePhase {
                        from: 0; to: Math.PI * 2; duration: 1800; loops: Animation.Infinite; running: screenRoot.wingsReveal > 0.98
                    }

                    property real rawCpu: isNaN(SysData.cpu) ? 0.0 : SysData.cpu / 100.0
                    property real cpuUsage: rawCpu
                    Behavior on cpuUsage { enabled: screenRoot.wingsReveal > 0.98; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

                    property real rawTemp: isNaN(SysData.temp) ? 0.0 : SysData.temp
                    property real tempC: rawTemp
                    Behavior on tempC { enabled: screenRoot.wingsReveal > 0.98; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

                    property real rawRam: isNaN(SysData.ramPercent) ? 0.0 : SysData.ramPercent / 100.0
                    property real ramUsage: rawRam
                    Behavior on ramUsage { enabled: screenRoot.wingsReveal > 0.98; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

                    property real rawRamGb: isNaN(SysData.ramGb) ? 0.0 : SysData.ramGb
                    property real ramUsedGb: rawRamGb
                    Behavior on ramUsedGb { enabled: screenRoot.wingsReveal > 0.98; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

                    property real netRx: isNaN(SysData.netRx) ? 0 : SysData.netRx
                    property real netTx: isNaN(SysData.netTx) ? 0 : SysData.netTx
                    function formatBytes(bytes) {
                        if (bytes <= 0 || isNaN(bytes)) return "0 B/s";
                        let k = 1024, sizes = ["B/s", "KB/s", "MB/s", "GB/s"];
                        let i = Math.floor(Math.log(bytes) / Math.log(k));
                        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
                    }
                    property string rxSpeedStr: formatBytes(netRx)
                    property string txSpeedStr: formatBytes(netTx)

                    property real rawDisk: isNaN(SysData.diskPercent) ? 0.0 : SysData.diskPercent / 100.0
                    property real diskUsagePercent: rawDisk
                    Behavior on diskUsagePercent { enabled: screenRoot.wingsReveal > 0.98; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

                    property string diskUsedText: SysData.diskGb > 0 ? (SysData.diskGb.toFixed(1) + "G") : "..."
                    property string diskTotalText: SysData.diskTotalGb > 0 ? (SysData.diskTotalGb.toFixed(1) + "G") : ""

                    component LiquidCard: Item {
                        id: lc
                        property real value: 0.0
                        property color colorBase: Qt.lighter(ThemeBackend.surface0, 1.28)
                        property color colorFill: ThemeBackend.mauve
                        property string icon: ""
                        property string title: ""
                        property string midText: ""
                        property string valueText: ""
                        property string subText: ""
                        property real cardRadius: screenRoot.s(14)

                        default property alias childItems: customContentBox.data

                        property real fillRatio: Math.max(0.0, Math.min(1.0, lc.value))
                        property real fillY: height * (1.0 - lc.fillRatio)
                        property real waveAmp: (lc.fillRatio < 0.99 && lc.fillRatio > 0.01) ? screenRoot.s(4) * Math.sin(lc.fillRatio * Math.PI) : 0
                        property real waveCenterOffset: lc.waveAmp > 0 ? 0.375 * lc.waveAmp * (Math.sin(screenRoot.globalWavePhase) - Math.cos(screenRoot.globalWavePhase)) : 0

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: screenRoot.s(2)
                            anchors.bottomMargin: -screenRoot.s(2)
                            radius: lc.cardRadius
                            color: Qt.rgba(0, 0, 0, 0.22)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: lc.cardRadius
                            color: lc.colorBase
                            border.width: 1
                            border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                        }

                        Canvas {
                            id: fluidCanvasItem
                            anchors.fill: parent
                            renderTarget: Canvas.FramebufferObject
                            renderStrategy: Canvas.Immediate

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                if (lc.value <= 0) return;

                                ctx.save();
                                var r = lc.cardRadius;
                                ctx.beginPath();
                                ctx.moveTo(r, 0);
                                ctx.lineTo(width - r, 0);
                                ctx.quadraticCurveTo(width, 0, width, r);
                                ctx.lineTo(width, height - r);
                                ctx.quadraticCurveTo(width, height, width - r, height);
                                ctx.lineTo(r, height);
                                ctx.quadraticCurveTo(0, height, 0, height - r);
                                ctx.lineTo(0, r);
                                ctx.quadraticCurveTo(0, 0, r, 0);
                                ctx.closePath();
                                ctx.clip();

                                ctx.beginPath();
                                ctx.moveTo(0, lc.fillY);
                                if (lc.waveAmp > 0) {
                                    var sinPhase = Math.sin(screenRoot.globalWavePhase);
                                    var cosPhase = Math.cos(screenRoot.globalWavePhase + Math.PI);
                                    var cp1y = lc.fillY + sinPhase * lc.waveAmp;
                                    var cp2y = lc.fillY + cosPhase * lc.waveAmp;
                                    ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, lc.fillY);
                                    ctx.lineTo(width, height);
                                    ctx.lineTo(0, height);
                                } else {
                                    ctx.lineTo(width, lc.fillY);
                                    ctx.lineTo(width, height);
                                    ctx.lineTo(0, height);
                                }
                                ctx.closePath();

                                var grad = ctx.createLinearGradient(0, 0, 0, height);
                                grad.addColorStop(0, Qt.lighter(lc.colorFill, 1.18).toString());
                                grad.addColorStop(1, lc.colorFill.toString());
                                ctx.fillStyle = grad;
                                ctx.globalAlpha = 0.94;
                                ctx.fill();
                                ctx.restore();
                            }

                            Connections {
                                target: screenRoot
                                enabled: screenRoot.wingsReveal > 0.98 && lc.waveAmp > 0
                                function onGlobalWavePhaseChanged() { fluidCanvasItem.requestPaint(); }
                            }

                            Connections {
                                target: lc
                                enabled: screenRoot.wingsReveal > 0.98
                                function onValueChanged() { fluidCanvasItem.requestPaint(); }
                                function onColorFillChanged() { fluidCanvasItem.requestPaint(); }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: screenRoot.s(10)

                            IconButton {
                                id: baseCardIcon
                                anchors.top: parent.top
                                anchors.left: parent.left
                                size: Math.round(screenRoot.s(26))
                                cornerRadius: Math.round(screenRoot.s(13))
                                accentColor: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.6)
                                textColor: ThemeBackend.subtext0
                                buttonIcon: lc.icon
                                iconFontSize: Math.round(screenRoot.s(14))
                                enabled: false
                            }

                            Row {
                                anchors.verticalCenter: baseCardIcon.verticalCenter
                                anchors.right: parent.right
                                spacing: screenRoot.s(4)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.DemiBold
                                    font.pixelSize: screenRoot.s(10.5)
                                    color: Qt.rgba(ThemeBackend.subtext0.r, ThemeBackend.subtext0.g, ThemeBackend.subtext0.b, 0.7)
                                    text: lc.midText
                                    visible: lc.midText !== ""
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.DemiBold
                                    font.pixelSize: screenRoot.s(10.5)
                                    color: ThemeBackend.subtext0
                                    text: lc.title
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.bottomMargin: screenRoot.s(1)
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.DemiBold
                                font.pixelSize: screenRoot.s(11)
                                color: ThemeBackend.subtext0
                                text: lc.subText
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: screenRoot.s(18)
                                color: ThemeBackend.text
                                text: lc.valueText
                            }
                        }

                        Item {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.min(parent.height, Math.max(0, (parent.height * lc.fillRatio) - lc.waveCenterOffset))
                            clip: true
                            visible: lc.value > 0

                            Item {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: lc.height
                                anchors.margins: screenRoot.s(10)

                                IconButton {
                                    id: filledCardIcon
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    size: Math.round(screenRoot.s(26))
                                    cornerRadius: Math.round(screenRoot.s(13))
                                    accentColor: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.15)
                                    textColor: ThemeBackend.crust
                                    buttonIcon: lc.icon
                                    iconFontSize: Math.round(screenRoot.s(14))
                                    enabled: false
                                }

                                Row {
                                    anchors.verticalCenter: filledCardIcon.verticalCenter
                                    anchors.right: parent.right
                                    spacing: screenRoot.s(4)

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.DemiBold
                                        font.pixelSize: screenRoot.s(10.5)
                                        color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.6)
                                        text: lc.midText
                                        visible: lc.midText !== ""
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.DemiBold
                                        font.pixelSize: screenRoot.s(10.5)
                                        color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.85)
                                        text: lc.title
                                    }
                                }

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.bottomMargin: screenRoot.s(1)
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.DemiBold
                                    font.pixelSize: screenRoot.s(11)
                                    color: ThemeBackend.crust
                                    text: lc.subText
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Black
                                    font.pixelSize: screenRoot.s(18)
                                    color: ThemeBackend.crust
                                    text: lc.valueText
                                }
                            }
                        }

                        Item {
                            id: customContentBox
                            anchors.fill: parent
                            anchors.margins: screenRoot.s(10)
                            z: 10
                        }
                    }

                    Component.onCompleted: {
                        introSequence.start();
                        screenRoot.updateForecastData();
                        screenRoot.restoreFocus();
                    }

                    Component.onDestruction: {
                        if (screenRoot.isCavaSubscribed) {
                            Cava.unregisterConsumer();
                            screenRoot.isCavaSubscribed = false;
                        }
                        if (isSysSubscribed) {
                            SysData.unsubscribe();
                            isSysSubscribed = false;
                        }
                    }

                    Connections {
                        target: rootLock
                        function onLockedChanged() {
                            if (rootLock.locked) {
                                focusSyncTimer.restart();
                                screenRoot.restoreFocus();
                            }
                        }
                    }

                    Timer {
                        id: focusSyncTimer
                        interval: 50
                        repeat: true
                        running: rootLock.locked && !screenRoot.isUnlocking
                        triggeredOnStart: true
                        onTriggered: {
                            screenRoot.restoreFocus();
                        }
                    }

                    Timer {
                        id: idleTimer
                        interval: 15000
                        running: screenRoot.inputActive && passwordInput.text.length === 0
                        repeat: false
                        onTriggered: {
                            screenRoot.inputActive = false;
                            screenRoot.restoreFocus();
                        }
                    }

                    Item {
                        id: freezeBackdropLayer
                        anchors.fill: parent
                        z: 0

                        Rectangle {
                            anchors.fill: parent
                            color: ThemeBackend.crust
                        }

                        Image {
                            id: fallbackWallpaperView
                            anchors.fill: parent
                            source: screenRoot.wallpaperSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: false
                            cache: false
                            onStatusChanged: {
                                if (status === Image.Error) {
                                    let defaultPath = "file://" + Caching.getCacheDir("wallpaper") + "/current_wallpaper.png";
                                    if (source.toString() !== defaultPath) {
                                        source = defaultPath;
                                    }
                                }
                            }
                        }

                        Image {
                            id: freezeWallpaperView
                            anchors.fill: parent
                            source: (screenRoot.currentFreezePath !== "" && root.freezeTimestamp !== "") ? ("file://" + screenRoot.currentFreezePath) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: false
                            cache: false
                            opacity: (status === Image.Ready && source.toString() !== "") ? 1.0 : 0.0

                            onStatusChanged: {
                                if (status === Image.Error && root.freezeTimestamp !== "") {
                                    let defaultFreeze = "file://" + Caching.getRunDir("screenshot") + "/lock_freeze_default_" + root.freezeTimestamp + ".png";
                                    if (source.toString() !== defaultFreeze) {
                                        source = defaultFreeze;
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: wallpaperContainer
                        anchors.fill: parent
                        visible: false

                        Image {
                            id: liveWallpaperView
                            anchors.fill: parent
                            source: screenRoot.wallpaperSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false

                            onStatusChanged: {
                                if (status === Image.Error) {
                                    let defaultPath = "file://" + Caching.getCacheDir("wallpaper") + "/current_wallpaper.png";
                                    if (source.toString() !== defaultPath) {
                                        source = defaultPath;
                                    }
                                }
                            }
                        }

                        Image {
                            id: liveFreezeView
                            anchors.fill: parent
                            source: (screenRoot.currentFreezePath !== "" && root.freezeTimestamp !== "") ? ("file://" + screenRoot.currentFreezePath) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: false
                            cache: false
                            opacity: (screenRoot.inputActive && status === Image.Ready && source.toString() !== "") ? 1.0 : 0.0

                            Behavior on opacity {
                                enabled: !screenRoot.isUnlocking
                                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }

                            onStatusChanged: {
                                if (status === Image.Error && root.freezeTimestamp !== "") {
                                    let defaultFreeze = "file://" + Caching.getRunDir("screenshot") + "/lock_freeze_default_" + root.freezeTimestamp + ".png";
                                    if (source.toString() !== defaultFreeze) {
                                        source = defaultFreeze;
                                    }
                                }
                            }
                        }
                    }

                    MultiEffect {
                        id: blurEffect
                        source: wallpaperContainer
                        anchors.fill: parent
                        z: 1
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: screenRoot.s(48)
                        blur: screenRoot.inputActive ? 1.0 : 0.55
                        Behavior on blur {
                            enabled: !screenRoot.isPlayingIntro && !screenRoot.isUnlocking
                            NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                        }
                        opacity: screenRoot.contentReveal
                        visible: opacity > 0.01
                    }

                    Rectangle {
                        id: dimmer
                        anchors.fill: parent
                        z: 2
                        color: ThemeBackend.crust
                        opacity: (screenRoot.inputActive ? 0.72 : 0.32) * screenRoot.contentReveal
                        Behavior on opacity {
                            enabled: !screenRoot.isPlayingIntro && !screenRoot.isUnlocking
                            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                        }
                    }

                    Canvas {
                        id: wipeCanvas
                        anchors.fill: parent
                        z: 10
                        renderTarget: Canvas.FramebufferObject
                        renderStrategy: Canvas.Immediate

                        property real lastPaintedRev: -1
                        property real cachedS28: screenRoot.s(28)

                        readonly property var wipeColors: [
                            ThemeBackend.crust.toString(),
                            ThemeBackend.surface1.toString(),
                            ThemeBackend.blue.toString(),
                            ThemeBackend.mauve.toString(),
                            ThemeBackend.surface0.toString()
                        ]
                        readonly property var wipeAmps: [1.5, 1.3, 1.1, 0.9, 0.6]
                        readonly property var wipeOffsets: [0.0, 0.5, 1.0, 1.5, 2.0]

                        opacity: screenRoot.isPlayingIntro ? (screenRoot.panelReveal < 0.8 ? 1.0 : Math.max(0.0, (1.0 - screenRoot.panelReveal) / 0.2)) : 0.0
                        visible: opacity > 0.001

                        Connections {
                            target: screenRoot
                            enabled: screenRoot.isPlayingIntro && wipeCanvas.visible
                            function onPanelRevealChanged() {
                                if (Math.abs(screenRoot.panelReveal - wipeCanvas.lastPaintedRev) >= 0.005) {
                                    wipeCanvas.requestPaint();
                                }
                            }
                        }

                        onPaint: {
                            var rev = screenRoot.panelReveal;
                            lastPaintedRev = rev;
                            if (rev <= 0.0) return;

                            var ctx = getContext("2d");
                            var w = width;
                            var h = height;

                            var lastFull = -1;
                            for (var k = 4; k >= 0; k--) {
                                var p = (rev - (k === 0 ? 0.0 : k * 0.07)) * 1.55;
                                if (p >= 1.0) {
                                    lastFull = k;
                                    break;
                                }
                            }

                            if (lastFull >= 0) {
                                ctx.fillStyle = wipeColors[lastFull];
                                ctx.fillRect(0, 0, w, h);
                            } else {
                                ctx.clearRect(0, 0, w, h);
                            }

                            var start = lastFull + 1;
                            if (start >= 5) return;

                            var phase = rev * 7.853981633974483;
                            var s28 = cachedS28;
                            var cp1x = w * 0.38;
                            var cp2x = w * 0.72;
                            var pi = 3.141592653589793;

                            for (var i = start; i < 5; i++) {
                                var prog = (rev - (i === 0 ? 0.0 : i * 0.07)) * 1.55;
                                if (prog <= 0.0) continue;

                                var smoothProg = Math.pow(prog, 1.4);
                                var currentY = h * smoothProg;
                                var waveAmp = s28 * Math.sin(smoothProg * pi) * wipeAmps[i];

                                var cp1y = currentY + Math.sin(phase + wipeOffsets[i]) * waveAmp;
                                var cp2y = currentY + Math.cos(phase + wipeOffsets[i] + pi) * waveAmp;

                                ctx.beginPath();
                                ctx.moveTo(0, 0);
                                ctx.lineTo(0, currentY);
                                ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, w, currentY);
                                ctx.lineTo(w, 0);
                                ctx.closePath();
                                ctx.fillStyle = wipeColors[i];
                                ctx.fill();
                            }
                        }
                    }

                    SequentialAnimation {
                        id: introSequence

                        ParallelAnimation {
                            NumberAnimation {
                                target: screenRoot
                                property: "panelReveal"
                                from: 0.0
                                to: 1.0
                                duration: 750
                                easing.type: Easing.OutCubic
                            }

                            SequentialAnimation {
                                PauseAnimation { duration: 200 }
                                NumberAnimation {
                                    target: screenRoot
                                    property: "contentReveal"
                                    from: 0.0
                                    to: 1.0
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        PropertyAction { target: screenRoot; property: "isPlayingIntro"; value: false }
                        ScriptAction {
                            script: {
                                screenRoot.restoreFocus();
                            }
                        }
                    }

                    Item {
                        id: rootContent
                        anchors.fill: parent
                        z: 20
                        opacity: screenRoot.mainOpacity

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            enabled: !screenRoot.isPlayingIntro && !screenRoot.isUnlocking
                            onPressed: {
                                screenRoot.restoreFocus();
                            }
                            onClicked: {
                                if (screenRoot.powerMenuOpen) screenRoot.powerMenuOpen = false;
                                if (!screenRoot.inputActive) {
                                    screenRoot.inputActive = true;
                                }
                                screenRoot.restoreFocus();
                            }
                        }

                        Item {
                            anchors.fill: parent
                            opacity: screenRoot.contentReveal
                            transform: Translate { y: screenRoot.s(20) * (1.0 - screenRoot.contentReveal) }

                            ColumnLayout {
                                id: clockModule
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: screenRoot.inputActive ? screenRoot.s(-280) : screenRoot.s(-130)
                                spacing: screenRoot.s(8)

                                opacity: (screenRoot.inputActive || screenRoot.centerReveal > 0.02) ? 0.0 : 1.0
                                scale: (screenRoot.inputActive || screenRoot.centerReveal > 0.02) ? 0.92 : 1.0
                                visible: opacity > 0.01

                                Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: screenRoot.s(4)

                                    Text {
                                        id: clockHours
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: screenRoot.s(120)
                                        font.weight: Font.Normal
                                        color: "#ffffff"
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.25)
                                    }

                                    Text {
                                        id: clockColon
                                        text: ":"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: screenRoot.s(80)
                                        font.weight: Font.Light
                                        Layout.alignment: Qt.AlignVCenter
                                        opacity: colonPulse.running ? colonOpacity : 0.6
                                        color: "#ffffff"
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.25)

                                        property real colonOpacity: 0.6
                                        SequentialAnimation on colonOpacity {
                                            id: colonPulse
                                            running: !screenRoot.isPlayingIntro && !screenRoot.isUnlocking
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.OutCubic }
                                            NumberAnimation { to: 0.35; duration: 500; easing.type: Easing.InCubic }
                                        }
                                    }

                                    Text {
                                        id: clockMinutes
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: screenRoot.s(120)
                                        font.weight: Font.Normal
                                        color: "#ffffff"
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.25)
                                    }

                                    Text {
                                        id: clockAmPm
                                        visible: text !== ""
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: screenRoot.s(28)
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                        opacity: 0.8
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.bottomMargin: screenRoot.s(24)
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.25)
                                    }
                                }

                                Text {
                                    id: dateText
                                    Layout.alignment: Qt.AlignHCenter
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: screenRoot.s(14)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: "#ffffff"
                                    opacity: 0.85
                                }

                                Timer {
                                    id: clockTimer
                                    interval: 1000; running: true; repeat: true; triggeredOnStart: true
                                    onTriggered: {
                                        let d = new Date();
                                        let fmt = (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.time && Config.rawSettings.bar.time.format !== undefined) ? Config.rawSettings.bar.time.format : "HH:mm:ss";
                                        let is12h = fmt.includes("h") || fmt.toLowerCase().includes("ap");
                                        let hourFmt = is12h ? (fmt.includes("hh") ? "hh" : "h") : (fmt.includes("H") && !fmt.includes("HH") ? "H" : "HH");
                                        clockHours.text = Qt.formatDateTime(d, hourFmt);
                                        clockMinutes.text = Qt.formatDateTime(d, "mm");
                                        clockAmPm.text = is12h ? Qt.formatDateTime(d, "AP") : "";
                                        dateText.text = Qt.formatDateTime(d, "dddd, d MMMM").toUpperCase();
                                    }
                                }
                            }

                            Rectangle {
                                id: mainDashboardShell
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: screenRoot.inputActive ? screenRoot.s(0) : screenRoot.s(90)
                                width: Math.min(parent.width - screenRoot.s(48), screenRoot.s(440) + (screenRoot.wingsReveal * screenRoot.s(780)))
                                height: screenRoot.s(540)
                                radius: ThemeBackend.borderRadius * 1.5
                                color: ThemeBackend.surface0
                                border.width: 1.5
                                border.color: ThemeBackend.surface1
                                clip: true

                                opacity: screenRoot.centerReveal
                                scale: 0.92 + (screenRoot.centerReveal * 0.08)
                                visible: opacity > 0.01

                                transform: Scale {
                                    origin.x: mainDashboardShell.width / 2
                                    origin.y: mainDashboardShell.height / 2
                                    xScale: screenRoot.isUnlocking ? screenRoot.foldScaleX : 1.0
                                    yScale: screenRoot.isUnlocking ? screenRoot.foldScaleY : 1.0
                                }

                                Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                                readonly property real leftWingWidth: screenRoot.wingsReveal * screenRoot.s(390)
                                readonly property real centerWidth: screenRoot.s(440)
                                readonly property real rightWingWidth: screenRoot.wingsReveal * screenRoot.s(390)

                                Item {
                                    id: leftWingContainer
                                    x: 0
                                    y: 0
                                    width: mainDashboardShell.leftWingWidth
                                    height: parent.height
                                    clip: true
                                    opacity: screenRoot.wingsReveal
                                    visible: width > 0.5

                                    Loader {
                                        id: leftWingLoader
                                        width: screenRoot.s(390)
                                        height: leftWingContainer.height
                                        active: screenRoot.wingsEverNeeded
                                        asynchronous: true
                                        sourceComponent: leftWingContent
                                    }
                                }

                                Item {
                                    id: centerUserPanel
                                    x: mainDashboardShell.leftWingWidth
                                    y: 0
                                    width: mainDashboardShell.centerWidth
                                    height: parent.height

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: screenRoot.s(24)
                                        spacing: 0

                                        Item { Layout.fillHeight: true; Layout.preferredHeight: screenRoot.s(22) }

                                        ImageBox {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.preferredWidth: screenRoot.s(190)
                                            Layout.preferredHeight: screenRoot.s(190)
                                            size: screenRoot.s(190)
                                            cornerRadius: screenRoot.s(95)
                                            imageRadius: screenRoot.s(95)
                                            source: screenRoot.faceIconPath !== "" ? screenRoot.faceIconPath : (SystemInfo.avatarPath !== "" ? (SystemInfo.avatarPath.startsWith("file://") ? SystemInfo.avatarPath : "file://" + SystemInfo.avatarPath) : "")
                                            backgroundColor: (screenRoot.faceIconPath === "" && SystemInfo.avatarPath === "") ? ThemeBackend.surface1 : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: screenRoot.s(95)
                                                color: ThemeBackend.text
                                                visible: screenRoot.faceIconPath === "" && SystemInfo.avatarPath === ""
                                            }
                                        }

                                        Item { Layout.fillHeight: true; Layout.preferredHeight: screenRoot.s(20) }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: screenRoot.s(14)

                                            ClickButton {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredHeight: screenRoot.s(38)
                                                cornerRadius: ThemeBackend.borderRadius
                                                horizontalPadding: screenRoot.s(16)
                                                buttonIcon: ""
                                                iconFontSize: screenRoot.s(15)
                                                buttonText: screenRoot.currentUser + " • " + lockUI.statusText
                                                textFontSize: screenRoot.s(13)
                                                accentColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                textColor: lockUI.failed ? ThemeBackend.red : (lockUI.authenticating ? ThemeBackend.peach : ThemeBackend.text)
                                            }

                                            PasswordInput {
                                                id: passwordInput
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: screenRoot.s(44)
                                                baseColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                hoverColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                focusColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                activeColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                accentColor: ThemeBackend.mauve
                                                textColor: ThemeBackend.text
                                                subTextColor: ThemeBackend.subtext0
                                                errorColor: ThemeBackend.red
                                                busyColor: ThemeBackend.peach
                                                cornerRadius: ThemeBackend.borderRadius
                                                horizontalPadding: screenRoot.s(12)
                                                fontFamily: ThemeBackend.fontFamily
                                                fontPixelSize: screenRoot.s(14)
                                                horizontalAlignment: TextInput.AlignHCenter
                                                placeholderText: I18n.t("lock.status.enter_pin")
                                                enabled: !screenRoot.isPlayingIntro && !screenRoot.isUnlocking
                                                hasError: lockUI.failed
                                                isBusy: lockUI.authenticating
                                                isWidgetVisible: rootLock.locked && screenRoot.inputActive
                                                isRevealed: !lockSettings.hidePassword

                                                onAccepted: (finalText) => {
                                                    if (finalText.length > 0 && pam.responseRequired && !lockUI.authenticating) {
                                                        lockUI.authenticating = true;
                                                        lockUI.statusText = I18n.t("lock.status.authenticating");
                                                        lockUI.failed = false;
                                                        pam.respond(finalText);
                                                    }
                                                }

                                                onTextEdited: (newText) => {
                                                    if (lockUI.authenticating || screenRoot.isUnlocking) return;
                                                    if (newText.length > 0 && !screenRoot.inputActive) {
                                                        screenRoot.inputActive = true;
                                                    }
                                                    idleTimer.restart();
                                                    if (newText.length > 0) {
                                                        lockUI.failed = false;
                                                        lockUI.statusText = I18n.t("lock.status.enter_pin");
                                                    } else {
                                                        if (!lockUI.failed) lockUI.statusText = I18n.t("lock.status.locked");
                                                    }
                                                }

                                                Keys.onPressed: (event) => {
                                                    if (event.key === Qt.Key_Escape) {
                                                        if (screenRoot.powerMenuOpen) {
                                                            screenRoot.powerMenuOpen = false;
                                                        } else {
                                                            screenRoot.inputActive = false;
                                                        }
                                                        passwordInput.clear();
                                                        screenRoot.restoreFocus();
                                                        event.accepted = true;
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: screenRoot.s(10)

                                                ClickButton {
                                                    id: kbPill
                                                    Layout.preferredHeight: screenRoot.s(32)
                                                    cornerRadius: ThemeBackend.borderRadius
                                                    horizontalPadding: screenRoot.s(12)
                                                    buttonIcon: "󰌌"
                                                    iconFontSize: screenRoot.s(14)
                                                    buttonText: root.kbLayout
                                                    textFontSize: screenRoot.s(12)
                                                    accentColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                    textColor: ThemeBackend.text
                                                    onClicked: root.switchKbLayout()
                                                }

                                                ClickButton {
                                                    id: batPill
                                                    visible: !root.isDesktop
                                                    Layout.preferredHeight: screenRoot.s(32)
                                                    cornerRadius: ThemeBackend.borderRadius
                                                    horizontalPadding: screenRoot.s(12)
                                                    buttonIcon: root.batIcon
                                                    iconFontSize: screenRoot.s(14)
                                                    buttonText: root.batPercent
                                                    textFontSize: screenRoot.s(12)
                                                    accentColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                                    textColor: root.batDynamicColor
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true; Layout.preferredHeight: screenRoot.s(16) }
                                    }
                                }

                                Item {
                                    id: rightWingContainer
                                    x: mainDashboardShell.leftWingWidth + mainDashboardShell.centerWidth
                                    y: 0
                                    width: mainDashboardShell.rightWingWidth
                                    height: parent.height
                                    clip: true
                                    opacity: screenRoot.wingsReveal
                                    visible: width > 0.5

                                    Loader {
                                        id: rightWingLoader
                                        width: screenRoot.s(390)
                                        height: rightWingContainer.height
                                        active: screenRoot.wingsEverNeeded
                                        asynchronous: true
                                        sourceComponent: rightWingContent
                                    }
                                }
                            }

                            Connections {
                                target: lockUI
                                function onFailedChanged() {
                                    if (lockUI.failed) {
                                        passwordInput.triggerShake();
                                        passwordInput.clear();
                                        screenRoot.restoreFocus();
                                    }
                                }
                            }

                            Item {
                                id: bottomInfoTray
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: screenRoot.s(16)
                                anchors.left: parent.left
                                anchors.leftMargin: screenRoot.s(20)
                                anchors.right: parent.right
                                anchors.rightMargin: screenRoot.s(20)
                                height: screenRoot.s(48)

                                opacity: screenRoot.inputActive ? 1.0 : 0.0
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                                IconButton {
                                    id: powerControlToggle
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: screenRoot.s(48)
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonIcon: screenRoot.powerMenuOpen ? "󰅖" : "󰐥"
                                    iconFontSize: screenRoot.s(20)
                                    accentColor: screenRoot.powerMenuOpen ? ThemeBackend.surface2 : Qt.lighter(ThemeBackend.surface0, 1.28)
                                    textColor: screenRoot.powerMenuOpen ? ThemeBackend.text : ThemeBackend.red
                                    onClicked: screenRoot.powerMenuOpen = !screenRoot.powerMenuOpen
                                }
                            }

                            Rectangle {
                                id: powerContainer
                                z: 100

                                Shortcut {
                                    sequence: "Escape"
                                    enabled: screenRoot.powerMenuOpen
                                    onActivated: {
                                        screenRoot.powerMenuOpen = false;
                                        screenRoot.restoreFocus();
                                    }
                                }

                                anchors.bottom: bottomInfoTray.top
                                anchors.bottomMargin: screenRoot.s(16)
                                anchors.right: bottomInfoTray.right

                                width: screenRoot.s(320)
                                height: screenRoot.powerMenuOpen ? (menuLayout.implicitHeight + screenRoot.s(24)) : 0
                                radius: ThemeBackend.borderRadius

                                clip: true
                                visible: height > 0 || opacity > 0
                                opacity: screenRoot.powerMenuOpen ? 1.0 : 0.0

                                color: Qt.rgba(ThemeBackend.surface0.r, ThemeBackend.surface0.g, ThemeBackend.surface0.b, 0.45)
                                border.color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.4)
                                border.width: 1

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 340
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.15
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                ColumnLayout {
                                    id: menuLayout
                                    anchors.top: parent.top
                                    anchors.topMargin: screenRoot.s(12)
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: screenRoot.s(12)
                                    anchors.rightMargin: screenRoot.s(12)
                                    spacing: screenRoot.s(8)

                                    FillButton {
                                        Layout.fillWidth: true
                                        buttonIcon: "󰒲"
                                        buttonText: I18n.t("lock.power.suspend")
                                        accentColor: ThemeBackend.mauve
                                        baseColor: ThemeBackend.surface0
                                        hoverColor: ThemeBackend.surface1
                                        fillDuration: 1200
                                        onTriggered: { screenRoot.powerMenuOpen = false; suspendProcess.running = true; }
                                    }

                                    FillButton {
                                        Layout.fillWidth: true
                                        buttonIcon: "󰑓"
                                        buttonText: I18n.t("lock.power.reboot")
                                        accentColor: ThemeBackend.blue
                                        baseColor: ThemeBackend.surface0
                                        hoverColor: ThemeBackend.surface1
                                        fillDuration: 1200
                                        onTriggered: { screenRoot.powerMenuOpen = false; reloadProcess.running = true; }
                                    }

                                    FillButton {
                                        Layout.fillWidth: true
                                        buttonIcon: "󰐥"
                                        buttonText: I18n.t("lock.power.power_off")
                                        accentColor: ThemeBackend.red
                                        baseColor: ThemeBackend.surface0
                                        hoverColor: ThemeBackend.surface1
                                        fillDuration: 1200
                                        onTriggered: { screenRoot.powerMenuOpen = false; poweroffProcess.running = true; }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: leftWingContent

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: screenRoot.s(14)
                            spacing: screenRoot.s(8)

                            Item {
                                id: weatherBoxFaceContainer
                                Layout.fillWidth: true
                                Layout.preferredHeight: screenRoot.s(182)
                                clip: true

                                property string currentHex: Weather.currentHex
                                property color accentColor: (currentHex && currentHex.length === 7) ? currentHex : ThemeBackend.mauve

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: screenRoot.s(2)
                                    anchors.bottomMargin: -screenRoot.s(2)
                                    radius: screenRoot.s(16)
                                    color: Qt.rgba(0, 0, 0, 0.22)
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: screenRoot.s(16)
                                    color: Qt.lighter(ThemeBackend.surface0, 1.28)
                                    border.width: 1
                                    border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                                }

                                LoaderIcon {
                                    anchors.centerIn: parent
                                    width: screenRoot.s(36)
                                    height: width
                                    accentColor: ThemeBackend.mauve
                                    running: Weather.isLoading || !Weather.isReady
                                    visible: Weather.isLoading || !Weather.isReady
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: screenRoot.s(12)
                                    anchors.bottomMargin: screenRoot.s(12)
                                    anchors.leftMargin: screenRoot.s(14)
                                    anchors.rightMargin: screenRoot.s(14)
                                    spacing: screenRoot.s(10)
                                    visible: !(Weather.isLoading || !Weather.isReady)

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 1
                                        spacing: 0

                                        Text {
                                            text: Weather.currentIcon !== "" ? Weather.currentIcon : ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: screenRoot.s(46)
                                            color: weatherBoxFaceContainer.accentColor
                                            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                                            transform: Translate { y: -screenRoot.s(4) }
                                        }

                                        Item {
                                            Layout.fillHeight: true
                                        }

                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignBottom | Qt.AlignLeft
                                            spacing: screenRoot.s(1)

                                            Text {
                                                text: Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°"
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: screenRoot.s(34)
                                                font.weight: Font.Black
                                                color: ThemeBackend.text
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: "Feels like " + screenRoot.getFeelsLike()
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: screenRoot.s(10.5)
                                                font.weight: Font.Medium
                                                color: ThemeBackend.subtext0
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 1.3
                                        spacing: 0

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                            spacing: screenRoot.s(1)

                                            Text {
                                                text: (typeof Location !== "undefined" && Location.city && Location.city !== "") ? Location.city : (Weather.data && Weather.data.city ? Weather.data.city : "Unknown")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: screenRoot.s(13.5)
                                                font.weight: Font.Bold
                                                color: ThemeBackend.text
                                                horizontalAlignment: Text.AlignRight
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: Weather.data && Weather.data.forecast && Weather.data.forecast[0] && Weather.data.forecast[0].desc ? Weather.data.forecast[0].desc : (Weather.data && Weather.data.desc ? Weather.data.desc : "")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: screenRoot.s(11)
                                                font.weight: Font.Medium
                                                color: ThemeBackend.subtext0
                                                horizontalAlignment: Text.AlignRight
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Item {
                                            Layout.fillHeight: true
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                                            spacing: screenRoot.s(8)

                                            Repeater {
                                                model: screenRoot.hourlyForecastList
                                                delegate: ColumnLayout {
                                                    Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                                                    spacing: screenRoot.s(2)

                                                    Text {
                                                        text: Math.round(parseFloat(modelData.temp)) + "°"
                                                        color: ThemeBackend.subtext0
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: screenRoot.s(11.5)
                                                        font.weight: Font.Medium
                                                        Layout.alignment: Qt.AlignHCenter
                                                        horizontalAlignment: Text.AlignHCenter
                                                        transform: Translate { x: 2 }
                                                    }

                                                    Text {
                                                        text: modelData.icon
                                                        color: modelData.hex && modelData.hex.length === 7 ? modelData.hex : weatherBoxFaceContainer.accentColor
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: screenRoot.s(20)
                                                        Layout.alignment: Qt.AlignHCenter
                                                        horizontalAlignment: Text.AlignHCenter
                                                        transform: Translate { x: -2 }
                                                    }

                                                    Text {
                                                        text: screenRoot.formatHour(modelData.time)
                                                        color: ThemeBackend.subtext0
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: screenRoot.s(9.5)
                                                        font.weight: Font.Normal
                                                        Layout.alignment: Qt.AlignHCenter
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                id: systemUsageBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                property real sp: screenRoot.s(8)
                                function cellX(mx) { return (mx * width) + (mx > 0 ? sp / 2 : 0); }
                                function cellY(my) { return (my * height) + (my > 0 ? sp / 2 : 0); }
                                function cellW(mx, mw) { return (mw * width) - ((mx > 0 ? sp / 2 : 0) + ((mx + mw) < 0.99 ? sp / 2 : 0)); }
                                function cellH(my, mh) { return (mh * height) - ((my > 0 ? sp / 2 : 0) + ((my + mh) < 0.99 ? sp / 2 : 0)); }

                                LiquidCard {
                                    x: systemUsageBox.cellX(0.0)
                                    y: systemUsageBox.cellY(0.0)
                                    width: systemUsageBox.cellW(0.0, 0.333)
                                    height: systemUsageBox.cellH(0.0, 0.5)
                                    value: screenRoot.cpuUsage
                                    colorFill: Qt.lighter(ThemeBackend.mauve, 1.35)
                                    icon: "\uF2DB"
                                    title: I18n.t("quickactions.systemusage.cpu")
                                    valueText: Math.round(screenRoot.cpuUsage * 100) + "%"
                                }

                                LiquidCard {
                                    x: systemUsageBox.cellX(0.333)
                                    y: systemUsageBox.cellY(0.0)
                                    width: systemUsageBox.cellW(0.333, 0.334)
                                    height: systemUsageBox.cellH(0.0, 0.5)
                                    value: screenRoot.ramUsage
                                    colorFill: Qt.lighter(ThemeBackend.mauve, 1.15)
                                    icon: "\uF538"
                                    title: I18n.t("quickactions.systemusage.ram")
                                    valueText: screenRoot.ramUsedGb.toFixed(1) + "G"
                                }

                                LiquidCard {
                                    x: systemUsageBox.cellX(0.667)
                                    y: systemUsageBox.cellY(0.0)
                                    width: systemUsageBox.cellW(0.667, 0.333)
                                    height: systemUsageBox.cellH(0.0, 0.5)
                                    value: Math.max(0.0, Math.min(1.0, screenRoot.tempC / 100.0))
                                    colorFill: ThemeBackend.mauve
                                    icon: "\uF2C9"
                                    title: I18n.t("quickactions.systemusage.temp")
                                    valueText: Math.round(screenRoot.tempC) + "°"
                                }

                                LiquidCard {
                                    x: systemUsageBox.cellX(0.0)
                                    y: systemUsageBox.cellY(0.5)
                                    width: systemUsageBox.cellW(0.5, 0.5)
                                    height: systemUsageBox.cellH(0.5, 0.5)
                                    value: screenRoot.diskUsagePercent
                                    colorFill: Qt.darker(ThemeBackend.mauve, 1.15)
                                    icon: "\uF0A0"
                                    title: screenRoot.diskTotalText
                                    subText: screenRoot.diskUsedText
                                    valueText: Math.round(screenRoot.diskUsagePercent * 100) + "%"
                                }

                                LiquidCard {
                                    x: systemUsageBox.cellX(0.5)
                                    y: systemUsageBox.cellY(0.5)
                                    width: systemUsageBox.cellW(0.5, 0.5)
                                    height: systemUsageBox.cellH(0.5, 0.5)
                                    value: 0.12
                                    colorFill: Qt.darker(ThemeBackend.mauve, 1.35)
                                    icon: "󰤨"
                                    title: I18n.t("quickactions.systemusage.net")
                                    valueText: ""

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: screenRoot.s(4)

                                        Rectangle {
                                            Layout.preferredHeight: screenRoot.s(26)
                                            Layout.preferredWidth: screenRoot.s(108)
                                            radius: screenRoot.s(13)
                                            color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.5)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: screenRoot.s(3)
                                                spacing: screenRoot.s(5)

                                                IconButton {
                                                    size: Math.round(screenRoot.s(20))
                                                    cornerRadius: Math.round(screenRoot.s(10))
                                                    buttonIcon: "\uF063"
                                                    iconFontSize: Math.round(screenRoot.s(11))
                                                    accentColor: Qt.rgba(ThemeBackend.green.r, ThemeBackend.green.g, ThemeBackend.green.b, 0.25)
                                                    textColor: ThemeBackend.green
                                                    enabled: false
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: screenRoot.rxSpeedStr
                                                    color: ThemeBackend.text
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: screenRoot.s(11)
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredHeight: screenRoot.s(26)
                                            Layout.preferredWidth: screenRoot.s(108)
                                            radius: screenRoot.s(13)
                                            color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.5)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: screenRoot.s(3)
                                                spacing: screenRoot.s(5)

                                                IconButton {
                                                    size: Math.round(screenRoot.s(20))
                                                    cornerRadius: Math.round(screenRoot.s(10))
                                                    buttonIcon: "\uF062"
                                                    iconFontSize: Math.round(screenRoot.s(11))
                                                    accentColor: Qt.rgba(ThemeBackend.peach.r, ThemeBackend.peach.g, ThemeBackend.peach.b, 0.25)
                                                    textColor: ThemeBackend.peach
                                                    enabled: false
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: screenRoot.txSpeedStr
                                                    color: ThemeBackend.text
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: screenRoot.s(11)
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: rightWingContent

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: screenRoot.s(14)
                            spacing: screenRoot.s(10)

                            NotificationBox {
                                id: notificationsMainBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                hasShadow: true
                                shadowColor: Qt.rgba(0, 0, 0, 0.22)
                                baseColor: Qt.lighter(ThemeBackend.surface0, 1.28)
                                borderWidth: 1
                                borderColor: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                                cornerRadius: screenRoot.s(16)
                                cardRadius: screenRoot.s(14)
                                emptyGraphicSize: screenRoot.s(110)
                                rootContext: screenRoot
                            }

                            Item {
                                id: mediaBoxContainer
                                Layout.fillWidth: true
                                Layout.preferredHeight: screenRoot.s(96)

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: screenRoot.s(2)
                                    anchors.bottomMargin: -screenRoot.s(2)
                                    radius: screenRoot.s(16)
                                    color: Qt.rgba(0, 0, 0, 0.22)
                                }

                                Rectangle {
                                    id: mediaBoxBg
                                    anchors.fill: parent
                                    radius: screenRoot.s(16)
                                    color: Qt.lighter(ThemeBackend.surface0, 1.28)
                                    border.width: 1
                                    border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)

                                    Rectangle {
                                        id: mediaBgMask
                                        anchors.fill: parent
                                        radius: parent.radius
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: mediaBgMask
                                        }

                                        Row {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: Math.max(30, parent.height * 0.85)
                                            spacing: Math.max(2, Math.floor(parent.width * 0.008))

                                            property int barCount: 32
                                            property real barSpacing: spacing
                                            property int activeBars: Math.min(barCount, Math.max(4, Math.floor(parent.width / (5 + barSpacing))))
                                            property var barLevels: {
                                                let source = Cava.barLevels;
                                                let count = activeBars;
                                                let out = [];
                                                if (!source || source.length === 0) {
                                                    for (let i = 0; i < count; i++) out.push(0.0);
                                                    return out;
                                                }
                                                let srcLen = source.length;
                                                let half = (count - 1) / 2;
                                                for (let i = 0; i < count; i++) {
                                                    let distFromCenter = Math.abs(i - half);
                                                    let norm = half > 0 ? (distFromCenter / half) : 0;
                                                    let pos = Math.pow(norm, 1.25) * (srcLen - 1);
                                                    let idx0 = Math.floor(pos);
                                                    let idx1 = Math.min(srcLen - 1, idx0 + 1);
                                                    let frac = pos - idx0;
                                                    let v0 = source[idx0] || 0.0;
                                                    let v1 = source[idx1] || 0.0;
                                                    let rawVal = v0 + (v1 - v0) * frac;
                                                    let val = rawVal < 0.03 ? 0.0 : Math.pow((rawVal - 0.03) / 0.97, 1.15);
                                                    out.push(Math.max(0.0, Math.min(1.0, val)));
                                                }
                                                return out;
                                            }

                                            Repeater {
                                                model: parent.activeBars
                                                delegate: Rectangle {
                                                    width: (parent.width - (parent.activeBars - 1) * parent.barSpacing) / parent.activeBars
                                                    height: Math.max(2, level * parent.height * 0.9)
                                                    topLeftRadius: width * 0.5
                                                    topRightRadius: width * 0.5
                                                    bottomLeftRadius: 0
                                                    bottomRightRadius: 0
                                                    color: ThemeBackend.mauve
                                                    opacity: 0.22 + (level * 0.18)
                                                    anchors.bottom: parent.bottom

                                                    Behavior on height {
                                                        NumberAnimation { duration: 75; easing.type: Easing.OutCubic }
                                                    }
                                                    Behavior on opacity {
                                                        NumberAnimation { duration: 75; easing.type: Easing.OutQuad }
                                                    }

                                                    property real level: (parent.barLevels && index < parent.barLevels.length) ? parent.barLevels[index] : 0.0
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: screenRoot.s(10)
                                        spacing: screenRoot.s(10)

                                        Rectangle {
                                            id: lockArtRect
                                            Layout.preferredWidth: screenRoot.s(60)
                                            Layout.preferredHeight: screenRoot.s(60)
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: ThemeBackend.borderRadius
                                            color: ThemeBackend.surface1
                                            border.width: 1
                                            border.color: (screenRoot.isMediaActive && MprisController.isPlaying) ? ThemeBackend.mauve : ThemeBackend.surface1
                                            clip: true

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰎈"
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: screenRoot.s(22)
                                                color: ThemeBackend.subtext0
                                                visible: !screenRoot.isMediaActive || !MprisController.artUrl
                                            }

                                            Image {
                                                id: lockArtImg
                                                anchors.fill: parent
                                                source: (screenRoot.isMediaActive && MprisController.artUrl) ? (MprisController.artUrl.startsWith("file://") ? MprisController.artUrl : "file://" + MprisController.artUrl) : ""
                                                fillMode: Image.PreserveAspectCrop
                                                visible: false
                                            }

                                            Rectangle {
                                                id: lockArtMask
                                                anchors.fill: parent
                                                radius: lockArtRect.radius
                                                visible: false
                                                layer.enabled: true
                                            }

                                            MultiEffect {
                                                anchors.fill: parent
                                                source: lockArtImg
                                                maskEnabled: true
                                                maskSource: lockArtMask
                                                visible: screenRoot.isMediaActive && MprisController.artUrl !== ""
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2

                                            Item {
                                                id: lockMediaTitleClip
                                                Layout.fillWidth: true
                                                implicitHeight: lockMediaTitleText.implicitHeight
                                                clip: true

                                                property int marqueeSpacing: screenRoot.s(30)
                                                property real scrollProgress: 0.0

                                                Item {
                                                    id: lockMediaMarquee
                                                    height: parent.height
                                                    x: lockMediaTitleText.implicitWidth > lockMediaTitleClip.width ? -lockMediaTitleClip.scrollProgress * (lockMediaTitleText.implicitWidth + lockMediaTitleClip.marqueeSpacing) : 0

                                                    Row {
                                                        spacing: lockMediaTitleClip.marqueeSpacing
                                                        Text {
                                                            id: lockMediaTitleText
                                                            text: screenRoot.isMediaActive ? (MprisController.trackTitle || "Unknown Track") : I18n.t("music.nothing_playing")
                                                            font.family: ThemeBackend.fontFamily
                                                            font.weight: Font.Black
                                                            font.pixelSize: screenRoot.s(13)
                                                            color: ThemeBackend.text

                                                            onTextChanged: {
                                                                lockMediaTitleClip.scrollProgress = 0.0;
                                                            }
                                                        }

                                                        Text {
                                                            text: lockMediaTitleText.text
                                                            font.family: ThemeBackend.fontFamily
                                                            font.weight: Font.Black
                                                            font.pixelSize: screenRoot.s(13)
                                                            color: ThemeBackend.text
                                                            visible: lockMediaTitleText.implicitWidth > lockMediaTitleClip.width
                                                        }
                                                    }
                                                }

                                                SequentialAnimation {
                                                    loops: Animation.Infinite
                                                    running: lockMediaTitleText.implicitWidth > lockMediaTitleClip.width

                                                    PauseAnimation { duration: 3000 }
                                                    NumberAnimation {
                                                        target: lockMediaTitleClip
                                                        property: "scrollProgress"
                                                        from: 0.0
                                                        to: 1.0
                                                        duration: (lockMediaTitleText.implicitWidth + lockMediaTitleClip.marqueeSpacing) * 25
                                                    }
                                                    PropertyAction { target: lockMediaTitleClip; property: "scrollProgress"; value: 0.0 }
                                                }
                                            }

                                            Text {
                                                text: screenRoot.isMediaActive ? (MprisController.trackArtist || "Unknown Artist") : ""
                                                font.family: ThemeBackend.fontFamily
                                                font.weight: Font.Medium
                                                font.pixelSize: screenRoot.s(10)
                                                color: ThemeBackend.subtext1
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                visible: screenRoot.isMediaActive && text !== ""
                                            }

                                            Text {
                                                text: screenRoot.isMediaActive && screenRoot.player ? (screenRoot.formatMusicTime(MprisController.livePosition) + " / " + screenRoot.formatMusicTime(screenRoot.player.length)) : "--:-- / --:--"
                                                font.family: ThemeBackend.fontFamily
                                                font.weight: Font.Bold
                                                font.pixelSize: screenRoot.s(10)
                                                color: ThemeBackend.subtext0
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                visible: screenRoot.isMediaActive
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: screenRoot.s(4)

                                            IconButton {
                                                Layout.preferredWidth: screenRoot.s(28)
                                                Layout.preferredHeight: screenRoot.s(28)
                                                cornerRadius: screenRoot.s(8)
                                                buttonIcon: "󰒮"
                                                iconFontSize: screenRoot.s(14)
                                                accentColor: ThemeBackend.surface1
                                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                                                onClicked: if (screenRoot.player && screenRoot.player.canGoPrevious) screenRoot.player.previous()
                                            }

                                            IconButton {
                                                Layout.preferredWidth: screenRoot.s(32)
                                                Layout.preferredHeight: screenRoot.s(32)
                                                cornerRadius: screenRoot.s(10)
                                                buttonIcon: (screenRoot.isMediaActive && MprisController.isPlaying) ? "󰏤" : "󰐊"
                                                iconFontSize: screenRoot.s(16)
                                                accentColor: ThemeBackend.surface1
                                                textColor: (screenRoot.isMediaActive && MprisController.isPlaying) ? ThemeBackend.green : ThemeBackend.text
                                                onClicked: if (screenRoot.player && screenRoot.player.canTogglePlaying) screenRoot.player.togglePlaying()
                                            }

                                            IconButton {
                                                Layout.preferredWidth: screenRoot.s(28)
                                                Layout.preferredHeight: screenRoot.s(28)
                                                cornerRadius: screenRoot.s(8)
                                                buttonIcon: "󰒭"
                                                iconFontSize: screenRoot.s(14)
                                                accentColor: ThemeBackend.surface1
                                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                                                onClicked: if (screenRoot.player && screenRoot.player.canGoNext) screenRoot.player.next()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
