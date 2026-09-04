import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../reusables"
import "../"

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: barWindow
            visible: barConfigReady

            property bool pendingReload: false
            property bool startupFilesReady: false
            property bool isRedacting: false

            property var activeToplevel: ToplevelManager.activeToplevel
            property bool isFullscreenActive: {
                if (!activeToplevel || !activeToplevel.fullscreen) return false;
                if (activeToplevel.screens && activeToplevel.screens.length > 0) {
                    return activeToplevel.screens.indexOf(barWindow.screen) !== -1;
                }
                return true;
            }

            onIsFullscreenActiveChanged: {
                if (barWindow.isFullscreenActive) {
                    OsdController.isFullscreen = true;
                } else if (!OsdController.screen || OsdController.screen === barWindow.screen) {
                    OsdController.isFullscreen = false;
                }
            }

            WlrLayershell.keyboardFocus: (barWindow.isNotifOpen || barWindow.isSysOpen)
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            property int configRevision: 0

            Connections {
                target: (typeof Config !== "undefined") ? Config : null
                function onSettingsLoaded() {
                    barWindow.configRevision++;
                }
                function onDataReadyChanged() {
                    if (Config && Config.dataReady) {
                        barWindow.configRevision++;
                    }
                }
                function onRawSettingsChanged() {
                    barWindow.configRevision++;
                }
            }

            Component.onCompleted: {
                if (typeof Config !== "undefined" && Config.dataReady) {
                    barWindow.configRevision++;
                }
            }

            property string barStyle: {
                let dummy = configRevision;
                if (typeof Config === "undefined" || !Config.rawSettings || !Config.rawSettings.bar) return "modular";
                let s = Config.rawSettings.bar.style;
                if (typeof s === "string") return s;
                if (s && typeof s === "object") {
                    if (s.fill || s.mode === "fill") return "fill";
                    if (s.solid || s.mode === "solid") return "solid";
                }
                return "modular";
            }
            property bool isFill: barStyle === "fill"
            property bool isSolid: barStyle === "solid" || barStyle === "fill"
            property bool distinctPills: {
                let dummy = configRevision;
                return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.distinctPills !== undefined) ? Config.rawSettings.bar.distinctPills : false;
            }

            property bool barConfigReady: {
                let dummy = configRevision;
                if (typeof Config === "undefined" || !Config.dataReady || !Config.rawSettings) return false;
                return Config.rawSettings.bar !== undefined && Config.rawSettings.bar.autohide !== undefined;
            }

            property bool autohide: {
                let dummy = configRevision;
                return barConfigReady ? Config.rawSettings.bar.autohide : false;
            }
            property int autohideTimeout: {
                let dummy = configRevision;
                return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.autohideTimeout !== undefined) ? Config.rawSettings.bar.autohideTimeout : 1000;
            }
            property real barOpacity: {
                let dummy = configRevision;
                return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.opacity !== undefined) ? (Config.rawSettings.bar.opacity / 100.0) : 1.0;
            }

            HoverHandler {
                id: barHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            }

            Timer {
                id: hideTimer
                interval: barWindow.autohideTimeout
            }

            function checkHideTimer() {
                if (!barHover.hovered && barWindow.autohide) {
                    hideTimer.restart();
                } else {
                    hideTimer.stop();
                }
            }

            Connections {
                target: barHover
                function onHoveredChanged() { barWindow.checkHideTimer(); }
            }

            property bool isRevealed: {
                if (isRedacting) return false;
                if (!autohide) return true;
                if (barHover.hovered) return true;
                if (hideTimer.running) return true;
                return false;
            }

            Timer {
                interval: 50
                running: true
                onTriggered: barWindow.startupFilesReady = true
            }

            IpcHandler {
                target: "topbar"
                function setRedactMode(active: string): void {
                    barWindow.isRedacting = (active === "true" || active === "1");
                }
                function forceReload() {
                    Quickshell.reload(true)
                }
                function queueReload() {
                    if (!barWindow.isNotifOpen && !barWindow.isSysOpen) {
                        Quickshell.reload(true)
                    } else {
                        barWindow.pendingReload = true
                    }
                }
                function toggleUpdate() {
                    let target = null;
                    if (barWindow.isVertical) target = verticalWrapper.getWidget("left");
                    else target = contentWrapper.getWidget("left");
                    if (target && typeof target.toggleUpdate === "function") {
                        target.toggleUpdate();
                    }
                }
                function getWidgetGeometry(widgetName: string): void {
                    let target = null;
                    if (barWindow.isVertical) target = verticalWrapper.getWidget(widgetName);
                    else target = contentWrapper.getWidget(widgetName);

                    if (target && target.width > 0) {
                        let pos = target.mapToItem(null, 0, 0);

                        let absoluteX = pos.x + barWindow.margins.left;
                        let absoluteY = pos.y + barWindow.margins.top;

                        let geo = {
                            startX: Math.round(absoluteX),
                            startY: Math.round(absoluteY),
                            endX: Math.round(absoluteX + target.width),
                            endY: Math.round(absoluteY + target.height)
                        };
                        Quickshell.execDetached(["bash", "-c", "echo '" + JSON.stringify(geo) + "' > " + Caching.runDir + "/tutorial_target.json"]);
                    }
                }
            }

            required property var modelData
            screen: modelData

            property string barPosition: {
                let dummy = configRevision;
                return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.position !== undefined) ? Config.rawSettings.bar.position : "top";
            }
            property bool positionChanging: false

            property real barWidthPercent: {
                let dummy = configRevision;
                return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.width !== undefined) ? Config.rawSettings.bar.width : 100;
            }
            property real edgePadding: (autohide && !isFill) ? s(4) : 0
            property real effectiveBarWidth: Math.round(isVertical ? barWindow.width : (isFill ? barWindow.width : ((barWindow.width - (autohide ? edgePadding * 2 : 0)) * (barWidthPercent / 100.0))))
            property real horizontalOffset: Math.round(isVertical ? 0 : (isFill ? 0 : ((barWindow.width - effectiveBarWidth) / 2)))

            property real effectiveBarHeight: Math.round(!isVertical ? barWindow.height : (isFill ? barWindow.height : ((barWindow.height - (autohide ? edgePadding * 2 : 0)) * (barWidthPercent / 100.0))))
            property real verticalOffset: Math.round(!isVertical ? 0 : (isFill ? 0 : ((barWindow.height - effectiveBarHeight) / 2)))

            property real currentBarMinX: contentWrapper ? contentWrapper.dynamicMinX : horizontalOffset
            property real currentBarMaxX: contentWrapper ? contentWrapper.dynamicMaxX : (horizontalOffset + effectiveBarWidth)

            property real currentBarMinY: verticalWrapper ? verticalWrapper.dynamicMinY : verticalOffset
            property real currentBarMaxY: verticalWrapper ? verticalWrapper.dynamicMaxY : (verticalOffset + effectiveBarHeight)

            Timer {
                id: positionChangeTimer
                interval: 200
                onTriggered: barWindow.positionChanging = false
            }

            onBarPositionChanged: {
                barWindow.positionChanging = true;
                positionChangeTimer.restart();
            }

            property bool isVertical: barPosition === "left" || barPosition === "right"

            property real baseScale: Scaler.baseScale

            function s(val) {
                return Math.round(Scaler.s(val));
            }

            property int barHeight: s(40)
            property real cornerRadius: s(12)

            property real baseOffsetY: {
                if (barPosition === "bottom") {
                    return isFill ? (barWindow.height - barWindow.barHeight) : (barWindow.height - barWindow.barHeight - edgePadding);
                } else {
                    return isFill ? 0 : edgePadding;
                }
            }

            anchors {
                top: barPosition === "top" || barWindow.isVertical
                bottom: barPosition === "bottom" || barWindow.isVertical
                left: barPosition === "left" || !barWindow.isVertical
                right: barPosition === "right" || !barWindow.isVertical
            }

            implicitHeight: barWindow.isVertical ? 0 : (barHeight + (isFill ? cornerRadius : edgePadding))
            implicitWidth: barWindow.isVertical ? (barHeight + (isFill ? cornerRadius : edgePadding)) : 0

            margins {
                top: isFill ? 0 : (barPosition === "bottom" ? 0 : (autohide ? 0 : s(4)))
                bottom: isFill ? 0 : (barPosition === "top" ? 0 : (autohide ? 0 : s(4)))
                left: isFill ? 0 : (barPosition === "right" ? 0 : (autohide ? 0 : s(4)))
                right: isFill ? 0 : (barPosition === "left" ? 0 : (autohide ? 0 : s(4)))
            }

            exclusiveZone: (!barConfigReady || autohide || isRedacting) ? 0 : barHeight
            color: "transparent"

            property real activeMaskHeight: isRedacting ? 0 : ((autohide && !isRevealed) ? s(4) : (isVertical ? (isFill ? barWindow.height : (effectiveBarHeight + edgePadding * 2)) : (isFill ? (barHeight + cornerRadius) : (barHeight + edgePadding))))
            property real activeMaskWidth: isRedacting ? 0 : ((autohide && !isRevealed) ? s(4) : (isVertical ? (isFill ? (barHeight + cornerRadius) : (barHeight + edgePadding)) : (isFill ? barWindow.width : (effectiveBarWidth + edgePadding * 2))))

            mask: Region {
                Region {
                    x: barWindow.isVertical ? (barWindow.barPosition === "right" ? (barWindow.width - barWindow.activeMaskWidth) : 0) : (isFill ? 0 : barWindow.currentBarMinX)
                    y: barWindow.isVertical ? (isFill ? 0 : barWindow.currentBarMinY) : (barWindow.barPosition === "bottom" ? barWindow.baseOffsetY : 0)
                    width: barWindow.isVertical ? barWindow.activeMaskWidth : (isFill ? barWindow.width : (barWindow.currentBarMaxX - barWindow.currentBarMinX))
                    height: barWindow.isVertical ? (isFill ? barWindow.height : (barWindow.currentBarMaxY - barWindow.currentBarMinY)) : (isFill ? barWindow.barHeight : barWindow.activeMaskHeight)
                }
                Region {
                    x: barWindow.isVertical ? (barWindow.barPosition === "right" ? (barWindow.width - barWindow.barHeight - barWindow.cornerRadius) : barWindow.barHeight) : 0
                    y: barWindow.isVertical ? 0 : (barWindow.barPosition === "bottom" ? (barWindow.baseOffsetY - barWindow.cornerRadius) : (barWindow.baseOffsetY + barWindow.barHeight))
                    width: (!barWindow.isVertical && barWindow.isFill) ? barWindow.cornerRadius : (barWindow.isVertical && barWindow.isFill ? barWindow.cornerRadius : 0)
                    height: (!barWindow.isVertical && barWindow.isFill) ? barWindow.cornerRadius : (barWindow.isVertical && barWindow.isFill ? barWindow.cornerRadius : 0)
                }
                Region {
                    x: barWindow.isVertical ? (barWindow.barPosition === "right" ? (barWindow.width - barWindow.barHeight - barWindow.cornerRadius) : barWindow.barHeight) : (barWindow.width - barWindow.cornerRadius)
                    y: barWindow.isVertical ? (barWindow.height - barWindow.cornerRadius) : (barWindow.barPosition === "bottom" ? (barWindow.baseOffsetY - barWindow.cornerRadius) : (barWindow.baseOffsetY + barWindow.barHeight))
                    width: (!barWindow.isVertical && barWindow.isFill) ? barWindow.cornerRadius : (barWindow.isVertical && barWindow.isFill ? barWindow.cornerRadius : 0)
                    height: (!barWindow.isVertical && barWindow.isFill) ? barWindow.cornerRadius : (barWindow.isVertical && barWindow.isFill ? barWindow.cornerRadius : 0)
                }
            }

            property string activeWidget: ""
            property bool isNotifOpen: activeWidget === "notifications"
            property bool isSysOpen: activeWidget === "system"

            onActiveWidgetChanged: {
                if (!barWindow.isNotifOpen && !barWindow.isSysOpen && barWindow.pendingReload) {
                    barWindow.pendingReload = false;
                    Quickshell.reload(true);
                }
            }

            FileView {
                id: widgetWatcher
                path: (barWindow.startupFilesReady && Caching.runDir) ? (Caching.runDir + "/current_widget") : ""
                watchChanges: true
                onFileChanged: reload()
                onLoaded: {
                    let txt = text().trim();
                    let widget = "";
                    let targetScreen = "";

                    try {
                        let parsed = JSON.parse(txt);
                        if (parsed && typeof parsed === "object") {
                            widget = parsed.widget || "";
                            targetScreen = parsed.screen || "";
                        } else if (typeof parsed === "string") {
                            widget = parsed;
                        }
                    } catch (e) {
                        widget = txt;
                    }

                    let myScreenName = (barWindow.screen && barWindow.screen.name) ? barWindow.screen.name : "";
                    let effectiveWidget = "";
                    if (widget === "notifications" || widget === "system") {
                        if (!targetScreen || targetScreen === myScreenName) {
                            effectiveWidget = widget;
                        }
                    }

                    if (barWindow.activeWidget !== effectiveWidget) {
                        barWindow.activeWidget = effectiveWidget;
                    }
                }
            }

            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }

            property bool startupCascadeFinished: false
            Timer { interval: 1050; running: true; onTriggered: barWindow.startupCascadeFinished = true }

            property bool fastPollerLoaded: false
            property bool isDataReady: fastPollerLoaded
            Timer { interval: 400; running: true; onTriggered: barWindow.isDataReady = true }

            SideBar {
                id: verticalWrapper
                barWindow: barWindow
                property real hideOffsetX: {
                    if (!barWindow || barWindow.isRevealed) return 0;
                    let offset = barWindow.barHeight + barWindow.edgePadding + barWindow.s(10);
                    return barWindow.barPosition === "right" ? offset : -offset;
                }
                transform: Translate {
                    x: verticalWrapper.hideOffsetX
                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                }
            }

            TopBar {
                id: contentWrapper
                barWindow: barWindow
            }
        }
    }
}
