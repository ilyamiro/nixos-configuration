import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import "../"
import "../reusables"

Item {
    id: window
    focus: true

    Timer {
        id: btRebuildDebounce
        interval: 150
        repeat: false
        onTriggered: window.rebuildBtData(false)
    }

    function requestBtRebuild() {
        if (window.visible) btRebuildDebounce.restart();
    }

    function getBtDevicesList() {
        let adapter = Bluetooth.defaultAdapter;
        if (!adapter || !adapter.devices) return [];
        let devs = adapter.devices.values || adapter.devices;
        let list = [];
        let count = devs.length !== undefined ? devs.length : (devs.count !== undefined ? devs.count : 0);
        for (let i = 0; i < count; i++) {
            let d = devs[i] !== undefined ? devs[i] : (devs.get ? devs.get(i) : null);
            if (d) list.push(d);
        }
        return list;
    }

    function isEthDevice(dev) {
        return !!dev && dev.type === DeviceType.Wired;
    }

    function isWifiDevice(dev) {
        return !!dev && dev.type === DeviceType.Wifi;
    }

    function findDevices() {
        if (!Networking || !Networking.devices) return;
        let devs = Networking.devices.values || Networking.devices;
        let count = devs.length !== undefined ? devs.length : (devs.count !== undefined ? devs.count : 0);
        for (let i = 0; i < count; i++) {
            let d = devs[i] !== undefined ? devs[i] : (devs.get ? devs.get(i) : null);
            if (!d) continue;
            if (!window.ethDevice && window.isEthDevice(d)) {
                window.ethDevice = d;
            } else if (!window.wifiDevice && window.isWifiDevice(d)) {
                window.wifiDevice = d;
                d.scannerEnabled = true;
            }
        }
    }

    function gotoTab(tabName) {
        if (!tabName) return;
        let t = String(tabName).toLowerCase();
        if (t === "wifi" || t === "wlan") t = "wifi";
        else if (t === "bt" || t === "bluetooth") t = "bt";
        else if (t === "eth" || t === "ethernet" || t === "wired") t = "eth";
        if (t === "wifi" && window.wifiPresent) window.activeMode = "wifi";
        else if (t === "bt" && window.btPresent) window.activeMode = "bt";
        else if (t === "eth" && window.ethPresent) window.activeMode = "eth";
    }

    function resetAndPlayIntro() {
        window.powerAnimAllowed = false;
        powerAnimBlocker.restart();
        window.introState = 0.0;
        introPlayTimer.restart();
    }

    Timer {
        id: introPlayTimer
        interval: 20
        repeat: false
        onTriggered: window.introState = 1.0
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: window.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            modeFile.reload();
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
            window.startBtScan();
            window.findDevices();
            window.rebuildEthData();
            window.rebuildWifiData();
            window.rebuildBtData(false);
            window.fetchIpData();
            window.fetchFreqData();
            if (window.activeMode === "bt" && !btProfilePoller.running) btProfilePoller.running = true;
        } else {
            window.stopBtScan();
            btProfilePoller.running = false;
            ipFetcher.running = false;
            freqFetcher.running = false;
            btConnectSimTimer.stop();
            busyTimeout.stop();
            failClearTimer.stop();
            btRebuildDebounce.stop();
            powerMinSpinTimer.stop();
            introPlayTimer.stop();
            focusTimer.stop();
            mainPollerTimer.stop();
            window.pendingWifiId = "";
            window.pendingWifiSsid = "";
            window.pendingPairThenConnect = "";
            window.btOpsInFlight = ({});
            window.hoveredCardCount = 0;
            window.disconnectHoverCount = 0;
            window.introState = 0.0;
        }
    }

    Component.onDestruction: window.stopBtScan()

    property int disconnectHoverCount: 0
    readonly property bool isDisconnectHovered: disconnectHoverCount > 0

    Timer {
        id: btConnectSimTimer
        property string targetId: ""
        property int attemptId: 0
        interval: 5000
        onTriggered: {
            if (window.activeConnectId !== attemptId) return;
            let bt = window.busyTasks;
            if (bt[targetId]) {
                delete bt[targetId];
                window.busyTasks = Object.assign({}, bt);
                window.failedId = targetId;
                failClearTimer.restart();
                Sounds.playSfx("network/error.wav");
            }
            window.connectingId = "";
        }
    }

    Item {
        visible: false
        Connections {
            target: Bluetooth.defaultAdapter || null
            enabled: window.visible
            ignoreUnknownSignals: true
            function onEnabledChanged() {
                window.requestBtRebuild();
            }
            function onDiscoveringChanged() {
                window.requestBtRebuild();
            }
        }
        Connections {
            target: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.devices) ? Bluetooth.defaultAdapter.devices : null
            enabled: window.visible
            ignoreUnknownSignals: true
            function onObjectInsertedPost(object, index) {
                window.requestBtRebuild();
            }
            function onObjectRemovedPost(object, index) {
                window.requestBtRebuild();
            }
        }
        Repeater {
            id: btDeviceRepeater
            model: (window.visible && Bluetooth.defaultAdapter) ? Bluetooth.defaultAdapter.devices : null
            Item {
                property var device: modelData
                Connections {
                    target: device || null
                    enabled: window.visible
                    ignoreUnknownSignals: true
                    function onConnectedChanged() { window.requestBtRebuild(); }
                    function onBatteryChanged() { window.requestBtRebuild(); }
                    function onBatteryAvailableChanged() { window.requestBtRebuild(); }
                    function onStateChanged() { window.requestBtRebuild(); }
                    function onPairedChanged() {
                        window.requestBtRebuild();
                        if (device && device.paired && window.pendingPairThenConnect === device.address) {
                            window.pendingPairThenConnect = "";
                            let mac = device.address;
                            window.withBtOpLock(mac, function() {
                                let devList = window.getBtDevicesList();
                                let d = null;
                                for (let i = 0; i < devList.length; i++) {
                                    if (devList[i] && devList[i].address === mac) { d = devList[i]; break; }
                                }
                                if (!d) return;
                                d.connect();
                                btConnectSimTimer.targetId = window.connectingId;
                                btConnectSimTimer.attemptId = window.activeConnectId;
                                btConnectSimTimer.restart();
                            });
                        }
                    }
                    function onTrustedChanged() { window.requestBtRebuild(); }
                    function onNameChanged() { window.requestBtRebuild(); }
                    function onDeviceNameChanged() { window.requestBtRebuild(); }
                }
            }
        }
    }

    property var ethDevice: null
    property var wifiDevice: null

    Item {
        visible: false
        Connections {
            target: Networking
            enabled: window.visible
            ignoreUnknownSignals: true
            function onWifiEnabledChanged() { window.rebuildWifiData(); }
            function onDevicesChanged() {
                window.findDevices();
                window.rebuildEthData();
                window.rebuildWifiData();
            }
        }
        Repeater {
            id: netDeviceRepeater
            model: window.visible ? Networking.devices : null
            Item {
                property var device: modelData

                function syncDevice() {
                    if (!device) return;
                    if (window.isEthDevice(device)) {
                        window.ethDevice = device;
                    } else if (window.isWifiDevice(device)) {
                        window.wifiDevice = device;
                        device.scannerEnabled = true;
                    }
                    window.rebuildEthData();
                    window.rebuildWifiData();
                }

                onDeviceChanged: syncDevice()
                Component.onCompleted: syncDevice()

                Connections {
                    target: device || null
                    enabled: window.visible
                    ignoreUnknownSignals: true
                    function onStateChanged() { window.isEthDevice(device) ? window.rebuildEthData() : window.rebuildWifiData(); }
                    function onConnectedChanged() { window.isEthDevice(device) ? window.rebuildEthData() : window.rebuildWifiData(); }
                }
                Connections {
                    target: (device && window.isEthDevice(device)) ? device : null
                    enabled: window.visible
                    ignoreUnknownSignals: true
                    function onHasLinkChanged() { window.rebuildEthData(); }
                    function onLinkSpeedChanged() { window.rebuildEthData(); }
                }
            }
        }
        Repeater {
            id: wifiNetworkRepeater
            model: (window.visible && window.wifiDevice) ? window.wifiDevice.networks : null
            Item {
                property var network: modelData
                Connections {
                    target: network || null
                    enabled: window.visible
                    ignoreUnknownSignals: true
                    function onSignalStrengthChanged() { window.rebuildWifiData(); }
                    function onStateChanged() { window.rebuildWifiData(); }
                    function onConnectedChanged() { window.rebuildWifiData(); }
                    function onKnownChanged() { window.rebuildWifiData(); }
                    function onConnectionFailed(reason) {
                        window.failedId = network.name || "";
                        failClearTimer.restart();
                        Sounds.playSfx("network/error.wav");
                        let bt = window.busyTasks;
                        if (network.name) delete bt[network.name];
                        window.busyTasks = Object.assign({}, bt);
                        window.connectingId = "";
                    }
                }
            }
        }
    }

    property string fetchedEthIp: ""
    property string fetchedWifiIp: ""
    property string fetchedWifiFreq: ""
    property string lastFetchedEthMac: ""
    property string lastFetchedWifiSsid: ""
    property string wifiDeviceName: ""

    Process {
        id: ipFetcher
        command: ["ip", "-4", "-j", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text.trim());
                    let eIp = ""; let wIp = "";
                    for (let i = 0; i < data.length; i++) {
                        let iface = data[i];
                        if (iface.ifname === window.ethDeviceName && iface.addr_info && iface.addr_info.length > 0) {
                            eIp = iface.addr_info[0].local || "";
                        }
                        if (iface.ifname === window.wifiDeviceName && iface.addr_info && iface.addr_info.length > 0) {
                            wIp = iface.addr_info[0].local || "";
                        }
                    }
                    window.fetchedEthIp = eIp;
                    window.fetchedWifiIp = wIp;
                    if (window.ethDeviceName !== "") window.rebuildEthData();
                    if (window.wifiDeviceName !== "") window.rebuildWifiData();
                } catch(e) {}
            }
        }
    }

    Process {
        id: freqFetcher
        command: window.wifiDeviceName !== "" ? ["iw", "dev", window.wifiDeviceName, "link"] : ["echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split('\n');
                let f = "";
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.indexOf("freq:") === 0) {
                        f = line.substring(5).trim();
                        break;
                    }
                }
                window.fetchedWifiFreq = f;
                if (window.wifiDeviceName !== "") window.rebuildWifiData();
            }
        }
    }

    function fetchIpData() { if (window.visible) ipFetcher.running = true; }
    function fetchFreqData() { if (window.visible && window.wifiDeviceName !== "") freqFetcher.running = true; }

    Timer {
        interval: 5000
        running: window.visible && (window.isEthConn || window.isWifiConn)
        repeat: true
        onTriggered: {
            if (window.isEthConn || window.isWifiConn) window.fetchIpData();
            if (window.isWifiConn) window.fetchFreqData();
        }
    }

    function startBtScan() {
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true;
    }

    function stopBtScan() {
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
    }

    function s(val) { return Scaler.s(val); }

    function deepEqual(a, b) {
        if (a === b) return true;
        if (!a || !b || typeof a !== "object" || typeof b !== "object") return false;
        if (Array.isArray(a) !== Array.isArray(b)) return false;
        let ak = Object.keys(a), bk = Object.keys(b);
        if (ak.length !== bk.length) return false;
        for (let k of ak) {
            if (!deepEqual(a[k], b[k])) return false;
        }
        return true;
    }

    function shEsc(str) {
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    readonly property string cacheDir: Caching.getCacheDir("network")
    readonly property string modeFilePath: cacheDir + "/mode"

    Shortcut {
        sequence: "Tab"
        enabled: window.visible
        onActivated: {
            if (window.pendingWifiId !== "") {
                window.pendingWifiId = ""; window.pendingWifiSsid = "";
                return;
            }
            Sounds.playSfx("network/switch.wav");
            let modes = [];
            if (window.ethPresent) modes.push("eth");
            if (window.wifiPresent) modes.push("wifi");
            if (window.btPresent) modes.push("bt");
            if (modes.length > 1) {
                let idx = modes.indexOf(window.activeMode);
                let nextMode = modes[(idx + 1) % modes.length];
                if (nextMode && window.activeMode !== nextMode) {
                    window.powerAnimAllowed = false;
                    powerAnimBlocker.restart();
                    window.activeMode = nextMode;
                }
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        if (window.pendingWifiId !== "") {
            window.pendingWifiId = "";
            window.pendingWifiSsid = "";
            event.accepted = true;
        }
    }

    Settings {
        id: cache
        location: window.cacheDir + "/settings.ini"
        category: "QS_NetworkWidgetUnified"
        property string lastWifiSsid: ""
        property string lastBtJson: ""
    }

    property var btDeviceMap: ({})
    property var btAudioProfiles: ({})

    property bool ethPresent: false
    property bool wifiPresent: false
    property bool btPresent: false

    property int btMissCount: 0
    property bool btFirstLoad: true

    property bool powerAnimAllowed: false
    Timer { id: powerAnimBlocker; interval: 250; running: true; onTriggered: window.powerAnimAllowed = true }

    Timer {
        id: firstLoadFailsafe
        interval: 1500
        running: true
        onTriggered: {
            if (window.btFirstLoad) {
                window.btFirstLoad = false;
                window.validateActiveMode();
            }
        }
    }

    property bool isValidatingMode: false
    function validateActiveMode() {
        if (window.btFirstLoad) return;
        if (isValidatingMode) return;
        isValidatingMode = true;

        let validModes = [];
        if (window.ethPresent) validModes.push("eth");
        if (window.wifiPresent) validModes.push("wifi");
        if (window.btPresent) validModes.push("bt");

        if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.activeMode = validModes[0];
        }

        isValidatingMode = false;
    }

    property bool ignoreNextModeFileUpdate: false

    FileView {
        id: modeFile
        path: window.modeFilePath
        watchChanges: window.visible
        onFileChanged: reload()
        onLoaded: {
            let mode = text().trim();
            if ((mode === "wifi" || mode === "bt" || mode === "eth") && window.activeMode !== mode) {
                if ((mode === "eth" && window.ethPresent) ||
                    (mode === "wifi" && window.wifiPresent) ||
                    (mode === "bt" && window.btPresent)) {
                    window.powerAnimAllowed = false;
                    powerAnimBlocker.restart();
                    window.ignoreNextModeFileUpdate = true;
                    window.activeMode = mode;
                }
            }
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", "mkdir -p '" + window.cacheDir + "'; if [ ! -f '" + window.modeFilePath + "' ]; then echo '" + activeMode + "' > '" + window.modeFilePath + "'; fi"]);

        window.findDevices();
        window.rebuildEthData();
        window.rebuildWifiData();

        let hasCache = false;
        if (cache.lastBtJson !== "") { window.rebuildBtData(true); hasCache = true; }

        if (hasCache) {
            let validModes = [];
            if (window.ethPresent) validModes.push("eth");
            if (window.wifiPresent) validModes.push("wifi");
            if (window.btPresent) validModes.push("bt");

            if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
                window.activeMode = validModes[0];
            }
        }

        window.validateActiveMode();

        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
            window.startBtScan();
        }
    }

    readonly property string scriptsDir: Caching.qsDir + "/network"

    readonly property color sharedAccent: Qt.lighter(ThemeBackend.sapphire, 1.15)
    readonly property color btAccent: ThemeBackend.mauve

    property string activeMode: "wifi"
    readonly property color activeColor: activeMode === "bt" ? window.btAccent : window.sharedAccent
    readonly property color activeGradientSecondary: Qt.darker(window.activeColor, 1.25)

    property var busyTasks: ({})
    property var disconnectingDevices: ({})
    property string connectingId: ""
    property string failedId: ""

    property var btOpsInFlight: ({})
    property string pendingPairThenConnect: ""

    function isBtOpBusy(mac) {
        return !!window.btOpsInFlight[mac];
    }

    function withBtOpLock(mac, fn) {
        if (!mac || window.isBtOpBusy(mac)) return false;

        let ops = window.btOpsInFlight;
        ops[mac] = true;
        window.btOpsInFlight = Object.assign({}, ops);

        Qt.callLater(function() {
            try {
                fn();
            } catch (e) {
                console.warn("BT op failed for", mac, e);
            } finally {
                let o = window.btOpsInFlight;
                delete o[mac];
                window.btOpsInFlight = Object.assign({}, o);
            }
        });
        return true;
    }

    Timer { id: busyTimeout; interval: 15000; onTriggered: { window.busyTasks = ({}); window.disconnectingDevices = ({}); window.connectingId = ""; } }
    Timer { id: failClearTimer; interval: 4000; onTriggered: window.failedId = "" }

    Timer { id: ethPendingReset; interval: 8000; onTriggered: { window.ethPowerPending = false; window.expectedEthPower = ""; } }
    Timer { id: wifiPendingReset; interval: 8000; onTriggered: { window.wifiPowerPending = false; window.expectedWifiPower = ""; } }
    Timer { id: btPendingReset; interval: 8000; onTriggered: { window.btPowerPending = false; window.expectedBtPower = ""; } }
    Timer { id: powerMinSpinTimer; interval: 800; onTriggered: { if (window.activeMode === "eth") window.rebuildEthData(); else if (window.activeMode === "wifi") window.rebuildWifiData(); else window.rebuildBtData(false); } }

    property bool showInfoView: false

    property string pendingWifiSsid: ""
    property string pendingWifiId: ""

    property int activeConnectId: 0

    function connectDevice(mode, id, macOrSsid, password) {
        window.activeConnectId++;
        window.connectingId = id || "";
        window.failedId = "";
        let bt = window.busyTasks;
        if (id) bt[id] = true;
        window.busyTasks = Object.assign({}, bt);
        busyTimeout.restart();

        if (mode === "eth") {
            if (window.ethDevice && window.ethDevice.network) {
                window.ethDevice.network.connect();
            }
        } else if (mode === "wifi") {
            if (window.wifiDevice && window.wifiDevice.networks) {
                let targetNet = null;
                let nets = window.wifiDevice.networks.values;
                for (let i = 0; i < nets.length; i++) {
                    let net = nets[i];
                    if (net && net.name === macOrSsid) { targetNet = net; break; }
                }
                if (targetNet) {
                    if (password && password !== "") targetNet.connectWithPsk(password);
                    else targetNet.connect();
                }
            }
        } else {
            window.stopBtScan();
            let mac = macOrSsid;
            if (window.isBtOpBusy(mac)) return;

            window.withBtOpLock(mac, function() {
                let devList = window.getBtDevicesList();
                let d = null;
                for (let i = 0; i < devList.length; i++) {
                    if (devList[i] && devList[i].address === mac) { d = devList[i]; break; }
                }
                if (!d) {
                    let b = window.busyTasks; delete b[id]; window.busyTasks = Object.assign({}, b);
                    window.connectingId = "";
                    window.failedId = id || "";
                    failClearTimer.restart();
                    return;
                }
                d.trusted = true;
                if (!d.paired && !d.bonded) {
                    window.pendingPairThenConnect = mac;
                    d.pair();
                } else {
                    d.connect();
                    btConnectSimTimer.targetId = id || "";
                    btConnectSimTimer.attemptId = window.activeConnectId;
                    btConnectSimTimer.restart();
                }
            });
        }
    }

    property var currentCores: [null, null, null, null, null]
    property var coreVisualIndices: [0, 0, 0, 0, 0]
    property int activeCoreCount: 0
    property real smoothedActiveCoreCount: activeCoreCount
    Behavior on smoothedActiveCoreCount { enabled: window.visible; NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    function syncCores() {
        let list = [];
        if (activeMode === "eth") {
            list = window.ethConnected ? [window.ethConnected] : [];
        } else if (activeMode === "wifi") {
            let wValid = !!window.wifiConnected && window.wifiConnected.ssid !== undefined;
            list = wValid ? [window.wifiConnected] : [];
        } else {
            list = window.btConnected || [];
        }

        if (!currentPower) list = [];
        else if (!Array.isArray(list)) list = [list];

        let newCores = [window.currentCores[0], window.currentCores[1], window.currentCores[2], window.currentCores[3], window.currentCores[4]];
        let found = [false, false, false, false, false];

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            if (!dev) continue;
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            if (!id) continue;
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { found[c] = true; newCores[c] = dev; break; }
                }
            }
        }

        for (let c = 0; c < 5; c++) { if (!found[c]) newCores[c] = null; }

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            if (!dev) continue;
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            if (!id) continue;
            let isFound = false;
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { isFound = true; break; }
                }
            }
            if (!isFound) {
                for (let c = 0; c < 5; c++) {
                    if (!newCores[c]) { newCores[c] = dev; break; }
                }
            }
        }

        window.currentCores = [...newCores];

        let activeCount = 0;
        let newVis = [0, 0, 0, 0, 0];
        for (let c = 0; c < 5; c++) {
            if (newCores[c]) {
                newVis[c] = activeCount;
                activeCount++;
            }
        }
        window.coreVisualIndices = newVis;
        window.activeCoreCount = activeCount;
    }

    onCurrentConnChanged: {
        showInfoView = currentConn;
        if (currentConn) updateInfoNodes();
    }

    onActiveModeChanged: {
        if (!window.ignoreNextModeFileUpdate) {
            Quickshell.execDetached(["bash", "-c", "mkdir -p '" + window.cacheDir + "' && echo '" + window.activeMode + "' > '" + window.modeFilePath + "'"]);
        }
        window.ignoreNextModeFileUpdate = false;

        window.hoveredCardCount = 0;
        window.disconnectHoverCount = 0;
        window.nextWifiList = null;
        window.nextBtList = null;
        window.nextInfoList = null;

        window.pendingWifiId = ""; window.pendingWifiSsid = "";
        if (window.activeMode === "bt" && window.visible && !btProfilePoller.running) btProfilePoller.running = true;

        infoListModel.clear();
        window.busyTasks = ({});
        window.disconnectingDevices = ({});
        window.currentCores = [null, null, null, null, null];
        window.coreVisualIndices = [0, 0, 0, 0, 0];
        window.activeCoreCount = 0;
        syncCores();
        window.showInfoView = window.currentConn;

        if (window.activeMode === "wifi") window.rebuildWifiData();
        else if (window.activeMode === "bt") window.rebuildBtData(false);
        else if (window.activeMode === "eth") window.rebuildEthData();

        if (window.showInfoView) window.updateInfoNodes();
    }

    ListModel { id: wifiListModel }
    ListModel { id: btListModel }
    ListModel { id: infoListModel }

    function syncModel(listModel, dataArray) {
        if (!listModel || !dataArray) return;
        for (let i = listModel.count - 1; i >= 0; i--) {
            let item = listModel.get(i);
            let id = item ? item.id : null;
            let found = false;
            if (id !== null && id !== undefined) {
                for (let j = 0; j < dataArray.length; j++) {
                    if (id === dataArray[j].id) { found = true; break; }
                }
            }
            if (!found) { listModel.remove(i); }
        }

        for (let i = 0; i < dataArray.length && i < 30; i++) {
            let d = dataArray[i];
            if (!d) continue;
            let foundIdx = -1;
            for (let j = 0; j < listModel.count; j++) {
                let mItem = listModel.get(j);
                if (mItem && mItem.id === d.id) { foundIdx = j; break; }
            }

            let obj = {
                id: d.id || "", ssid: d.ssid || "", mac: d.mac || "",
                name: d.name || d.ssid || "", icon: d.icon || "", security: d.security || "", action: d.action || "",
                isInfoNode: d.isInfoNode || false, isActionable: d.isActionable !== undefined ? d.isActionable : true,
                cmdStr: d.cmdStr || "", parentIndex: d.parentIndex !== undefined ? d.parentIndex : -1
            };

            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) { listModel.move(foundIdx, i, 1); }
                let currentModelItem = listModel.get(i);
                if (currentModelItem) {
                    for (let key in obj) {
                        if (currentModelItem[key] !== obj[key]) {
                            listModel.setProperty(i, key, obj[key]);
                        }
                    }
                }
            }
        }
    }

    property int hoveredCardCount: 0
    readonly property bool isListLocked: hoveredCardCount > 0
    property var nextWifiList: null
    property var nextBtList: null
    property var nextInfoList: null

    onIsListLockedChanged: {
        if (!isListLocked) {
            if (nextWifiList !== null) { window.syncModel(wifiListModel, nextWifiList); window.wifiList = nextWifiList; nextWifiList = null; }
            if (nextBtList !== null) { window.syncModel(btListModel, nextBtList); window.btList = nextBtList; nextBtList = null; }
            if (nextInfoList !== null) { window.syncModel(infoListModel, nextInfoList); nextInfoList = null; }
        }
    }

    property string ethDeviceName: ""
    property bool ethPowerPending: false
    property string expectedEthPower: ""
    property string ethPower: "off"
    property var ethConnected: null
    readonly property bool isEthConn: !!window.ethConnected

    onEthConnectedChanged: { syncCores(); if (window.currentConn && window.activeMode === "eth") updateInfoNodes(); }

    property bool wifiPowerPending: false
    property string expectedWifiPower: ""
    property string wifiPower: "off"
    property var wifiConnected: null
    property var wifiList: []
    property string strongestWifiSsid: ""
    readonly property bool isWifiConn: !!window.wifiConnected && window.wifiConnected.ssid !== undefined

    readonly property string targetWifiSsid: {
        let found = false;
        if (cache.lastWifiSsid !== "") {
            for (let i = 0; i < wifiList.length; i++) {
                if (wifiList[i] && wifiList[i].id === cache.lastWifiSsid) { found = true; break; }
            }
        }
        return found ? cache.lastWifiSsid : strongestWifiSsid;
    }

    onWifiConnectedChanged: {
        if (window.wifiConnected && window.wifiConnected.ssid) { cache.lastWifiSsid = window.wifiConnected.ssid; }
        syncCores();
        if (window.currentConn && window.activeMode === "wifi") updateInfoNodes();
    }

    property bool btPowerPending: false
    property string expectedBtPower: ""
    property string btPower: "off"
    property var btConnected: []
    property var btList: []
    readonly property bool isBtConn: window.btConnected.length > 0

    onBtConnectedChanged: {
        syncCores();
        if (window.currentConn && window.activeMode === "bt") updateInfoNodes();
    }

    readonly property bool currentPower: activeMode === "eth" ? window.ethPower === "on" : (activeMode === "wifi" ? window.wifiPower === "on" : window.btPower === "on")
    onCurrentPowerChanged: { syncCores(); }

    readonly property bool currentPowerPending: activeMode === "eth" ? window.ethPowerPending : (activeMode === "wifi" ? window.wifiPowerPending : window.btPowerPending)
    readonly property bool currentConn: activeMode === "eth" ? window.isEthConn : (activeMode === "wifi" ? window.isWifiConn : window.isBtConn)

    readonly property var currentObjList: activeMode === "eth" ? (window.isEthConn ? [window.ethConnected] : []) : (activeMode === "wifi" ? (window.isWifiConn ? [window.wifiConnected] : []) : window.btConnected)

    readonly property bool isLogicMultiState: window.activeMode === "bt" && window.activeCoreCount > 1

    property real multiTransitionState: (isLogicMultiState && window.currentPower) ? 1.0 : 0.0
    Behavior on multiTransitionState { enabled: window.visible; NumberAnimation { duration: 1200; easing.type: Easing.InOutExpo } }

    function updateInfoNodes() {
        let nodes = [];
        let cList = [];

        if (window.activeMode === "eth") {
            cList = window.ethConnected ? [window.ethConnected] : [];
        } else if (window.activeMode === "wifi") {
            let wConn = window.wifiConnected;
            if (Array.isArray(wConn)) wConn = wConn[0];
            cList = (!!wConn && wConn.ssid !== undefined) ? [wConn] : [];
        } else {
            cList = window.btConnected || [];
        }

        if (window.currentConn && cList.length > 0) {
            for (let i = 0; i < cList.length; i++) {
                let obj = cList[i];
                if (!obj) continue;
                let cIndex = 0;

                if (window.activeMode === "bt" && obj.mac) {
                    for (let c = 0; c < 5; c++) {
                        if (window.currentCores[c] && window.currentCores[c].mac === obj.mac) { cIndex = c; break; }
                    }
                }

                if (window.activeMode === "eth") {
                    nodes.push({ id: "ip", name: obj.ip || I18n.t("network.status.no_ip") || "No IP", icon: "󰩟", action: "", isInfoNode: true, isActionable: true, cmdStr: "printf '%s' " + window.shEsc(obj.ip || "") + " | wl-copy", parentIndex: cIndex });
                    nodes.push({ id: "spd", name: obj.speed || I18n.t("network.status.unknown") || "Unknown", icon: "󰓅", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "mac", name: obj.mac || I18n.t("network.status.unknown") || "Unknown", icon: "󰒋", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else if (window.activeMode === "wifi") {
                    let sigValue = obj.signal !== undefined ? obj.signal + "%" : (I18n.t("network.status.calculating") || "Calculating...");
                    nodes.push({ id: "sig_" + i, name: sigValue, icon: obj.icon || "󰤨", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "sec_" + i, name: obj.security || I18n.t("network.status.open") || "Open", icon: "󰦝", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.ip) nodes.push({ id: "ip_" + i, name: obj.ip, icon: "󰩟", action: "", isInfoNode: true, isActionable: true, cmdStr: "printf '%s' " + window.shEsc(obj.ip) + " | wl-copy", parentIndex: cIndex });
                    if (obj.freq) nodes.push({ id: "freq_" + i, name: obj.freq, icon: "󰖧", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else if (obj.mac) {
                    nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.profile) {
                        nodes.push({ id: "prof_" + obj.mac, name: obj.profile, icon: (obj.profile === "Hi-Fi (A2DP)" ? "󰓃" : "󰋎"), action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }
                    nodes.push({ id: "mac_" + obj.mac, name: obj.mac || I18n.t("network.status.unknown") || "Unknown", icon: "󰒋", action: "", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "forget_" + obj.mac, name: I18n.t("network.actions.unpair") || "Unpair", icon: "󰆴", action: "", isInfoNode: true, isActionable: true, cmdStr: "BT_FORGET_" + obj.mac, parentIndex: cIndex });
                }
            }
            if (window.activeMode !== "eth") {
                nodes.push({ id: "action_scan", name: I18n.t("network.actions.scan") || "Scan", icon: "󰍉", action: "", isInfoNode: true, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }
        }

        if (window.isListLocked && window.activeMode !== "eth") window.nextInfoList = nodes;
        else { window.syncModel(infoListModel, nodes); window.nextInfoList = null; }
    }

    function rebuildEthData() {
        if (!window.ethDevice) window.findDevices();
        let hasEth = !!window.ethDevice && (window.ethDevice.hasLink || window.ethDevice.connected);
        window.ethPresent = hasEth;
        if (!window.ethPresent) {
            window.ethConnected = null;
            window.validateActiveMode();
            return;
        }

        window.ethDeviceName = (window.ethDevice && (window.ethDevice.name || window.ethDevice.interfaceName || window.ethDevice.interface)) ? (window.ethDevice.name || window.ethDevice.interfaceName || window.ethDevice.interface) : "";
        let fetchedPower = (window.ethDevice.hasLink || window.ethDevice.connected) ? "on" : "off";

        if (window.ethPowerPending) {
            window.ethPower = window.expectedEthPower;
            if (fetchedPower === window.expectedEthPower && !powerMinSpinTimer.running) {
                window.ethPowerPending = false;
                ethPendingReset.stop();
            }
        } else {
            window.ethPower = fetchedPower;
            window.expectedEthPower = "";
        }

        let newConnected = null;
        if (window.ethDevice.connected) {
            if (window.lastFetchedEthMac !== window.ethDevice.address) {
                window.lastFetchedEthMac = window.ethDevice.address || "";
                window.fetchIpData();
            }
            newConnected = {
                id: window.ethDeviceName,
                mac: window.ethDevice.address || "",
                speed: window.ethDevice.linkSpeed ? window.ethDevice.linkSpeed.toString() + " Mbps" : "",
                ip: window.fetchedEthIp
            };
        } else {
            window.lastFetchedEthMac = "";
        }

        if (!window.deepEqual(window.ethConnected, newConnected)) {
            if (!window.isEthConn && newConnected && window.activeMode === "eth") Sounds.playSfx("network/connect.wav");
            window.ethConnected = newConnected;
        }

        if (window.activeMode === "eth") {
            let dd = window.disconnectingDevices;
            let ddChanged = false;
            for (let devId in dd) {
                if (!newConnected || newConnected.id !== devId) {
                    delete dd[devId];
                    ddChanged = true;
                }
            }
            if (ddChanged) {
                window.disconnectingDevices = Object.assign({}, dd);
                if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
            }
        }
        window.validateActiveMode();
    }

    function rebuildWifiData() {
        if (!window.wifiDevice) window.findDevices();
        window.wifiPresent = !!window.wifiDevice;
        if (!window.wifiPresent) { window.wifiConnected = null; window.validateActiveMode(); return; }

        window.wifiDeviceName = (window.wifiDevice && (window.wifiDevice.name || window.wifiDevice.interfaceName || window.wifiDevice.interface)) ? (window.wifiDevice.name || window.wifiDevice.interfaceName || window.wifiDevice.interface) : "";
        let fetchedPower = Networking.wifiEnabled ? "on" : "off";

        if (window.wifiPowerPending) {
            window.wifiPower = window.expectedWifiPower;
            if (fetchedPower === window.expectedWifiPower && !powerMinSpinTimer.running) {
                window.wifiPowerPending = false;
                wifiPendingReset.stop();
            }
        } else {
            window.wifiPower = fetchedPower;
            window.expectedWifiPower = "";
        }

        let newConnected = null;
        let newNetworks = [];
        let maxSig = -1;
        let bestSsid = "";

        if (window.wifiDevice && window.wifiDevice.networks) {
            let nets = window.wifiDevice.networks.values;
            for (let i = 0; i < nets.length; i++) {
                let net = nets[i];
                if (!net || !net.name) continue;

                let secStr = "Open";
                if (net.security === 1) secStr = "WEP";
                else if (net.security === 2) secStr = "WPA";
                else if (net.security === 3) secStr = "WPA2";
                else if (net.security === 4) secStr = "WPA3";
                else if (net.security === 5) secStr = "WPA2/WPA3";
                else if (net.security === 6) secStr = "Enterprise";
                else if (net.security === 7) secStr = "OWE";
                else if (net.security > 0) secStr = "Secure";

                let sig = net.signalStrength !== undefined ? Math.round(net.signalStrength * 100) : 0;
                if (sig > maxSig) { maxSig = sig; bestSsid = net.name; }

                let nObj = {
                    id: net.name,
                    ssid: net.name,
                    mac: "",
                    name: net.name,
                    icon: "󰤨",
                    security: secStr,
                    signal: sig.toString(),
                    action: net.known ? "" : "Connect",
                    isActionable: true
                };

                if (net.connected) {
                    if (window.lastFetchedWifiSsid !== net.name) {
                        window.lastFetchedWifiSsid = net.name;
                        window.fetchIpData();
                        window.fetchFreqData();
                    }
                    nObj.ip = window.fetchedWifiIp;
                    nObj.freq = window.fetchedWifiFreq;
                    newConnected = nObj;
                } else {
                    newNetworks.push(nObj);
                }
            }
        }

        if (!newConnected) window.lastFetchedWifiSsid = "";
        window.strongestWifiSsid = bestSsid;

        let isNowWifiConn = !!newConnected;
        let wasWifiConn = !!window.wifiConnected;

        if (!window.deepEqual(window.wifiConnected, newConnected)) {
            window.wifiConnected = newConnected;
        }

        newNetworks.sort((a, b) => (a && b && a.id && b.id) ? a.id.localeCompare(b.id) : 0);

        if (isNowWifiConn && window.activeMode === "wifi") {
            newNetworks.push({ id: "action_settings", ssid: I18n.t("network.status.current_device") || "Current Device", mac: "", name: I18n.t("network.status.current_device") || "Current Device", icon: "󰒓", action: "", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
        }

        if (!window.deepEqual(window.wifiList, newNetworks)) {
            if (window.isListLocked) window.nextWifiList = newNetworks;
            else { window.syncModel(wifiListModel, newNetworks); window.wifiList = newNetworks; window.nextWifiList = null; }
        }

        if (window.activeMode === "wifi") {
            if (!wasWifiConn && isNowWifiConn) window.showInfoView = true;

            let dd = window.disconnectingDevices;
            let ddChanged = false;
            for (let ssid in dd) {
                if (!isNowWifiConn || (newConnected && newConnected.ssid !== ssid)) {
                    delete dd[ssid];
                    ddChanged = true;
                }
            }
            if (ddChanged) {
                window.disconnectingDevices = Object.assign({}, dd);
                if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
            }

            let newlyConnected = false;
            let bt = window.busyTasks;
            if (isNowWifiConn && newConnected && bt[newConnected.ssid]) {
                newlyConnected = true;
                delete bt[newConnected.ssid];
                window.connectingId = "";
            }
            if (newlyConnected) {
                Sounds.playSfx("network/connect.wav");
                window.busyTasks = Object.assign({}, bt);
                if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
            }

            if (isNowWifiConn || window.isBtConn || window.isEthConn) window.updateInfoNodes();
        }
        window.validateActiveMode();
    }

    function rebuildBtData(isCache) {
        if (!isCache && window.btFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.btFirstLoad = false;
        }
        let adapter = Bluetooth.defaultAdapter;
        if (!adapter) {
            window.btMissCount++;
            if (window.btMissCount >= 2) window.btPresent = false;
            if (!isCache) validateActiveMode();
            return;
        }

        window.btMissCount = 0;
        window.btPresent = true;

        let fetchedPower = adapter.enabled ? "on" : "off";

        if (window.btPowerPending) {
            window.btPower = window.expectedBtPower;
            if (fetchedPower === window.expectedBtPower && !powerMinSpinTimer.running) {
                window.btPowerPending = false;
                btPendingReset.stop();
            }
        } else {
            window.btPower = fetchedPower;
            window.expectedBtPower = "";
        }

        let oldBtLen = window.btConnected ? window.btConnected.length : 0;
        let newBtConnected = [];
        let newDevices = [];
        let map = {};

        let devList = window.getBtDevicesList();
        for (let i = 0; i < devList.length; i++) {
            let d = devList[i];
            if (!d) continue;
            let mac = d.address || "";
            if (mac === "") continue;

            map[mac] = d;

            let deviceName = d.deviceName || "";
            let alias = d.name || "";
            let hasName = deviceName !== "";
            let paired = d.paired || d.bonded;

            let name = hasName ? deviceName : (alias !== "" ? alias : mac);

            let connected = d.connected;
            let battery = d.batteryAvailable ? Math.round(d.battery * 100) : 0;
            let iconType = d.icon || "";

            let icon = "";
            let typeLower = iconType.toLowerCase();
            let nameLower = name.toLowerCase();
            if (typeLower.indexOf("headset") !== -1 || typeLower.indexOf("headphone") !== -1 || nameLower.indexOf("headphone") !== -1 || nameLower.indexOf("buds") !== -1 || nameLower.indexOf("pods") !== -1) icon = "🎧";
            else if (typeLower.indexOf("audio") !== -1 || typeLower.indexOf("speaker") !== -1 || typeLower.indexOf("card") !== -1 || nameLower.indexOf("speaker") !== -1) icon = "📻";
            else if (typeLower.indexOf("phone") !== -1 || nameLower.indexOf("phone") !== -1 || nameLower.indexOf("iphone") !== -1 || nameLower.indexOf("android") !== -1) icon = "📱";
            else if (typeLower.indexOf("mouse") !== -1 || nameLower.indexOf("mouse") !== -1) icon = "󰍽";
            else if (typeLower.indexOf("keyboard") !== -1 || nameLower.indexOf("keyboard") !== -1) icon = "⌨️";
            else if (typeLower.indexOf("controller") !== -1 || nameLower.indexOf("controller") !== -1) icon = "🎮";

            if (connected) {
                newBtConnected.push({
                    id: mac,
                    name: name,
                    mac: mac,
                    icon: icon,
                    battery: battery.toString(),
                    profile: window.btAudioProfiles[mac.toLowerCase()] || "Connected"
                });
            } else {
                if (!hasName && !paired) continue;

                newDevices.push({
                    id: mac,
                    name: name,
                    mac: mac,
                    icon: icon,
                    action: paired ? "Connect" : "Pair",
                    isActionable: true
                });
            }
        }

        window.btDeviceMap = map;
        let isNowBtConn = newBtConnected.length > 0;

        if (!window.deepEqual(window.btConnected, newBtConnected)) {
            window.btConnected = newBtConnected;
        }

        newDevices.sort((a, b) => (a && b && a.id && b.id) ? a.id.localeCompare(b.id) : 0);

        if (isNowBtConn && window.activeMode === "bt") {
            newDevices.push({ id: "action_settings", ssid: "", mac: "action_settings", name: I18n.t("network.status.current_device") || "Current Device", icon: "󰒓", action: "", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
        }

        if (!window.deepEqual(window.btList, newDevices)) {
            if (window.isListLocked) window.nextBtList = newDevices;
            else { window.syncModel(btListModel, newDevices); window.btList = newDevices; window.nextBtList = null; }
        }

        if (window.activeMode === "bt") {
            if (newBtConnected.length > oldBtLen) {
                window.showInfoView = true;
            }

            let dd = window.disconnectingDevices;
            let ddChanged = false;
            for (let mac in dd) {
                let stillConnected = false;
                for (let i = 0; i < newBtConnected.length; i++) {
                    if (newBtConnected[i] && newBtConnected[i].mac === mac) { stillConnected = true; break; }
                }
                if (!stillConnected) {
                    delete dd[mac];
                    ddChanged = true;
                }
            }
            if (ddChanged) {
                window.disconnectingDevices = Object.assign({}, dd);
                if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
            }

            let newlyConnected = false;
            let bt = window.busyTasks;
            for (let i = 0; i < newBtConnected.length; i++) {
                if (newBtConnected[i] && newBtConnected[i].mac) {
                    let mac = newBtConnected[i].mac;
                    if (bt[mac]) {
                        newlyConnected = true;
                        delete bt[mac];
                        window.connectingId = "";
                    }
                }
            }
            if (newlyConnected) {
                btConnectSimTimer.stop();
                Sounds.playSfx("network/connect.wav");
                window.busyTasks = Object.assign({}, bt);
                if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
            }

            if (isNowBtConn || window.isWifiConn || window.isEthConn) window.updateInfoNodes();
        }
        if (!isCache) validateActiveMode();
    }

    Process {
        id: btProfilePoller
        command: ["bash", window.scriptsDir + "/bluetooth_panel_logic.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let text = this.text.trim();
                    if (text !== "") {
                        window.btAudioProfiles = JSON.parse(text);
                        window.requestBtRebuild();
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: mainPollerTimer
        interval: (Object.keys(window.busyTasks).length > 0 || Object.keys(window.disconnectingDevices).length > 0) ? 1000 : 3000
        running: window.visible
        repeat: true
        property int tick: 0
        onTriggered: {
            tick = (tick + 1) % 4;
            if (window.activeMode === "bt") {
                if (!btProfilePoller.running) btProfilePoller.running = true;
            }
            if (tick === 0) {
                if (window.activeMode !== "bt" && !btProfilePoller.running) btProfilePoller.running = true;
            }
        }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 400000; loops: Animation.Infinite; running: window.visible
    }

    property real introState: 0.0
    Behavior on introState { enabled: window.visible; NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }

    component LoadingDots : Row {
        spacing: window.s(4)
        property color dotCol: ThemeBackend.text
        Repeater {
            model: 3
            Rectangle {
                width: window.s(5); height: window.s(5); radius: window.s(2.5); color: dotCol
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: window.visible && parent.visible
                    PauseAnimation { duration: index * 100 }
                    NumberAnimation { from: 0; to: window.s(-5); duration: 250; easing.type: Easing.OutSine }
                    NumberAnimation { from: window.s(-5); to: 0; duration: 250; easing.type: Easing.InSine }
                    PauseAnimation { duration: (2 - index) * 100 }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: window.visible
        enabled: window.visible

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(120)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(80)
                opacity: window.currentPower ? (window.isDisconnectHovered ? 0.05 : 0.03) : 0.01
                color: window.isDisconnectHovered && window.currentConn
                    ? ThemeBackend.red
                    : (window.currentConn ? window.activeColor : ThemeBackend.surface2)
                Behavior on color { enabled: window.visible; ColorAnimation { duration: 300; easing.type: Easing.OutQuad } }
                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                visible: opacity > 0.005
            }

            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-120)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-80)
                opacity: window.currentPower ? (window.isDisconnectHovered ? 0.04 : 0.02) : 0.005
                color: window.isDisconnectHovered && window.currentConn
                    ? Qt.darker(ThemeBackend.red, 1.25)
                    : (window.currentConn ? window.activeGradientSecondary : ThemeBackend.surface1)
                Behavior on color { enabled: window.visible; ColorAnimation { duration: 300; easing.type: Easing.OutQuad } }
                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                visible: opacity > 0.002
            }

            Item {
                id: radarItem
                anchors.fill: parent
                anchors.bottomMargin: window.s(65)
                opacity: window.currentPower ? 1.0 : 0.0
                scale: window.currentPower ? 1.0 : 1.05
                visible: window.visible && opacity > 0.01
                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
                Behavior on scale { enabled: window.visible; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                Repeater {
                    model: 3
                    Rectangle {
                        anchors.centerIn: parent
                        width: window.s(220) + (index * window.s(130))
                        height: width
                        radius: width / 2
                        color: "transparent"

                        border.color: Object.keys(window.disconnectingDevices).length > 0 ? ThemeBackend.red : window.activeColor
                        border.width: Object.keys(window.disconnectingDevices).length > 0 ? window.s(2) : 1

                        Behavior on border.color { enabled: window.visible; ColorAnimation { duration: 150 } }
                        Behavior on border.width { enabled: window.visible; NumberAnimation { duration: 150 } }

                        opacity: Object.keys(window.disconnectingDevices).length > 0 ? 0.2 : (window.currentConn ? 0.08 - (index * 0.02) : 0.03)
                        Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 150 } }
                    }
                }
            }

            Canvas {
                id: nodeLinesCanvas
                anchors.fill: parent
                anchors.bottomMargin: window.s(65)
                z: 0
                opacity: (window.currentConn && window.showInfoView && window.currentPower) ? 1.0 : 0.0
                visible: window.visible && opacity > 0.01
                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 500 } }

                property real scaleTrigger: window.s(1)
                onScaleTriggerChanged: if (window.visible) requestPaint()

                Timer {
                    id: lightningTimer
                    interval: 25
                    running: window.visible && nodeLinesCanvas.opacity > 0.01 && window.currentPower
                    repeat: true
                    onTriggered: nodeLinesCanvas.requestPaint()
                }

                onPaint: {
                    var ctx = getContext("2d");
                    var s = window.s;
                    ctx.clearRect(0, 0, width, height);
                    if (!window.currentConn || !window.showInfoView || !window.currentPower) return;

                    var time = Date.now() / 1000;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";

                    var tWave1 = time * 2.5;
                    var tWave2 = time * -1.5;
                    var tWave3 = time * 3.4;

                    for (var i = 0; i < orbitRepeater.count; i++) {
                        var item = orbitRepeater.itemAt(i);
                        if (!item || !item.isLoaded) continue;

                        var targetX = item.x + item.width / 2;
                        var targetY = item.y + item.height / 2;

                        function drawCurvedStrands(startX, startY, parentFade, parentWidth) {
                            var dx = targetX - startX;
                            var dy = targetY - startY;
                            var fullDist = Math.sqrt(dx * dx + dy * dy);

                            if (fullDist < s(10)) return;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);

                            var coreVisualRadius = parentWidth / 2;
                            var startOffset = coreVisualRadius + s(5);
                            var endOffset = s(26);

                            var drawDist = fullDist - startOffset - endOffset;
                            if (drawDist <= 0) return;

                            var steps = 22;
                            var perpX = -sinA;
                            var perpY = cosA;

                            var sX = startX + cosA * startOffset;
                            var sY = startY + sinA * startOffset;

                            var distanceFactor = Math.max(0, 1.0 - (fullDist / 420.0));
                            var dynamicLineWidthCore = s(1.0) + (distanceFactor * s(1.2));
                            var dynamicLineWidthGlow = s(4.5) + (distanceFactor * s(3.0));
                            var dynamicAlpha = (0.35 + (distanceFactor * 0.65)) * parentFade;

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var m = 1; m <= steps; m++) {
                                var tm = m / steps;
                                var currentDistM = drawDist * tm;
                                var envelopeM = Math.sin(tm * Math.PI);
                                var offsetM = Math.sin(tWave3 + tm * 9 + i) * s(9) * envelopeM + ((Math.sin(time * 12 + m) - 0.5) * s(2.0) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDistM + perpX * offsetM, sY + sinA * currentDistM + perpY * offsetM);
                            }
                            ctx.lineWidth = dynamicLineWidthGlow;
                            ctx.strokeStyle = window.activeColor;
                            ctx.globalAlpha = dynamicAlpha * 0.22;
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var j = 1; j <= steps; j++) {
                                var t = j / steps;
                                var currentDist = drawDist * t;
                                var envelope = Math.sin(t * Math.PI);
                                var offset = Math.sin(tWave1 + t * 6 - i) * s(5.5) * envelope + ((Math.cos(time * 10 - j) - 0.5) * s(2.5) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDist + perpX * offset, sY + sinA * currentDist + perpY * offset);
                            }
                            ctx.lineWidth = dynamicLineWidthCore * 2.0;
                            ctx.strokeStyle = Qt.lighter(window.activeColor, 1.35);
                            ctx.globalAlpha = dynamicAlpha * 0.55;
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var k = 1; k <= steps; k++) {
                                var tk = k / steps;
                                var currentDistK = drawDist * tk;
                                var envelopeK = Math.sin(tk * Math.PI);
                                var offsetK = Math.cos(tWave2 + tk * 8 + i * 2) * s(7) * envelopeK + ((Math.sin(time * 14 + k) - 0.5) * s(1.8) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDistK + perpX * offsetK, sY + sinA * currentDistK + perpY * offsetK);
                            }
                            ctx.lineWidth = dynamicLineWidthCore;
                            ctx.strokeStyle = "#ffffff";
                            ctx.globalAlpha = dynamicAlpha * 0.95;
                            ctx.stroke();
                        }

                        if (typeof item.myParentIdx === "number" && item.myParentIdx === -1) {
                            for (var c = 0; c < coreRepeater.count; c++) {
                                var cItem = coreRepeater.itemAt(c);
                                if (cItem && cItem.activeTransition > 0.01) {
                                    drawCurvedStrands(cItem.x + cItem.width/2, cItem.y + cItem.height/2, cItem.activeTransition, cItem.width);
                                }
                            }
                        } else if (typeof item.myParentIdx === "number" && item.myParentIdx >= 0 && item.myParentIdx < coreRepeater.count) {
                            var pItem = coreRepeater.itemAt(item.myParentIdx);
                            if (pItem && pItem.activeTransition > 0.01) {
                                drawCurvedStrands(pItem.x + pItem.width/2, pItem.y + pItem.height/2, pItem.activeTransition, pItem.width);
                            }
                        }
                    }
                }
            }

            Item {
                id: orbitContainer
                anchors.fill: parent
                anchors.bottomMargin: window.s(65)
                z: 1

                Repeater {
                    id: coreRepeater
                    model: 5

                    delegate: Item {
                        id: coreContainer

                        property var myDevice: window.currentCores[index]

                        property bool isPrimary: index === 0
                        property bool hasDevice: myDevice !== null
                        property bool isReallyActive: window.currentPower && (hasDevice || (isPrimary && window.activeCoreCount === 0))

                        property real activeTransition: isReallyActive ? 1.0 : 0.0

                        Behavior on activeTransition {
                            enabled: window.visible && window.introState >= 1.0;
                            NumberAnimation { duration: 1400; easing.type: Easing.OutExpo }
                        }

                        property real multiShift: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState

                        width: window.currentPower ? (window.s(170) - (window.s(25) * multiShift) - (window.s(12) * Math.max(0, window.smoothedActiveCoreCount - 2))) : window.s(140)
                        height: width

                        property real myBaseAngle: (window.coreVisualIndices[index] / Math.max(1, window.activeCoreCount)) * Math.PI * 2
                        property real animatedBaseAngle: myBaseAngle
                        Behavior on animatedBaseAngle { enabled: window.visible; NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

                        property real coreOrbitAngle: window.globalOrbitAngle * 1.5 + animatedBaseAngle

                        property real myOrbitRadiusX: window.s(150) + (window.activeCoreCount > 2 ? window.s(15) : 0)
                        property real myOrbitRadiusY: window.s(90) + (window.activeCoreCount > 2 ? window.s(12) : 0)

                        x: window.activeMode === "eth" ? (orbitContainer.width / 2 - width / 2) : ((orbitContainer.width / 2 - width / 2) + (Math.cos(coreOrbitAngle) * myOrbitRadiusX * multiShift * activeTransition))
                        y: window.activeMode === "eth" ? (orbitContainer.height / 2 - height / 2) : ((orbitContainer.height / 2 - height / 2) + (Math.sin(coreOrbitAngle) * myOrbitRadiusY * multiShift * activeTransition))

                        opacity: activeTransition
                        scale: centralCore.bumpScale * (0.8 + 0.2 * activeTransition)
                        visible: opacity > 0.01

                        property string myId: myDevice ? (window.activeMode === "wifi" ? (myDevice.ssid || "") : (window.activeMode === "eth" ? (myDevice.id || "") : (myDevice.mac || ""))) : "unknown"
                        property bool isMyDisconnecting: !!window.disconnectingDevices[myId]

                        property bool showScanning: isPrimary && window.currentPower && !window.currentConn && window.pendingWifiId === "" && window.activeMode !== "eth"
                        property bool showConnected: window.currentConn && hasDevice && window.pendingWifiId === ""
                        property bool showPassword: isPrimary && window.pendingWifiId !== "" && window.activeMode === "wifi"
                        property bool showEthDisconnected: isPrimary && window.currentPower && !window.currentConn && window.activeMode === "eth"

                        MultiEffect {
                            source: centralCore
                            anchors.fill: centralCore
                            shadowEnabled: window.visible && window.currentPower
                            shadowColor: "#000000"
                            shadowOpacity: window.currentPower ? 0.5 : 0.0
                            shadowBlur: 1.2
                            shadowVerticalOffset: window.s(5)
                            z: -1
                            Behavior on shadowOpacity { enabled: window.visible; NumberAnimation { duration: 600 } }
                        }

                        Rectangle {
                            id: centralCore
                            anchors.fill: parent
                            radius: width / 2

                            property real disconnectFill: 0.0
                            property bool disconnectTriggered: false
                            property real flashOpacity: 0.0
                            property real bumpScale: 1.0
                            property bool isDangerState: coreMa.containsMouse || disconnectFill > 0 || isMyDisconnecting

                            SequentialAnimation on bumpScale {
                                id: coreBumpAnim
                                running: false
                                NumberAnimation { to: 1.15; duration: 200; easing.type: Easing.OutBack }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.OutQuint }
                            }

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop {
                                    position: 0.0
                                    color: {
                                        if (!window.currentPower) return ThemeBackend.mantle;
                                        if (isMyDisconnecting) return ThemeBackend.surface0;
                                        if (centralCore.isDangerState && window.currentConn && !showPassword) return Qt.tint(Qt.lighter(window.activeColor, 1.15), Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.75));
                                        return window.currentConn || showPassword ? Qt.lighter(window.activeColor, 1.15) : ThemeBackend.surface0;
                                    }
                                    Behavior on color { enabled: window.visible; ColorAnimation { duration: 300 } }
                                }
                                GradientStop {
                                    position: 1.0
                                    color: {
                                        if (!window.currentPower) return ThemeBackend.crust;
                                        if (isMyDisconnecting) return ThemeBackend.base;
                                        if (centralCore.isDangerState && window.currentConn && !showPassword) return Qt.tint(window.activeColor, Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.75));
                                        return window.currentConn || showPassword ? window.activeColor : ThemeBackend.base;
                                    }
                                    Behavior on color { enabled: window.visible; ColorAnimation { duration: 300 } }
                                }
                            }

                            border.color: {
                                if (!window.currentPower) return ThemeBackend.crust;
                                if (isMyDisconnecting) return ThemeBackend.surface0;
                                if (centralCore.isDangerState && window.currentConn && !showPassword) return Qt.tint(Qt.lighter(window.activeColor, 1.1), Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.45));
                                return window.currentConn || showPassword ? Qt.lighter(window.activeColor, 1.1) : ThemeBackend.surface1;
                            }
                            border.width: window.s(2)
                            Behavior on border.color { enabled: window.visible; ColorAnimation { duration: 300 } }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "#ffffff"
                                opacity: centralCore.flashOpacity
                                PropertyAnimation on opacity { id: coreFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                            }

                            Canvas {
                                id: coreWave
                                anchors.fill: parent
                                visible: window.visible && centralCore.disconnectFill > 0
                                opacity: 0.95

                                property real scaleTrigger: window.s(1)
                                onScaleTriggerChanged: if (window.visible) requestPaint()

                                property real wavePhase: 0.0
                                NumberAnimation on wavePhase {
                                    running: window.visible && centralCore.disconnectFill > 0.0 && centralCore.disconnectFill < 1.0
                                    loops: Animation.Infinite
                                    from: 0; to: Math.PI * 2; duration: 800
                                }
                                onWavePhaseChanged: if (window.visible) requestPaint()
                                Connections { target: centralCore; enabled: window.visible; function onDisconnectFillChanged() { if (window.visible) coreWave.requestPaint() } }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    var s = window.s;
                                    ctx.clearRect(0, 0, width, height);
                                    if (centralCore.disconnectFill <= 0.001) return;

                                    var r = width / 2;
                                    var fillY = height * (1.0 - centralCore.disconnectFill);

                                    ctx.save();
                                    ctx.beginPath();
                                    ctx.arc(r, r, r, 0, 2 * Math.PI);
                                    ctx.clip();

                                    ctx.beginPath();
                                    ctx.moveTo(0, fillY);
                                    if (centralCore.disconnectFill < 0.99) {
                                        var waveAmp = s(10) * Math.sin(centralCore.disconnectFill * Math.PI);
                                        var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                        var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                        ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    } else {
                                        ctx.lineTo(width, 0);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    }
                                    ctx.closePath();

                                    var grad = ctx.createLinearGradient(0, height, 0, fillY);
                                    grad.addColorStop(0, ThemeBackend.crust.toString());
                                    grad.addColorStop(1, ThemeBackend.surface2.toString());
                                    ctx.fillStyle = grad;
                                    ctx.fill();
                                    ctx.restore();
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(30)
                                height: width
                                radius: width / 2
                                color: centralCore.isDangerState && window.currentConn && !showPassword ? ThemeBackend.red : window.activeColor
                                opacity: (window.currentConn || showPassword) && !isMyDisconnecting ? (centralCore.isDangerState && !showPassword ? 0.45 : 0.15) : 0.0
                                z: -1
                                Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }
                                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300 } }

                                SequentialAnimation on scale {
                                    loops: Animation.Infinite; running: window.visible && (window.currentConn || showPassword)
                                    NumberAnimation { to: 1.1; duration: 2000; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(12)
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: centralCore.isDangerState && !showPassword ? ThemeBackend.red : window.activeColor
                                border.width: window.s(2)
                                z: -2

                                property real pulseOp: 0.0
                                property real pulseSc: 1.0
                                opacity: ((window.currentConn || showPassword) && window.showInfoView && window.currentPower && !isMyDisconnecting) ? pulseOp : 0.0
                                scale: pulseSc

                                Timer {
                                    interval: 45
                                    running: window.visible && parent.opacity > 0.01
                                    repeat: true
                                    onTriggered: {
                                        var time = Date.now() / 1000;
                                        parent.pulseOp = 0.3 + Math.sin(time * 2.5) * 0.15;
                                        parent.pulseSc = 1.02 + Math.cos(time * 3.0) * 0.02;
                                    }
                                }
                            }

                            Item {
                                anchors.fill: parent
                                opacity: showScanning ? 1.0 : 0.0
                                visible: opacity > 0.01
                                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 400 } }

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.4; height: width; radius: width / 2
                                        color: "transparent"
                                        border.color: window.activeColor; border.width: window.s(2)
                                        SequentialAnimation on scale {
                                            running: window.visible && showScanning; loops: Animation.Infinite
                                            PauseAnimation { duration: index * 400 }
                                            NumberAnimation { from: 1.0; to: 2.5; duration: 2000; easing.type: Easing.OutSine }
                                        }
                                        SequentialAnimation on opacity {
                                            running: window.visible && showScanning; loops: Animation.Infinite
                                            PauseAnimation { duration: index * 400 }
                                            NumberAnimation { from: 0.8; to: 0.0; duration: 2000; easing.type: Easing.OutSine }
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(40) - (window.s(12) * coreContainer.multiShift)
                                    color: window.activeColor
                                    text: window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯")
                                    SequentialAnimation on opacity {
                                        running: window.visible && showScanning; loops: Animation.Infinite
                                        NumberAnimation { to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(8)
                                visible: showEthDisconnected
                                opacity: visible ? 1.0 : 0.0
                                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300 } }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(40); color: ThemeBackend.overlay0; text: "󰈂" }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(13); color: ThemeBackend.overlay0; text: window.currentPowerPending ? (window.expectedEthPower === "on" ? (I18n.t("network.status.powering_on") || "Powering on...") : (I18n.t("network.status.powering_off") || "Powering off...")) : (I18n.t("network.status.disconnected") || "Disconnected") }
                            }

                            Item {
                                id: pwdLayer
                                anchors.fill: parent
                                opacity: showPassword ? 1.0 : 0.0
                                visible: opacity > 0.01
                                scale: showPassword ? 1.0 : 0.8
                                Behavior on scale { enabled: window.visible; NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300; easing.type: Easing.OutSine } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: window.s(6)

                                    Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(28); color: ThemeBackend.crust; text: "󰤨" }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: pwdLayer.width - window.s(30)
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                        color: ThemeBackend.crust; text: window.pendingWifiSsid; elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: pwdLayer.width - window.s(30); height: window.s(32)
                                        radius: ThemeBackend.borderRadius
                                        color: ThemeBackend.surface0
                                        border.color: wifiPasswordField.activeFocus ? ThemeBackend.crust : "transparent"
                                        border.width: 1
                                        Behavior on border.color { enabled: window.visible; ColorAnimation { duration: 200 } }

                                        TextInput {
                                            id: wifiPasswordField
                                            anchors.fill: parent
                                            anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12)
                                            verticalAlignment: TextInput.AlignVCenter
                                            font.family: ThemeBackend.fontFamily; font.pixelSize: window.s(12); color: ThemeBackend.text
                                            echoMode: TextInput.Password; clip: true
                                            onAccepted: {
                                                if (text.trim() !== "") {
                                                    window.connectDevice(window.activeMode, window.pendingWifiId, window.pendingWifiSsid, text);
                                                    window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = "";
                                                    window.forceActiveFocus();
                                                }
                                            }
                                            Keys.onEscapePressed: { window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = ""; window.forceActiveFocus(); }
                                        }
                                    }
                                }

                                Timer { id: deferFocusTimer; interval: 50; onTriggered: wifiPasswordField.forceActiveFocus() }
                                onVisibleChanged: { if (visible) { wifiPasswordField.text = ""; deferFocusTimer.start(); } }
                            }

                            Item {
                                id: showConnectedItem
                                anchors.fill: parent
                                opacity: showConnected ? 1.0 : 0.0
                                visible: opacity > 0.01
                                scale: showConnected ? 1.0 : 0.95
                                Behavior on scale { enabled: window.visible; NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 300; easing.type: Easing.OutSine } }

                                ColumnLayout {
                                    id: baseCoreText
                                    anchors.centerIn: parent
                                    spacing: window.s(3)

                                    Text {
                                        id: coreIconText
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: window.s(40) - (window.s(12) * coreContainer.multiShift)
                                        color: isMyDisconnecting ? ThemeBackend.overlay1 : ThemeBackend.crust
                                        text: isMyDisconnecting ? "" : (coreMa.containsMouse ? (window.activeMode === "wifi" ? "󰖪" : (window.activeMode === "eth" ? "󰈂" : "󰂲")) : (coreContainer.myDevice ? (coreContainer.myDevice.icon || (window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯"))) : ""))
                                        Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }
                                    }
                                    LoadingDots { Layout.alignment: Qt.AlignHCenter; visible: isMyDisconnecting; dotCol: ThemeBackend.overlay1 }
                                    Text {
                                        id: coreNameText
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: window.s(130) - (window.s(40) * coreContainer.multiShift)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Black
                                        font.pixelSize: window.s(14) - (window.s(3) * coreContainer.multiShift)
                                        color: isMyDisconnecting ? ThemeBackend.overlay1 : ThemeBackend.crust
                                        text: coreContainer.myDevice ? (window.activeMode === "wifi" ? (coreContainer.myDevice.ssid || "") : (coreContainer.myDevice.name || "")) : ""
                                        elide: Text.ElideRight
                                        Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }
                                    }
                                    Text {
                                        id: coreStatusText
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                        color: isMyDisconnecting ? ThemeBackend.overlay1 : (coreMa.containsMouse ? ThemeBackend.crust : "#99000000")
                                        text: isMyDisconnecting ? (I18n.t("network.status.disconnecting") || "Disconnecting...") : (centralCore.disconnectFill > 0.01 ? (I18n.t("network.status.hold") || "Hold to Disconnect") : (I18n.t("network.status.connected") || "Connected"))
                                        Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }
                                    }
                                }

                                Item {
                                    id: waveClipItem
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    property real clipWaveAmp: window.s(10) * Math.sin(centralCore.disconnectFill * Math.PI)
                                    property real clipPhaseOffset: Math.sin(coreWave.wavePhase) - Math.cos(coreWave.wavePhase)
                                    property real clipCenterOffset: centralCore.disconnectFill > 0.01 && centralCore.disconnectFill < 0.99 ? 0.375 * clipWaveAmp * clipPhaseOffset : 0
                                    height: Math.max(0, Math.min(parent.height, (parent.height * centralCore.disconnectFill) + clipCenterOffset))
                                    clip: true
                                    visible: centralCore.disconnectFill > 0

                                    ColumnLayout {
                                        spacing: window.s(3)
                                        x: waveClipItem.width / 2 - width / 2
                                        y: (centralCore.height / 2) - (height / 2) - (centralCore.height - waveClipItem.height)

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: window.s(40) - (window.s(12) * coreContainer.multiShift)
                                            color: ThemeBackend.text
                                            text: isMyDisconnecting ? "" : (coreMa.containsMouse ? (window.activeMode === "wifi" ? "󰖪" : (window.activeMode === "eth" ? "󰈂" : "󰂲")) : (coreContainer.myDevice ? (coreContainer.myDevice.icon || (window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯"))) : ""))
                                        }
                                        LoadingDots { Layout.alignment: Qt.AlignHCenter; visible: isMyDisconnecting; dotCol: ThemeBackend.text }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.maximumWidth: window.s(130) - (window.s(40) * coreContainer.multiShift)
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black
                                            font.pixelSize: window.s(14) - (window.s(3) * coreContainer.multiShift)
                                            color: ThemeBackend.text
                                            text: coreContainer.myDevice ? (window.activeMode === "wifi" ? (coreContainer.myDevice.ssid || "") : (coreContainer.myDevice.name || "")) : ""
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                            color: ThemeBackend.text
                                            text: isMyDisconnecting ? (I18n.t("network.status.disconnecting") || "Disconnecting...") : (centralCore.disconnectFill > 0.01 ? (I18n.t("network.status.hold") || "Hold to Disconnect") : (I18n.t("network.status.connected") || "Connected"))
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: coreMa
                                anchors.fill: parent
                                enabled: window.visible
                                hoverEnabled: window.visible
                                cursorShape: window.currentConn && !isMyDisconnecting && !showPassword ? Qt.PointingHandCursor : Qt.ArrowCursor

                                onEntered: {
                                    if (window.currentConn && !showPassword) {
                                        window.disconnectHoverCount++;
                                    }
                                }
                                onExited: {
                                    if (window.currentConn && !showPassword) {
                                        window.disconnectHoverCount = Math.max(0, window.disconnectHoverCount - 1);
                                    }
                                }

                                onPressed: {
                                    if (window.currentConn && !isMyDisconnecting && !centralCore.disconnectTriggered && !showPassword) {
                                        coreDrainAnim.stop();
                                        coreFillAnim.start();
                                    }
                                }
                                onReleased: {
                                    if (!centralCore.disconnectTriggered && !isMyDisconnecting && !showPassword) {
                                        coreFillAnim.stop();
                                        coreDrainAnim.start();
                                    }
                                }
                            }

                            NumberAnimation {
                                id: coreFillAnim
                                target: centralCore
                                property: "disconnectFill"
                                to: 1.0
                                duration: 800 * (1.0 - centralCore.disconnectFill)
                                easing.type: Easing.InSine
                                onFinished: {
                                    if (!coreMa.pressed) {
                                        centralCore.disconnectFill = 0.0;
                                        return;
                                    }

                                    centralCore.disconnectTriggered = true;
                                    centralCore.flashOpacity = 0.6;
                                    coreFlashAnim.start();
                                    coreBumpAnim.start();

                                    Sounds.playSfx("network/disconnect.wav");

                                    let dd = window.disconnectingDevices;
                                    dd[coreContainer.myId] = true;
                                    window.disconnectingDevices = Object.assign({}, dd);
                                    busyTimeout.restart();

                                    if (window.activeMode === "bt") {
                                        let devList = window.getBtDevicesList();
                                        let devToDisconnect = null;
                                        for (let i = 0; i < devList.length; i++) {
                                            if (devList[i] && devList[i].address === coreContainer.myId) { devToDisconnect = devList[i]; break; }
                                        }
                                        if (devToDisconnect) devToDisconnect.disconnect();
                                    } else if (window.activeMode === "eth") {
                                        if (window.ethDevice) window.ethDevice.disconnect();
                                    } else if (window.activeMode === "wifi") {
                                        if (window.wifiDevice) window.wifiDevice.disconnect();
                                    }

                                    centralCore.disconnectFill = 0.0;
                                    centralCore.disconnectTriggered = false;
                                }
                            }

                            NumberAnimation {
                                id: coreDrainAnim
                                target: centralCore
                                property: "disconnectFill"
                                to: 0.0
                                duration: 1500 * centralCore.disconnectFill
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: window.currentPower ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

                Repeater {
                    id: orbitRepeater
                    model: (window.currentConn && window.showInfoView) ? infoListModel : (window.activeMode === "wifi" ? wifiListModel : (window.activeMode === "bt" ? btListModel : null))

                    delegate: Item {
                        id: floatCardDelegateContainer
                        width: window.s(150); height: window.s(52)

                        property bool isLoaded: false
                        opacity: (isLoaded && window.currentPower) ? 1.0 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                        property real entryAnim: isLoaded ? 1.0 : 0.0
                        Behavior on entryAnim { enabled: window.visible; NumberAnimation { duration: 600; easing.type: Easing.OutBack } }

                        Connections {
                            target: window
                            function onVisibleChanged() {
                                if (!window.visible) {
                                    floatCardDelegateContainer.isLoaded = false;
                                }
                            }
                            function onCurrentPowerChanged() {
                                if (!window.currentPower) {
                                    floatCardDelegateContainer.isLoaded = false;
                                }
                            }
                        }

                        Timer {
                            id: entranceTimer
                            running: window.visible && window.currentPower && !floatCardDelegateContainer.isLoaded
                            interval: window.activeMode === "eth" ? (600 + (index * 80)) : (40 + (index * 30))
                            onTriggered: floatCardDelegateContainer.isLoaded = true
                        }

                        Component.onCompleted: {
                            if (window.visible && window.currentPower) {
                                entranceTimer.restart();
                            }
                        }

                        property int myParentIdx: (typeof model !== "undefined" && model !== null && typeof model.parentIndex !== "undefined") ? model.parentIndex : ((typeof parentIndex !== "undefined" && parentIndex !== null) ? parentIndex : -1)

                        property int siblingsCount: {
                            let c = 0;
                            let m = orbitRepeater.model;
                            if (m && typeof m.count === "number") {
                                for (let i = 0; i < m.count; i++) {
                                    let d = m.get(i);
                                    if (d && (typeof d.parentIndex !== "undefined" ? d.parentIndex : -1) === myParentIdx) c++;
                                }
                            }
                            return Math.max(1, c);
                        }
                        property int localIndex: {
                            let idx = 0;
                            let m = orbitRepeater.model;
                            if (m && typeof m.count === "number" && typeof index === "number") {
                                for (let i = 0; i < index && i < m.count; i++) {
                                    let d = m.get(i);
                                    if (d && (typeof d.parentIndex !== "undefined" ? d.parentIndex : -1) === myParentIdx) idx++;
                                }
                            }
                            return idx;
                        }

                        property real unifiedRatio: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState

                        property real activeCount: (unifiedRatio > 0.5 && myParentIdx !== -1) ? siblingsCount : orbitRepeater.count
                        property real dynamicScale: activeCount > 10 ? Math.max(0.6, 12.0 / activeCount) : (unifiedRatio > 0.5 ? (window.activeCoreCount > 2 ? 0.7 : 0.8) : 1.0)

                        property real safeMultiShift: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState
                        property var pItem: (myParentIdx !== -1 && myParentIdx >= 0 && myParentIdx < coreRepeater.count) ? coreRepeater.itemAt(myParentIdx) : null

                        property real safeParentX: (pItem && !isNaN(pItem.x)) ? (orbitContainer.width / 2) + (Math.cos(parentCoreAngle) * (pItem.myOrbitRadiusX || 0) * safeMultiShift * (pItem.activeTransition || 0)) : (orbitContainer.width / 2)
                        property real safeParentY: (pItem && !isNaN(pItem.y)) ? (orbitContainer.height / 2) + (Math.sin(parentCoreAngle) * (pItem.myOrbitRadiusY || 0) * safeMultiShift * (pItem.activeTransition || 0)) : (orbitContainer.height / 2)

                        property real parentBaseAngle: pItem ? pItem.animatedBaseAngle : 0

                        property real targetSingleBaseAngle: (index / Math.max(1, orbitRepeater.count)) * Math.PI * 2
                        property real singleBaseAngle: targetSingleBaseAngle
                        Behavior on singleBaseAngle { enabled: window.visible; NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                        property real singleLiveAngle: (window.globalOrbitAngle * 1.5) + singleBaseAngle

                        property real arcSpread: Math.PI * 0.8
                        property real targetNodeOffset: (siblingsCount > 1) ? ((localIndex / (siblingsCount - 1)) - 0.5) * arcSpread : 0
                        property real nodeOffset: targetNodeOffset
                        Behavior on nodeOffset { enabled: window.visible; NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                        property real parentCoreAngle: (window.globalOrbitAngle * 1.5) + parentBaseAngle
                        property real multiLiveAngle: myParentIdx === -1 ? singleLiveAngle : (parentCoreAngle + nodeOffset)

                        property int ringIndex: (typeof isInfoNode !== "undefined" && isInfoNode) ? 0 : index % 2
                        property real targetRingOffset: ringIndex * window.s(32)
                        property real ringOffset: targetRingOffset
                        Behavior on ringOffset { enabled: window.visible; NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                        property real singleRadX: (typeof isInfoNode !== "undefined" && isInfoNode) ? window.s(253) : window.s(260) + ringOffset
                        property real singleRadY: (typeof isInfoNode !== "undefined" && isInfoNode) ? window.s(154) : window.s(160) + ringOffset

                        property real multiRadX: (typeof isInfoNode !== "undefined" && isInfoNode) ? (myParentIdx === -1 ? 0 : (window.activeCoreCount > 2 ? window.s(165) : window.s(149))) : window.s(270) + ringOffset
                        property real multiRadY: (typeof isInfoNode !== "undefined" && isInfoNode) ? (myParentIdx === -1 ? 0 : (window.activeCoreCount > 2 ? window.s(165) : window.s(149))) : window.s(190) + ringOffset

                        property real currentRadX: window.activeMode === "eth" ? window.s(253) : ((singleRadX * (1 - unifiedRatio)) + (multiRadX * unifiedRatio))
                        property real currentRadY: window.activeMode === "eth" ? window.s(154) : ((singleRadY * (1 - unifiedRatio)) + (multiRadY * unifiedRatio))
                        property real currentAngle: (singleLiveAngle * (1 - unifiedRatio)) + (multiLiveAngle * unifiedRatio)

                        property real pwrDrift: window.currentPower ? 0 : window.s(32)
                        Behavior on pwrDrift { enabled: window.visible; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                        property real animRadX: (currentRadX + pwrDrift) * entryAnim
                        property real animRadY: (currentRadY + pwrDrift) * entryAnim

                        property real targetX: {
                            let tx = myParentIdx === -1
                                ? (orbitContainer.width / 2) - (width / 2) + Math.cos(currentAngle) * animRadX
                                : safeParentX - (width / 2) + Math.cos(currentAngle) * animRadX;
                            return isNaN(tx) ? (orbitContainer.width / 2 - width / 2) : tx;
                        }

                        property real targetY: {
                            let ty = myParentIdx === -1
                                ? (orbitContainer.height / 2) - (height / 2) + Math.sin(currentAngle) * animRadY
                                : safeParentY - (height / 2) + Math.sin(currentAngle) * animRadY;
                            return isNaN(ty) ? (orbitContainer.height / 2 - height / 2) : ty;
                        }

                        property real liveBob: myParentIdx === -1 && (typeof isInfoNode !== "undefined" && isInfoNode)
                            ? Math.sin(window.globalOrbitAngle * 6) * window.s(10) * (1 - unifiedRatio)
                            : 0

                        x: targetX
                        y: targetY + liveBob

                        property bool isHoveredOrHighlighted: isMyActionable ? fillBtn.isHoveredOrHighlighted : clickBtn.isHoveredOrHighlighted
                        property real currentPopScale: isMyActionable ? fillBtn.popScale : clickBtn.popScale

                        scale: (!isLoaded ? 0.0 : (isHoveredOrHighlighted ? dynamicScale * 1.025 : dynamicScale)) * currentPopScale
                        Behavior on scale { enabled: window.visible; NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                        z: cardHoverHandler.hovered ? 10 : index

                        HoverHandler {
                            id: cardHoverHandler
                            enabled: window.visible
                            onHoveredChanged: {
                                if (hovered) window.hoveredCardCount++;
                                else window.hoveredCardCount = Math.max(0, window.hoveredCardCount - 1);
                            }
                        }

                        Component.onDestruction: {
                            if (cardHoverHandler.hovered) {
                                window.hoveredCardCount = Math.max(0, window.hoveredCardCount - 1);
                            }
                        }

                        property string itemId: typeof model !== "undefined" && model !== null && model.id !== undefined ? model.id : (typeof id !== "undefined" && id !== null ? id : "")
                        property bool isFailed: window.failedId === itemId
                        property bool isMyBusy: window.connectingId === itemId || !!window.busyTasks[itemId]

                        property bool isPairedBT: window.activeMode === "bt" && (typeof action !== "undefined" && action === "Connect")
                        property bool isTargetWifi: window.activeMode === "wifi" && !window.isWifiConn && itemId === window.targetWifiSsid
                        property bool isSpecialAction: itemId === "action_scan" || itemId === "action_settings" || itemId === "ip_0" || itemId.indexOf("forget_") === 0
                        property bool isHighlighted: isPairedBT || isTargetWifi || isSpecialAction

                        property bool isCurrentlyConnected: {
                            if (window.activeMode === "eth") return (window.ethConnected && window.ethConnected.id === itemId);
                            if (window.activeMode === "wifi") return (window.wifiConnected && window.wifiConnected.ssid === itemId);
                            for (let i = 0; i < window.btConnected.length; i++) {
                                if (window.btConnected[i] && window.btConnected[i].mac === itemId) return true;
                            }
                            return false;
                        }

                        property real myFillLevel: isCurrentlyConnected ? 1.0 : 0.0

                        property string myButtonText: {
                            let n = typeof model !== "undefined" && model !== null && model.name !== undefined ? model.name : (typeof name !== "undefined" && name !== null ? name : "");
                            return n !== "" ? n : (typeof ssid !== "undefined" ? ssid : "");
                        }

                        property string myButtonIcon: typeof icon !== "undefined" ? icon : ""
                        property bool isMyActionable: typeof isActionable !== "undefined" ? isActionable : true

                        property color dynamicTextColor: {
                            if (isFailed) return ThemeBackend.red;
                            if (isHighlighted) return window.activeColor;
                            return ThemeBackend.text;
                        }

                        function handleTrigger() {
                            let currentCmd = typeof cmdStr !== "undefined" ? cmdStr : "";
                            let currentAction = typeof action !== "undefined" ? action : "";
                            let currentSsid = typeof ssid !== "undefined" ? ssid : "";
                            let currentMac = typeof mac !== "undefined" ? mac : "";
                            let currentIsInfoNode = typeof isInfoNode !== "undefined" ? isInfoNode : false;

                            if (currentCmd === "TOGGLE_VIEW") {
                                window.showInfoView = !window.showInfoView;
                            } else if (currentIsInfoNode && currentAction === "IP Address") {
                                let itemName = myButtonText;
                                if (itemName && itemName !== "No IP" && itemName !== "Unknown") {
                                    Sounds.playSfx("network/switch.wav");
                                    Quickshell.execDetached(["bash", "-c", currentCmd]);
                                }
                            } else if (currentIsInfoNode && currentCmd) {
                                if (currentCmd.indexOf("BT_FORGET_") === 0) {
                                    let macToForget = currentCmd.substring(10);
                                    window.withBtOpLock(macToForget, function() {
                                        let devList = window.getBtDevicesList();
                                        let devToForget = null;
                                        for (let i = 0; i < devList.length; i++) {
                                            if (devList[i] && devList[i].address === macToForget) { devToForget = devList[i]; break; }
                                        }
                                        if (!devToForget) return;

                                        let map = Object.assign({}, window.btDeviceMap);
                                        delete map[macToForget];
                                        window.btDeviceMap = map;

                                        let bt = window.busyTasks; delete bt[macToForget]; window.busyTasks = Object.assign({}, bt);
                                        let dd = window.disconnectingDevices; delete dd[macToForget]; window.disconnectingDevices = Object.assign({}, dd);
                                        if (window.connectingId === macToForget) window.connectingId = "";
                                        if (window.failedId === macToForget) window.failedId = "";

                                        devToForget.forget();
                                        window.requestBtRebuild();
                                    });
                                } else {
                                    Quickshell.execDetached(["sh", "-c", currentCmd]);
                                }
                            } else {
                                let sec = typeof security !== "undefined" && security ? security.trim().toLowerCase() : "";
                                let isSecure = sec !== "" && sec !== "open" && sec !== "--" && sec !== "none";
                                let isSaved = false;
                                if (window.wifiDevice && window.wifiDevice.networks) {
                                    let nets = window.wifiDevice.networks.values;
                                    for (let i = 0; i < nets.length; i++) {
                                        let n = nets[i];
                                        if (n && n.name === currentSsid && n.known) { isSaved = true; break; }
                                    }
                                }

                                if (window.activeMode === "wifi" && isSecure && !isSaved) {
                                    window.pendingWifiSsid = currentSsid;
                                    window.pendingWifiId = itemId;
                                } else {
                                    window.connectDevice(window.activeMode, itemId, window.activeMode === "wifi" ? currentSsid : (window.activeMode === "eth" ? itemId : currentMac), "");
                                }
                            }
                        }

                        FillButton {
                            id: fillBtn
                            visible: isMyActionable
                            enabled: !isMyBusy && !window.isBtOpBusy(itemId)
                            anchors.fill: parent
                            cornerRadius: ThemeBackend.borderRadius
                            fillDuration: 600
                            buttonText: ""
                            buttonIcon: ""
                            accentColor: window.activeColor
                            baseColor: ThemeBackend.base
                            hoverColor: ThemeBackend.surface0
                            textColor: dynamicTextColor
                            filledTextColor: ThemeBackend.crust
                            action_highlight: isHighlighted
                            contentAlignment: Qt.AlignLeft
                            horizontalPadding: window.s(10)
                            textFontSize: window.s(12)
                            iconFontSize: window.s(18)
                            fillLevel: myFillLevel
                            onTriggered: floatCardDelegateContainer.handleTrigger()
                        }

                        ClickButton {
                            id: clickBtn
                            visible: !isMyActionable
                            enabled: !isMyBusy && !window.isBtOpBusy(itemId)
                            anchors.fill: parent
                            cornerRadius: ThemeBackend.borderRadius
                            accentColor: ThemeBackend.surface0
                            textColor: dynamicTextColor
                            action_highlight: isHighlighted
                            buttonText: ""
                            buttonIcon: ""
                            onTriggered: floatCardDelegateContainer.handleTrigger()
                        }

                        Item {
                            id: cardContentOverlay
                            anchors.fill: parent

                            Item {
                                id: baseContent
                                anchors.fill: parent
                                anchors.leftMargin: window.s(10)
                                anchors.rightMargin: window.s(10)

                                Row {
                                    id: baseRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: window.s(6)
                                    height: parent.height

                                    Text {
                                        id: overlayIcon
                                        visible: myButtonIcon !== ""
                                        text: myButtonIcon
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(18)
                                        color: dynamicTextColor
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }
                                    }

                                    Item {
                                        id: marqueeClip
                                        width: floatCardDelegateContainer.width - window.s(20) - (overlayIcon.visible ? overlayIcon.implicitWidth + window.s(6) : 0)
                                        height: parent.height
                                        clip: true

                                        Item {
                                            id: marqueeContainer
                                            height: parent.height
                                            width: marqueeRow.implicitWidth

                                            Row {
                                                id: marqueeRow
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: window.s(30)

                                                Text {
                                                    id: overlayTextMain
                                                    text: myButtonText
                                                    font.family: ThemeBackend.fontFamily
                                                    font.weight: Font.Bold
                                                    font.pixelSize: window.s(12)
                                                    color: dynamicTextColor
                                                    Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }

                                                    onTextChanged: {
                                                        marqueeContainer.x = 0;
                                                        if (implicitWidth > marqueeClip.width && window.visible) {
                                                            marqueeAnim.restart();
                                                        } else {
                                                            marqueeAnim.stop();
                                                        }
                                                    }
                                                }

                                                Text {
                                                    id: overlayTextClone
                                                    text: myButtonText
                                                    font.family: ThemeBackend.fontFamily
                                                    font.weight: Font.Bold
                                                    font.pixelSize: window.s(12)
                                                    color: overlayTextMain.color
                                                    visible: overlayTextMain.implicitWidth > marqueeClip.width
                                                }
                                            }

                                            SequentialAnimation on x {
                                                id: marqueeAnim
                                                loops: Animation.Infinite
                                                running: window.visible && overlayTextMain.implicitWidth > marqueeClip.width

                                                PauseAnimation { duration: 3000 }
                                                NumberAnimation {
                                                    from: 0
                                                    to: -(overlayTextMain.implicitWidth + window.s(30))
                                                    duration: (overlayTextMain.implicitWidth + window.s(30)) * 25
                                                }
                                                PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                id: filledClipItem
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * (isMyActionable ? fillBtn.fillLevel : 0.0)
                                clip: true
                                visible: width > 0

                                Item {
                                    width: cardContentOverlay.width
                                    height: cardContentOverlay.height
                                    anchors.left: parent.left
                                    anchors.top: parent.top

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: window.s(10)
                                        anchors.rightMargin: window.s(10)

                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: window.s(6)
                                            height: parent.height

                                            Text {
                                                visible: myButtonIcon !== ""
                                                text: myButtonIcon
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(18)
                                                color: ThemeBackend.crust
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Item {
                                                width: marqueeClip.width
                                                height: parent.height
                                                clip: true

                                                Item {
                                                    height: parent.height
                                                    width: marqueeContainer.width
                                                    x: marqueeContainer.x

                                                    Row {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: window.s(30)

                                                        Text {
                                                            text: myButtonText
                                                            font.family: ThemeBackend.fontFamily
                                                            font.weight: Font.Bold
                                                            font.pixelSize: window.s(12)
                                                            color: ThemeBackend.crust
                                                        }

                                                        Text {
                                                            text: myButtonText
                                                            font.family: ThemeBackend.fontFamily
                                                            font.weight: Font.Bold
                                                            font.pixelSize: window.s(12)
                                                            color: ThemeBackend.crust
                                                            visible: overlayTextMain.implicitWidth > marqueeClip.width
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

            Switch {
                id: bottomSwitch
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: window.s(18)
                implicitWidth: window.s(320)
                implicitHeight: window.s(42)
                fontPixelSize: window.s(14)
                cornerRadius: ThemeBackend.borderRadius
                accentColor: window.activeColor
                baseColor: "#1affffff"
                textColor: ThemeBackend.text
                activeTextColor: ThemeBackend.crust
                switchSound: "network/switch.wav"
                visible: window.visible && availableModes.length > 0
                enabled: window.visible

                readonly property var availableModes: {
                    let m = [];
                    if (window.ethPresent) m.push({ mode: "eth", label: "󰈀  " + (I18n.t("network.tabs.ethernet") || "Ethernet") });
                    if (window.wifiPresent) m.push({ mode: "wifi", label: "󰤨  " + (I18n.t("network.tabs.wifi") || "Wi-Fi") });
                    if (window.btPresent) m.push({ mode: "bt", label: "󰂯 " + (I18n.t("network.tabs.bluetooth") || "Bluetooth") });
                    return m;
                }

                options: {
                    let opts = [];
                    for (let i = 0; i < availableModes.length; i++) {
                        if (availableModes[i] && availableModes[i].label) {
                            opts.push(availableModes[i].label);
                        }
                    }
                    return opts;
                }

                Binding on currentIndex {
                    value: {
                        let modes = bottomSwitch.availableModes;
                        for (let i = 0; i < modes.length; i++) {
                            if (modes[i] && modes[i].mode === window.activeMode) return i;
                        }
                        return 0;
                    }
                }

                onToggled: val => {
                    if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                    let modes = bottomSwitch.availableModes;
                    if (!modes || modes.length === 0) return;
                    let chosen = "";
                    if (typeof val === "number") {
                        if (val >= 0 && val < modes.length && modes[val]) {
                            chosen = modes[val].mode;
                        }
                    } else if (typeof val === "string") {
                        for (let i = 0; i < modes.length; i++) {
                            if (modes[i] && (modes[i].label === val || modes[i].mode === val)) {
                                chosen = modes[i].mode;
                                break;
                            }
                        }
                    }
                    if (chosen && chosen !== "" && window.activeMode !== chosen) {
                        window.powerAnimAllowed = false;
                        powerAnimBlocker.restart();
                        window.activeMode = chosen;
                    }
                }
            }

            Item {
                id: powerToggleContainer
                z: 100

                property real pwrMorph: window.currentPower ? 1.0 : 0.0
                Behavior on pwrMorph {
                    enabled: window.powerAnimAllowed && window.visible;
                    NumberAnimation { duration: 800; easing.type: Easing.InOutQuint }
                }

                width: window.s(140) + (window.s(42) - window.s(140)) * pwrMorph
                height: width

                x: ((parent.width / 2) - window.s(70)) + ((parent.width - window.s(24) - window.s(42)) - ((parent.width / 2) - window.s(70))) * pwrMorph
                y: (((parent.height - window.s(65)) / 2) - window.s(70)) + ((parent.height - window.s(24) - window.s(42)) - (((parent.height - window.s(65)) / 2) - window.s(70))) * pwrMorph

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: window.s(2)
                    anchors.bottomMargin: -window.s(2)
                    radius: width / 2
                    color: Qt.rgba(0, 0, 0, 0.16)
                    z: -1
                }

                Rectangle {
                    id: powerBtnRect
                    anchors.fill: parent
                    radius: width / 2

                    scale: pwrMa.pressed ? 0.95 : (pwrMa.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { enabled: window.visible; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    color: window.currentPower ? "transparent" : (pwrMa.containsMouse ? Qt.lighter(ThemeBackend.base, 1.6) : Qt.lighter(ThemeBackend.base, 1.3))
                    Behavior on color { enabled: window.visible; ColorAnimation { duration: 200 } }

                    border.color: window.currentPowerPending ? window.activeColor : (window.currentPower ? "transparent" : (pwrMa.containsMouse ? Qt.lighter(ThemeBackend.base, 1.45) : Qt.lighter(ThemeBackend.base, 1.25)))
                    border.width: 1
                    Behavior on border.color { enabled: window.powerAnimAllowed && window.visible; ColorAnimation { duration: 800; easing.type: Easing.InOutQuint } }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        opacity: window.currentPower ? 1.0 : 0.0
                        Behavior on opacity { enabled: window.powerAnimAllowed && window.visible; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.lighter(window.activeColor, 1.15) }
                            GradientStop { position: 1.0; color: window.activeColor }
                        }
                    }

                    Text {
                        id: pwrIcon
                        anchors.centerIn: parent
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(54)
                        scale: 1.0 + ((20.0 / 54.0) - 1.0) * powerToggleContainer.pwrMorph
                        color: window.currentPower ? ThemeBackend.crust : ThemeBackend.subtext0
                        text: window.currentPowerPending ? "󰑮" : ""
                        Behavior on color { enabled: window.powerAnimAllowed && window.visible; ColorAnimation { duration: 800; easing.type: Easing.InOutQuint } }

                        RotationAnimation {
                            target: pwrIcon
                            property: "rotation"
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: window.visible && window.currentPowerPending
                            onRunningChanged: {
                                if (!running) pwrIcon.rotation = 0;
                            }
                        }
                    }

                    MouseArea {
                        id: pwrMa
                        anchors.fill: parent
                        enabled: window.visible
                        hoverEnabled: window.visible
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }

                            if (window.activeMode === "eth") {
                                if (window.ethPowerPending) return;
                                window.expectedEthPower = window.ethPower === "on" ? "off" : "on";
                                window.ethPowerPending = true;
                                powerMinSpinTimer.restart();
                                if (window.expectedEthPower === "on") Sounds.playSfx("network/power_on.wav"); else Sounds.playSfx("network/power_off.wav");
                                ethPendingReset.restart();
                                window.ethPower = window.expectedEthPower;
                                if (window.expectedEthPower === "off") {
                                    if (window.ethDevice) window.ethDevice.disconnect();
                                } else {
                                    if (window.ethDevice && window.ethDevice.network) window.ethDevice.network.connect();
                                }
                            } else if (window.activeMode === "wifi") {
                                if (window.wifiPowerPending) return;
                                window.expectedWifiPower = window.wifiPower === "on" ? "off" : "on";
                                window.wifiPowerPending = true;
                                powerMinSpinTimer.restart();
                                if (window.expectedWifiPower === "on") Sounds.playSfx("network/power_on.wav"); else Sounds.playSfx("network/power_off.wav");
                                wifiPendingReset.restart();
                                window.wifiPower = window.expectedWifiPower;
                                Networking.wifiEnabled = (window.expectedWifiPower === "on");
                            } else {
                                if (window.btPowerPending) return;
                                window.expectedBtPower = window.btPower === "on" ? "off" : "on";
                                window.btPowerPending = true;
                                powerMinSpinTimer.restart();
                                if (window.expectedBtPower === "on") Sounds.playSfx("network/power_on.wav"); else Sounds.playSfx("network/power_off.wav");
                                btPendingReset.restart();
                                window.btPower = window.expectedBtPower;
                                if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = (window.expectedBtPower === "on");
                            }
                        }
                    }
                }
            }
        }
    }
}
