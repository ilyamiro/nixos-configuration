import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import "WindowRegistry.js" as Registry
import "notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: masterWindow.isVisible
        onActivated: switchWidget("hidden", "")
    }

    IpcHandler {
        target: "main"

        function forceReload(): void {
            Quickshell.reload(true);
        }

        function clearNotifications(): void {
            NotificationManager.clearNotifications();
        }

        function handleCommand(cmd: string, targetWidget: string, arg: string): void {
            cmd = cmd || "";
            targetWidget = targetWidget || "";
            arg = arg || "";

            if (cmd === "clearNotifications" || cmd === "clear_notifications" || cmd === "clearNotifs") {
                NotificationManager.clearNotifications();
                return;
            }

            if (cmd === "launcher" || targetWidget === "launcher") {
                if (cmd === "close") {
                    LauncherController.hide();
                } else if (cmd === "open") {
                    ClipboardController.hide();
                    LauncherController.show();
                } else {
                    ClipboardController.hide();
                    LauncherController.toggle();
                }
                return;
            }

            if (cmd === "clipboard" || targetWidget === "clipboard" || cmd === "clip" || targetWidget === "clip") {
                if (cmd === "close") {
                    ClipboardController.hide();
                } else if (cmd === "open") {
                    LauncherController.hide();
                    ClipboardController.show();
                } else {
                    LauncherController.hide();
                    ClipboardController.toggle();
                }
                return;
            }

            if (cmd === "airplane" || targetWidget === "airplane" || cmd === "flight" || targetWidget === "flight") {
                let isAirplane = !Networking.wifiEnabled && !(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled);
                if (isAirplane) {
                    Networking.wifiEnabled = true;
                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true;
                } else {
                    Networking.wifiEnabled = false;
                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = false;
                }
                return;
            }

            let effectivelyActive = masterWindow.targetActive;

            if (cmd === "close") {
                switchWidget("hidden", "");
            } else if (cmd === "toggle" || cmd === "open") {
                if (targetWidget === effectivelyActive) {
                    let currentItem = widgetCache[targetWidget] || widgetStack.currentItem;

                    if (arg !== "" && arg !== masterWindow.activeArg) {
                        masterWindow.activeArg = arg;
                        if (currentItem && currentItem.activeMode !== undefined) {
                            currentItem.activeMode = arg;
                        }
                        if (currentItem && currentItem.gotoTab !== undefined) {
                            currentItem.gotoTab(arg);
                        }
                    } else if (cmd === "toggle") {
                        switchWidget("hidden", "");
                    }
                } else if (getLayout(targetWidget)) {
                    switchWidget(targetWidget, arg);
                }
            } else if (getLayout(cmd)) {
                let legacyArg = targetWidget;

                if (cmd === effectivelyActive) {
                    let currentItem = widgetCache[cmd] || widgetStack.currentItem;
                    if (legacyArg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== legacyArg) {
                        currentItem.activeMode = legacyArg;
                    } else if (legacyArg !== "" && currentItem && currentItem.gotoTab !== undefined) {
                        currentItem.gotoTab(legacyArg);
                    } else {
                        switchWidget("hidden", "");
                    }
                } else {
                    switchWidget(cmd, legacyArg);
                }
            }
        }

        function getWidgetGeometry(widgetName: string): void {
            let layout = getLayout(widgetName);
            if (layout) {
                let geo = {
                    startX: Math.round(layout.rx),
                    startY: Math.round(layout.ry),
                    endX: Math.round(layout.rx + layout.w),
                    endY: Math.round(layout.ry + layout.h)
                };
                Quickshell.execDetached(["bash", "-c", "echo '" + JSON.stringify(geo) + "' > " + Caching.runDir + "/tutorial_target.json"]);
            }
        }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusionMode: ExclusionMode.Ignore
    focusable: true

    implicitWidth: masterWindow.screen ? masterWindow.screen.width : 0
    implicitHeight: masterWindow.screen ? masterWindow.screen.height : 0

    visible: isVisible

    mask: Region { item: topBarHole; intersection: Intersection.Xor }

    property var rawBarSettings: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : ({})
    property string barPosition: (rawBarSettings && rawBarSettings.position !== undefined) ? rawBarSettings.position : "top"
    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false

    readonly property bool isFullscreenActive: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive
    readonly property bool screenReady: masterWindow.width >= 100 && masterWindow.height >= 100

    Item {
        id: topBarHole

        property int barThickness: 48
        property string bp: masterWindow.barPosition
        property bool activeBar: !masterWindow.isBarEffectivelyHidden

        property bool overlapTopLeft: masterWindow.currentActive !== "hidden" && animContainer.x < 10 && animContainer.y < barThickness
        property bool overlapTopRight: masterWindow.currentActive !== "hidden" && (animContainer.x + animContainer.width) > (masterWindow.width - 10) && animContainer.y < barThickness
        property bool overlapBottomLeft: masterWindow.currentActive !== "hidden" && animContainer.x < 10 && (animContainer.y + animContainer.height) > (masterWindow.height - barThickness)
        property bool overlapBottomRight: masterWindow.currentActive !== "hidden" && (animContainer.x + animContainer.width) > (masterWindow.width - 10) && (animContainer.y + animContainer.height) > (masterWindow.height - barThickness)

        x: {
            if (!activeBar) return 0;
            if (bp === "left") return 0;
            if (bp === "right") return masterWindow.width - barThickness;
            if (overlapTopLeft && bp === "top") return animContainer.width;
            if (overlapBottomLeft && bp === "bottom") return animContainer.width;
            return 0;
        }

        y: {
            if (!activeBar) return 0;
            if (bp === "top") return 0;
            if (bp === "bottom") return masterWindow.height - barThickness;
            if (overlapTopLeft && bp === "left") return animContainer.height;
            if (overlapTopRight && bp === "right") return animContainer.height;
            return 0;
        }

        width: {
            if (!activeBar) return 0;
            if (bp === "left" || bp === "right") return barThickness;
            let w = masterWindow.width;
            if (overlapTopLeft && bp === "top") w -= animContainer.width;
            if (overlapTopRight && bp === "top") w -= animContainer.width;
            if (overlapBottomLeft && bp === "bottom") w -= animContainer.width;
            if (overlapBottomRight && bp === "bottom") w -= animContainer.width;
            return Math.max(0, w);
        }

        height: {
            if (!activeBar) return 0;
            if (bp === "top" || bp === "bottom") return barThickness;
            let h = masterWindow.height;
            if (overlapTopLeft && bp === "left") h -= animContainer.height;
            if (overlapBottomLeft && bp === "left") h -= animContainer.height;
            if (overlapTopRight && bp === "right") h -= animContainer.height;
            if (overlapBottomRight && bp === "right") h -= animContainer.height;
            return Math.max(0, h);
        }

        Behavior on x {
            enabled: masterWindow.currentActive !== "hidden" && !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: masterWindow.currentActive !== "hidden" && !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: masterWindow.currentActive !== "hidden" && !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: masterWindow.currentActive !== "hidden" && !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    Item {
        id: preloaderContainer
        visible: false
    }

    property var widgetCache: ({})
    property var componentCache: ({})
    property var _allWidgetNames: ["battery", "network", "volume", "guide", "calendar", "wallpaper", "music", "movies", "notifications", "system"]
    property int _preloadIndex: 0

    function widgetNameForItem(item) {
        for (let name in widgetCache) {
            if (widgetCache[name] === item) return name;
        }
        return null;
    }

    function ensureWidgetItem(name, t) {
        let cached = widgetCache[name];
        if (cached) return cached;

        let comp = componentCache[name];
        if (!comp) {
            comp = typeof t.comp === "string" ? Qt.createComponent(t.comp) : t.comp;
            if (comp) componentCache[name] = comp;
        }
        if (!comp) return null;

        if (comp.status === Component.Loading) return null;
        if (comp.status === Component.Error) {
            console.warn("Widget component failed to load:", name, comp.errorString());
            return null;
        }

        let item = comp.createObject(preloaderContainer);
        if (item) widgetCache[name] = item;
        return item;
    }

    function preloadWidget(name) {
        let t = getLayout(name);
        if (!t || !t.comp) return;
        ensureWidgetItem(name, t);
    }

    Component.onCompleted: {
        preloadStaggerTimer.start();
    }

    Timer {
        id: preloadStaggerTimer
        interval: 150
        repeat: true
        onTriggered: {
            if (masterWindow._preloadIndex >= masterWindow._allWidgetNames.length) {
                preloadStaggerTimer.stop();
                return;
            }
            if (masterWindow.currentActive !== "hidden") {
                return;
            }
            preloadWidget(masterWindow._allWidgetNames[masterWindow._preloadIndex]);
            masterWindow._preloadIndex++;
        }
    }

    property string targetActive: "hidden"
    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > " + Caching.runDir + "/current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: true
    property int switchGeneration: 0

    property int morphDuration:       300
    property int morphDurationSwitch: 300
    property int exitDuration:        180

    property real _animW: 1
    property real _animH: 1
    property real _animX: 0
    property real _animY: 0

    property real _stageW: 1
    property real _stageH: 1

    property real globalUiScale: 1.0

    Notifs.NotificationPopups {
        id: osdPopups
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", `cat "${Config.settingsJsonPath}" 2>/devnull || echo '{}'`]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        let sName = masterWindow.screen ? masterWindow.screen.name : "";
                        let sVal = undefined;

                        if (sName !== "" && parsed.display && parsed.display.monitors && parsed.display.monitors[sName] && parsed.display.monitors[sName].scale !== undefined) {
                            sVal = parsed.display.monitors[sName].scale;
                        } else if (parsed.general && parsed.general.uiScale !== undefined) {
                            sVal = parsed.general.uiScale;
                        } else if (parsed.uiScale !== undefined) {
                            sVal = parsed.uiScale;
                        }

                        if (sVal !== undefined && masterWindow.globalUiScale !== sVal) {
                            masterWindow.globalUiScale = sVal;
                        }

                        if (parsed.bar) {
                            masterWindow.rawBarSettings = parsed.bar;
                            if (parsed.bar.position !== undefined) masterWindow.barPosition = parsed.bar.position;
                            if (parsed.bar.autohide !== undefined) masterWindow.barAutohide = Boolean(parsed.bar.autohide);
                        }
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: settingsWatcher
        command: ["bash", "-c", `while [ ! -f "${Config.settingsJsonPath}" ]; do sleep 1; done; inotifywait -qq -e modify,close_write "${Config.settingsJsonPath}"`]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false;
                settingsReader.running = true;
                settingsWatcher.running = false;
                settingsWatcher.running = true;
            }
        }
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            let b = (Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : {};
            masterWindow.rawBarSettings = b;
            masterWindow.barPosition = (b && b.position !== undefined) ? b.position : "top";
            masterWindow.barAutohide = (b && b.autohide !== undefined) ? Boolean(b.autohide) : false;
        }
    }

    function getLayout(name) {
        let bp = masterWindow.barPosition;
        let effHidden = masterWindow.isBarEffectivelyHidden;

        let result = Registry.getLayout(name, 0, 0, masterWindow.width, masterWindow.height, masterWindow.globalUiScale, bp);
        if (!result) return null;

        let scale = masterWindow.globalUiScale || 1.0;
        let isFixed = (name === "guide" || name === "wallpaper" || name === "notifications" || name === "system" || name === "hidden");

        if (effHidden && !isFixed) {
            let offsetAdjustment = Math.round(46 * scale);
            let adjusted = {
                w: result.w,
                h: result.h,
                rx: result.rx,
                ry: result.ry,
                comp: result.comp
            };

            if (bp === "top") {
                adjusted.ry = Math.max(Math.round(6 * scale), result.ry - offsetAdjustment);
            } else if (bp === "bottom") {
                adjusted.ry = Math.min(masterWindow.height - result.h - Math.round(6 * scale), result.ry + offsetAdjustment);
            } else if (bp === "left" && name !== "calendar") {
                adjusted.rx = Math.max(Math.round(6 * scale), result.rx - offsetAdjustment);
            } else if (bp === "right" && name !== "calendar") {
                adjusted.rx = Math.min(masterWindow.width - result.w - Math.round(6 * scale), result.rx + offsetAdjustment);
            }

            return adjusted;
        }

        return result;
    }

    function recenterX(t, dynW) {
        let originalCenterX = t.rx + Math.floor(t.w / 2);
        return Math.floor(originalCenterX - (dynW / 2));
    }

    readonly property var targetLayout: {
        if (currentActive === "hidden" || currentActive === "") return null;
        if (!screenReady) return null;

        let t = getLayout(currentActive);
        if (!t || !t.w || !t.h || t.w < 10 || t.h < 10) return null;

        if (t.rx < -t.w - 50 || t.ry < -t.h - 50 ||
            t.rx > masterWindow.width + 50 || t.ry > masterWindow.height + 50) {
            return null;
        }

        let item = widgetCache[currentActive];
        let tw = t.w, th = t.h;
        if (item) {
            if (typeof item.targetMasterWidth === "number" && !isNaN(item.targetMasterWidth) && item.targetMasterWidth >= 50) {
                tw = item.targetMasterWidth;
            }
            if (typeof item.targetMasterHeight === "number" && !isNaN(item.targetMasterHeight) && item.targetMasterHeight >= 50) {
                th = item.targetMasterHeight;
            }
        }

        let x = (tw !== t.w) ? recenterX(t, tw) : t.rx;
        return { x: x, y: t.ry, w: tw, h: th };
    }

    onTargetLayoutChanged: {
        if (!targetLayout || masterWindow.currentActive === "hidden" || !masterWindow.isVisible) return;
        masterWindow._animX = targetLayout.x;
        masterWindow._animY = targetLayout.y;
        masterWindow._animW = targetLayout.w;
        masterWindow._animH = targetLayout.h;
        masterWindow._stageW = targetLayout.w;
        masterWindow._stageH = targetLayout.h;
    }

    onIsVisibleChanged: {
        if (isVisible) widgetStack.forceActiveFocus();
    }

    Item {
        id: animContainer
        x: masterWindow._animX
        y: masterWindow._animY
        width: masterWindow._animW
        height: masterWindow._animH
        clip: true

        Item {
            id: contentStage
            width: masterWindow._stageW
            height: masterWindow._stageH
            x: (animContainer.width - width) / 2
            y: (animContainer.height - height) / 2
            transformOrigin: Item.Center

            scale: masterWindow.isVisible ? 1.0 : 0.96
            Behavior on scale {
                NumberAnimation {
                    duration: masterWindow.isVisible ? 280 : 160
                    easing.type: masterWindow.isVisible ? Easing.OutCubic : Easing.InCubic
                }
            }

            opacity: masterWindow.isVisible ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: masterWindow.isVisible ? 200 : 140
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea { anchors.fill: parent }

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true

                replaceEnter: null
                replaceExit: null
                pushEnter: null
                pushExit: null
                popEnter: null
                popExit: null

                Keys.onEscapePressed: (event) => {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                }
            }
        }

        Behavior on x {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
    }

    function switchWidget(newWidget, arg) {
        masterWindow.switchGeneration++;
        let gen = masterWindow.switchGeneration;
        masterWindow.targetActive = newWidget;

        if (delayedClear.running) {
            delayedClear.stop();
        }

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.currentActive = "hidden";
                masterWindow.morphDuration = masterWindow.exitDuration;
                masterWindow.disableMorph = true;
                masterWindow.isVisible = false;

                delayedClear.scheduledGeneration = gen;
                delayedClear.restart();
            }
        } else {
            executeSwitch(newWidget, arg, gen);
        }
    }

    function executeSwitch(newWidget, arg, gen) {
        if (gen !== masterWindow.switchGeneration || newWidget === "hidden") return;

        let t = getLayout(newWidget);
        if (!t || !t.w || !t.h || t.w < 10 || t.h < 10) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration) {
                    executeSwitch(newWidget, arg, gen);
                }
            });
            return;
        }

        let cachedItem = ensureWidgetItem(newWidget, t);
        if (!cachedItem) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration) {
                    executeSwitch(newWidget, arg, gen);
                }
            });
            return;
        }

        if (gen !== masterWindow.switchGeneration) return;

        if (cachedItem.targetMasterWidth !== undefined)  cachedItem.targetMasterWidth  = t.w;
        if (cachedItem.targetMasterHeight !== undefined) cachedItem.targetMasterHeight = t.h;

        let isComingFromHidden = (!masterWindow.isVisible || widgetStack.currentItem === null || masterWindow.currentActive === "hidden");

        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;

        let finalW = (typeof cachedItem.targetMasterWidth === "number" && cachedItem.targetMasterWidth >= 50) ? cachedItem.targetMasterWidth : t.w;
        let finalH = (typeof cachedItem.targetMasterHeight === "number" && cachedItem.targetMasterHeight >= 50) ? cachedItem.targetMasterHeight : t.h;
        let finalX = (finalW !== t.w) ? recenterX(t, finalW) : t.rx;
        let finalY = t.ry;

        masterWindow._animX = finalX;
        masterWindow._animY = finalY;
        masterWindow._animW = finalW;
        masterWindow._animH = finalH;
        masterWindow._stageW = finalW;
        masterWindow._stageH = finalH;

        if (isComingFromHidden) {
            masterWindow.disableMorph = true;
        } else {
            masterWindow.morphDuration = masterWindow.morphDurationSwitch;
            masterWindow.disableMorph = false;
        }

        if (newWidget === "wallpaper" && cachedItem.widgetArg !== undefined) cachedItem.widgetArg = arg;
        if (newWidget === "wallpaper" && cachedItem.refreshForDisplay !== undefined) cachedItem.refreshForDisplay();
        if (arg !== "" && cachedItem.activeMode !== undefined) cachedItem.activeMode = arg;
        if (arg !== "" && cachedItem.gotoTab !== undefined) cachedItem.gotoTab(arg);

        if (widgetStack.currentItem !== cachedItem) {
            widgetStack.replace(cachedItem, {}, StackView.Immediate);
        }

        masterWindow.isVisible = true;

        if (isComingFromHidden) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration && masterWindow.isVisible && masterWindow.currentActive === newWidget) {
                    masterWindow.disableMorph = false;
                }
            });
        }
    }

    Timer {
        id: delayedClear
        interval: 200
        property int scheduledGeneration: -1
        onTriggered: {
            if (masterWindow.currentActive === "hidden" && scheduledGeneration === masterWindow.switchGeneration) {
                masterWindow.disableMorph = true;
            }
        }
    }
}
