import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../reusables"
import "../"
import "sidemodules"

Item {
    id: contentWrapper

    property var barWindow

    property string barStyle: {
        if (barWindow && barWindow.barStyle !== undefined) return barWindow.barStyle;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.style) {
            let s = Config.rawSettings.bar.style;
            if (typeof s === "string") return s;
            if (typeof s === "object") {
                if (s.fill || s.mode === "fill") return "fill";
                if (s.solid || s.mode === "solid") return "solid";
            }
        }
        return "modular";
    }
    property bool isFill: barStyle === "fill"
    property bool isSolid: barStyle === "solid" || barStyle === "fill"
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property real cornerRadius: barWindow ? barWindow.cornerRadius : 12

    property bool suppressAnimation: false
    property bool layoutAnimationsEnabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging && !contentWrapper.suppressAnimation

    Timer {
        id: snapTimer
        interval: 200
        onTriggered: contentWrapper.suppressAnimation = false
    }

    Connections {
        target: contentWrapper.barWindow || null
        function onBarPositionChanged() {
            contentWrapper.suppressAnimation = true;
            snapTimer.restart();
        }
        function onPositionChangingChanged() {
            if (contentWrapper.barWindow && contentWrapper.barWindow.positionChanging) {
                contentWrapper.suppressAnimation = true;
            } else {
                snapTimer.restart();
            }
        }
        function onBaseOffsetYChanged() {
            contentWrapper.suppressAnimation = true;
            snapTimer.restart();
        }
        function onIsVerticalChanged() {
            contentWrapper.suppressAnimation = true;
            snapTimer.restart();
        }
    }

    property var defaultModuleSettings: {
        "left": ["left", "workspaces", "focus"],
        "center": ["timedate", "info", "weather", "media", "vis"],
        "right": ["tray", "sysmon", "kb", "wifi", "bt", "vol", "bat"]
    }

    function parseModuleSettings(ms) {
        if (!ms) return defaultModuleSettings;

        function migrate(arr) {
            if (!arr) return [];
            let res = [];
            for (let i = 0; i < arr.length; i++) {
                if (Array.isArray(arr[i])) {
                    let group = [];
                    for (let j = 0; j < arr[i].length; j++) {
                        if (arr[i][j] === "system") group.push("sysmon", "kb", "wifi", "bt", "vol", "bat");
                        else group.push(arr[i][j]);
                    }
                    if (group.length === 1) res.push(group[0]);
                    else if (group.length > 1) res.push(group);
                } else {
                    if (arr[i] === "system") res.push(["sysmon", "kb", "wifi", "bt", "vol", "bat"]);
                    else res.push(arr[i]);
                }
            }
            return res;
        }

        let l = migrate(ms.left);
        let c = migrate(ms.center);
        let r = migrate(ms.right);

        if (ms.active && !l.length && !c.length && !r.length) {
            let order = migrate(ms.active);
            let cIdx = -1;
            for (let i = 0; i < order.length; i++) {
                if (order[i] === "center" || (Array.isArray(order[i]) && order[i].indexOf("center") !== -1)) { cIdx = i; break; }
            }
            l = []; c = []; r = [];
            for (let i = 0; i < order.length; i++) {
                if (order[i] === "center" || (Array.isArray(order[i]) && order[i].indexOf("center") !== -1)) continue;
                if (cIdx === -1 || i < cIdx) l.push(order[i]);
                else r.push(order[i]);
            }
            c = ["timedate", "info", "weather"];
        }

        function filterCenter(arr) {
            let out = [];
            for (let i = 0; i < arr.length; i++) {
                if (Array.isArray(arr[i])) {
                    let filtered = arr[i].filter(id => id !== "center" && id !== "centerbox");
                    if (filtered.length === 1) out.push(filtered[0]);
                    else if (filtered.length > 1) out.push(filtered);
                } else if (arr[i] !== "center" && arr[i] !== "centerbox") {
                    out.push(arr[i]);
                }
            }
            return out;
        }

        return {
            "left": filterCenter(l),
            "center": filterCenter(c),
            "right": filterCenter(r)
        };
    }

    property var moduleSettings: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.modules) ? parseModuleSettings(Config.rawSettings.bar.modules) : defaultModuleSettings

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            let ms = Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.modules ? Config.rawSettings.bar.modules : null;
            contentWrapper.moduleSettings = parseModuleSettings(ms);
        }
    }

    property string layoutState: "default"

    property var topArr: contentWrapper.moduleSettings["left"] || []
    property var centerArr: contentWrapper.moduleSettings["center"] || []
    property var bottomArr: contentWrapper.moduleSettings["right"] || []

    property var flatTopArr: { let r=[]; for(let i=0; i<topArr.length; i++){ if(Array.isArray(topArr[i])) r.push(...topArr[i]); else r.push(topArr[i]); } return r; }
    property var flatCenterArr: { let r=[]; for(let i=0; i<centerArr.length; i++){ if(Array.isArray(centerArr[i])) r.push(...centerArr[i]); else r.push(centerArr[i]); } return r; }
    property var flatBottomArr: { let r=[]; for(let i=0; i<bottomArr.length; i++){ if(Array.isArray(bottomArr[i])) r.push(...bottomArr[i]); else r.push(bottomArr[i]); } return r; }

    property var groupDefs: {
        let defs = [];
        let all = [contentWrapper.topArr, contentWrapper.centerArr, contentWrapper.bottomArr];
        for (let i = 0; i < all.length; i++) {
            for (let j = 0; j < all[i].length; j++) {
                if (Array.isArray(all[i][j])) defs.push(all[i][j]);
            }
        }
        return defs;
    }

    property bool trayInTop: flatTopArr.indexOf("tray") !== -1
    property bool trayInCenter: flatCenterArr.indexOf("tray") !== -1
    property bool trayInBottom: flatBottomArr.indexOf("tray") !== -1

    property bool trayAlignBottom: {
        if (trayInTop) return false;
        if (trayInBottom) return true;
        return true;
    }

    function isModuleActive(moduleId) {
        if (moduleId === "timedate") return flatTopArr.indexOf("timedate") !== -1 || flatCenterArr.indexOf("timedate") !== -1 || flatBottomArr.indexOf("timedate") !== -1 || flatTopArr.indexOf("time") !== -1 || flatCenterArr.indexOf("time") !== -1 || flatBottomArr.indexOf("time") !== -1 || flatTopArr.indexOf("clock") !== -1 || flatCenterArr.indexOf("clock") !== -1 || flatBottomArr.indexOf("clock") !== -1;
        if (moduleId === "info") return flatTopArr.indexOf("info") !== -1 || flatCenterArr.indexOf("info") !== -1 || flatBottomArr.indexOf("info") !== -1 || flatTopArr.indexOf("indicator") !== -1 || flatCenterArr.indexOf("indicator") !== -1 || flatBottomArr.indexOf("indicator") !== -1 || flatTopArr.indexOf("indicators") !== -1 || flatCenterArr.indexOf("indicators") !== -1 || flatBottomArr.indexOf("indicators") !== -1 || flatTopArr.indexOf("record") !== -1 || flatCenterArr.indexOf("record") !== -1 || flatBottomArr.indexOf("record") !== -1;
        return flatTopArr.indexOf(moduleId) !== -1 || flatCenterArr.indexOf(moduleId) !== -1 || flatBottomArr.indexOf(moduleId) !== -1;
    }

    function isModuleGrouped(id) {
        let allArrs = [topArr, centerArr, bottomArr];
        for (let a = 0; a < allArrs.length; a++) {
            for (let i = 0; i < allArrs[a].length; i++) {
                if (Array.isArray(allArrs[a][i])) {
                    if (allArrs[a][i].indexOf(id) !== -1) return true;
                    if (id === "timedate" && (allArrs[a][i].indexOf("time") !== -1 || allArrs[a][i].indexOf("clock") !== -1)) return true;
                    if (id === "info" && (allArrs[a][i].indexOf("indicator") !== -1 || allArrs[a][i].indexOf("indicators") !== -1 || allArrs[a][i].indexOf("record") !== -1)) return true;
                }
            }
        }
        return false;
    }

    property real hLeft: isModuleActive("left") ? (leftWidget.targetHeight !== undefined ? leftWidget.targetHeight : leftWidget.height) : 0
    property real hWorkspaces: isModuleActive("workspaces") ? (workspacesWidget.targetHeight !== undefined ? workspacesWidget.targetHeight : workspacesWidget.height) : 0
    property real hFocus: isModuleActive("focus") ? (focusWidget.targetHeight !== undefined ? focusWidget.targetHeight : focusWidget.height) : 0
    property real hMedia: isModuleActive("media") ? (mediaWidget.targetHeight !== undefined ? mediaWidget.targetHeight : mediaWidget.height) : 0
    property real hVis: isModuleActive("vis") ? (visWidget.targetHeight !== undefined ? visWidget.targetHeight : visWidget.height) : 0
    property real hTray: isModuleActive("tray") ? (trayWidget.targetHeight !== undefined ? trayWidget.targetHeight : trayWidget.height) : 0
    property real hSysmon: isModuleActive("sysmon") ? (sysMonWidget.targetHeight !== undefined ? sysMonWidget.targetHeight : sysMonWidget.height) : 0
    property real hKb: isModuleActive("kb") ? (kbWidget.targetHeight !== undefined ? kbWidget.targetHeight : kbWidget.height) : 0
    property real hWifi: isModuleActive("wifi") ? (wifiWidget.targetHeight !== undefined ? wifiWidget.targetHeight : wifiWidget.height) : 0
    property real hBt: isModuleActive("bt") ? (btWidget.targetHeight !== undefined ? btWidget.targetHeight : btWidget.height) : 0
    property real hVol: isModuleActive("vol") ? (volWidget.targetHeight !== undefined ? volWidget.targetHeight : volWidget.height) : 0
    property real hBat: isModuleActive("bat") ? (batWidget.targetHeight !== undefined ? batWidget.targetHeight : batWidget.height) : 0
    property real hTimedate: isModuleActive("timedate") ? (timeDateWidget.targetHeight !== undefined ? timeDateWidget.targetHeight : timeDateWidget.height) : 0
    property real hInfo: isModuleActive("info") ? (infoWidget.targetHeight !== undefined ? infoWidget.targetHeight : infoWidget.height) : 0
    property real hWeather: isModuleActive("weather") ? (weatherWidget.targetHeight !== undefined ? weatherWidget.targetHeight : weatherWidget.height) : 0

    function getH(moduleId) {
        if (moduleId === "left" || moduleId === "top") return hLeft;
        if (moduleId === "workspaces") return hWorkspaces;
        if (moduleId === "focus") return hFocus;
        if (moduleId === "media") return hMedia;
        if (moduleId === "vis") return hVis;
        if (moduleId === "tray") return hTray;
        if (moduleId === "sysmon") return hSysmon;
        if (moduleId === "kb") return hKb;
        if (moduleId === "wifi") return hWifi;
        if (moduleId === "bt") return hBt;
        if (moduleId === "vol") return hVol;
        if (moduleId === "bat") return hBat;
        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return hTimedate;
        if (moduleId === "info" || moduleId === "indicator" || moduleId === "indicators" || moduleId === "record") return hInfo;
        if (moduleId === "weather") return hWeather;
        return 0;
    }

    property real gap: barWindow ? barWindow.s(2) : 2
    property real groupGap: barWindow ? -barWindow.s(4) : -4
    property real gap8: barWindow ? barWindow.s(10) : 10

    function calcTargetHeight(arr) {
        let total = 0;
        let groupCount = 0;
        for (let i = 0; i < arr.length; i++) {
            if (Array.isArray(arr[i])) {
                let gh = 0;
                let gItems = 0;
                for (let j = 0; j < arr[i].length; j++) {
                    let h = getH(arr[i][j]);
                    if (h > 0) {
                        if (gItems > 0) gh += groupGap;
                        gh += h;
                        gItems++;
                    }
                }
                if (gItems > 0) {
                    total += gh;
                    groupCount++;
                }
            } else {
                let h = getH(arr[i]);
                if (h > 0) { total += h; groupCount++; }
            }
        }
        return total + (groupCount > 1 ? gap * (groupCount - 1) : 0);
    }

    property real tHeightTarget: calcTargetHeight(topArr)
    property real cHeightTarget: calcTargetHeight(centerArr)
    property real bHeightTarget: calcTargetHeight(bottomArr)

    property real tcGap: (tHeightTarget > 0 && cHeightTarget > 0) ? gap8 : 0
    property real cbGap: (cHeightTarget > 0 && bHeightTarget > 0) ? gap8 : 0

    property real distinctEdgePadding: (isSolid && distinctPills) ? (barWindow ? barWindow.s(4) : 4) : 4
    property real fillInset: distinctEdgePadding

    property real baseMinTop: isFill ? fillInset : (barWindow ? (barWindow.verticalOffset + barWindow.s(1) + distinctEdgePadding) : distinctEdgePadding)
    property real baseMaxBottom: isFill ? (contentWrapper.height - fillInset) : (barWindow ? (contentWrapper.height - barWindow.verticalOffset - barWindow.s(1) - distinctEdgePadding) : (contentWrapper.height - distinctEdgePadding))

    property real screenMinTop: isFill ? fillInset : (barWindow ? (barWindow.s(1) + distinctEdgePadding) : distinctEdgePadding)
    property real screenMaxBottom: isFill ? (contentWrapper.height - fillInset) : (barWindow ? (contentWrapper.height - barWindow.s(1) - distinctEdgePadding) : (contentWrapper.height - distinctEdgePadding))

    property real rawCNaturalY: (contentWrapper.height - cHeightTarget) / 2

    property real absMinC: (tHeightTarget > 0) ? (screenMinTop + tHeightTarget + tcGap) : screenMinTop
    property real absMaxC: (bHeightTarget > 0) ? (screenMaxBottom - bHeightTarget - cbGap - cHeightTarget) : (screenMaxBottom - cHeightTarget)

    property real cResolvedY: {
        if (absMinC <= absMaxC) {
            return Math.max(absMinC, Math.min(absMaxC, rawCNaturalY));
        }
        return Math.max(screenMinTop, Math.min(screenMaxBottom - cHeightTarget, rawCNaturalY));
    }

    property real cFinalY: cResolvedY

    property real tFinalY: {
        if (tHeightTarget <= 0) return baseMinTop;
        let pushedY = Math.min(baseMinTop, cFinalY - tcGap - tHeightTarget);
        return Math.max(screenMinTop, pushedY);
    }

    property real bFinalY: {
        if (bHeightTarget <= 0) return baseMaxBottom;
        let pushedY = Math.max(baseMaxBottom - bHeightTarget, cFinalY + cHeightTarget + cbGap);
        return Math.min(screenMaxBottom - bHeightTarget, pushedY);
    }
    property real bFinalClampedY: Math.max(0, Math.min(contentWrapper.height - bHeightTarget, bFinalY))

    property real dynamicMinY: {
        if (isFill) return 0;
        let m = contentWrapper.height;
        let hasModules = (tHeightTarget > 0 || cHeightTarget > 0 || bHeightTarget > 0);
        if (tHeightTarget > 0) m = Math.min(m, tFinalY - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (cHeightTarget > 0) m = Math.min(m, cFinalY - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (bHeightTarget > 0) m = Math.min(m, bFinalClampedY - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (layoutState !== "default") {
            return hasModules ? Math.max(0, m) : contentWrapper.height / 2;
        }
        return Math.max(0, Math.min(m, barWindow ? barWindow.verticalOffset : 0));
    }

    property real dynamicMaxY: {
        if (isFill) return contentWrapper.height;
        let m = 0;
        let hasModules = (tHeightTarget > 0 || cHeightTarget > 0 || bHeightTarget > 0);
        if (tHeightTarget > 0) m = Math.max(m, tFinalY + tHeightTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (cHeightTarget > 0) m = Math.max(m, cFinalY + cHeightTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (bHeightTarget > 0) m = Math.max(m, bFinalClampedY + bHeightTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (layoutState !== "default") {
            return hasModules ? Math.min(contentWrapper.height, m) : contentWrapper.height / 2;
        }
        return Math.min(contentWrapper.height, Math.max(m, barWindow ? (barWindow.verticalOffset + barWindow.effectiveBarHeight) : contentWrapper.height));
    }

    function matchId(item, id) {
        if (item === id) return true;
        if (id === "timedate" && (item === "time" || item === "clock")) return true;
        if (id === "info" && (item === "indicator" || item === "indicators" || item === "record")) return true;
        return false;
    }

    function getModuleY(id, state) {
        let arr = null, isTop = false, isCenter = false, isBottom = false;
        let checkFlat = (fArr) => {
            for (let i = 0; i < fArr.length; i++) {
                if (matchId(fArr[i], id)) return true;
            }
            return false;
        };

        if (checkFlat(flatTopArr)) { arr = topArr; isTop = true; }
        else if (checkFlat(flatCenterArr)) { arr = centerArr; isCenter = true; }
        else if (checkFlat(flatBottomArr)) { arr = bottomArr; isBottom = true; }

        if (!arr) return 0;

        let offset = 0;
        let baseY = isTop ? tFinalY : (isCenter ? cFinalY : bFinalClampedY);

        for (let i = 0; i < arr.length; i++) {
            let item = arr[i];
            if (Array.isArray(item)) {
                let groupHasId = false;
                for (let k = 0; k < item.length; k++) {
                    if (matchId(item[k], id)) { groupHasId = true; break; }
                }
                let gItems = 0;
                for (let j = 0; j < item.length; j++) {
                    let mId = item[j];
                    let h = getH(mId);
                    if (matchId(mId, id)) {
                        if (gItems > 0) offset += groupGap;
                        return baseY + offset;
                    }
                    if (h > 0) {
                        if (gItems > 0) offset += groupGap;
                        offset += h;
                        gItems++;
                    }
                }
                if (gItems > 0 && !groupHasId) {
                    offset += gap;
                }
            } else {
                if (matchId(item, id)) {
                    return baseY + offset;
                }
                let h = getH(item);
                if (h > 0) {
                    offset += h + gap;
                }
            }
        }
        return 0;
    }

    function getPositionedWidget(id) {
        if (id === "left" || id === "top") return leftWidget;
        if (id === "workspaces") return workspacesWidget;
        if (id === "focus") return focusWidget;
        if (id === "media") return mediaWidget;
        if (id === "vis") return visWidget;
        if (id === "tray") return trayWidget;
        if (id === "sysmon") return sysMonWidget;
        if (id === "kb") return kbWidget;
        if (id === "wifi") return wifiWidget;
        if (id === "bt") return btWidget;
        if (id === "vol") return volWidget;
        if (id === "bat") return batWidget;
        if (id === "timedate" || id === "time" || id === "clock") return timeDateWidget;
        if (id === "info" || id === "indicator" || id === "indicators" || id === "record") return infoWidget;
        if (id === "weather") return weatherWidget;
        return null;
    }

    function getWidget(widgetName) {
        if (widgetName === "left" || widgetName === "top") return leftWidget;
        else if (widgetName === "help" || widgetName === "guide") return leftWidget.helpButton;
        else if (widgetName === "workspaces") return workspacesWidget;
        else if (widgetName === "focus") return focusWidget;
        else if (widgetName === "media") return mediaWidget;
        else if (widgetName === "vis" || widgetName === "viswidget" || widgetName === "visualizer") return visWidget;
        else if (widgetName === "timedate" || widgetName === "time" || widgetName === "clock") return timeDateWidget;
        else if (widgetName === "info" || widgetName === "indicator" || widgetName === "indicators") return infoWidget;
        else if (widgetName === "weather") return weatherWidget;
        else if (widgetName === "tray") return trayWidget;
        else if (widgetName === "sysmon") return sysMonWidget;
        else if (widgetName === "kb") return kbWidget.kbPill ? kbWidget.kbPill : kbWidget;
        else if (widgetName === "wifi") return wifiWidget.wifiPill ? wifiWidget.wifiPill : wifiWidget;
        else if (widgetName === "bt") return btWidget.btPill ? btWidget.btPill : btWidget;
        else if (widgetName === "volume" || widgetName === "vol") return volWidget.volPill ? volWidget.volPill : volWidget;
        else if (widgetName === "battery" || widgetName === "bat") return batWidget.batPill ? batWidget.batPill : batWidget;
        else if (widgetName === "system" || widgetName === "pills") return systemWidget;
        else if (widgetName === "record") return infoWidget ? infoWidget.recCol : null;
        return null;
    }

    function getModuleX(widget) {
        if (!barWindow) return 0;
        let bThick = barWindow.barHeight;
        let isRight = barWindow.barPosition === "right";
        let base = (barWindow.baseOffsetX !== undefined) ? barWindow.baseOffsetX : (isRight ? (contentWrapper.width - bThick) : 0);
        let w = widget ? widget.width : 0;
        if (w > 0 && w < bThick) {
            return base + Math.round((bThick - w) / 2);
        }
        if (w > bThick && isRight) {
            return contentWrapper.width - w;
        }
        return base;
    }

    anchors.fill: parent
    visible: barWindow ? (barWindow.isVertical && !barWindow.positionChanging) : true
    opacity: (visible && (!barWindow || !barWindow.positionChanging) && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0

    Behavior on opacity {
        enabled: barWindow ? (!barWindow.positionChanging && barWindow.startupCascadeFinished) : true
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: solidBackground
        x: barWindow && barWindow.barPosition === "right" ? (parent.width - width) : 0
        y: isFill ? 0 : contentWrapper.dynamicMinY
        width: barWindow ? barWindow.barHeight : 40
        height: isFill ? contentWrapper.height : (contentWrapper.dynamicMaxY - contentWrapper.dynamicMinY)
        color: Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        radius: isFill ? 0 : ThemeBackend.borderRadius
        border.width: (isSolid || isFill) ? 0 : 1
        border.color: (isSolid || isFill) ? "transparent" : Qt.alpha(ThemeBackend.surface0, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        visible: (isSolid || isFill) && (barWindow ? !barWindow.positionChanging : true)
        opacity: visible ? 1.0 : 0.0

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        Behavior on height {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            enabled: barWindow && !barWindow.positionChanging && barWindow.startupCascadeFinished && !contentWrapper.suppressAnimation
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Canvas {
        id: topOuterCorner
        x: barWindow && barWindow.barPosition === "right" ? (parent.width - (barWindow ? barWindow.barHeight : 40) - width) : (barWindow ? barWindow.barHeight : 40)
        y: 0
        width: contentWrapper.cornerRadius
        height: contentWrapper.cornerRadius
        visible: contentWrapper.isFill && (barWindow ? !barWindow.positionChanging : true)
        opacity: (visible && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0
        z: 0

        Connections {
            target: ThemeBackend
            function onBaseChanged() { topOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper
            function onIsFillChanged() { topOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper.barWindow || null
            function onBarPositionChanged() { topOuterCorner.requestPaint(); }
            function onBarOpacityChanged() { topOuterCorner.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0);
            ctx.beginPath();
            if (barWindow && barWindow.barPosition === "right") {
                ctx.moveTo(width, 0);
                ctx.lineTo(0, 0);
                ctx.arcTo(width, 0, width, height, width);
                ctx.lineTo(width, height);
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.arcTo(0, 0, 0, height, width);
                ctx.lineTo(0, height);
            }
            ctx.closePath();
            ctx.fill();
        }

        Behavior on opacity {
            enabled: barWindow && !barWindow.positionChanging && barWindow.startupCascadeFinished && !contentWrapper.suppressAnimation
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Canvas {
        id: bottomOuterCorner
        x: barWindow && barWindow.barPosition === "right" ? (parent.width - (barWindow ? barWindow.barHeight : 40) - width) : (barWindow ? barWindow.barHeight : 40)
        y: parent.height - height
        width: contentWrapper.cornerRadius
        height: contentWrapper.cornerRadius
        visible: contentWrapper.isFill && (barWindow ? !barWindow.positionChanging : true)
        opacity: (visible && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0
        z: 0

        Connections {
            target: ThemeBackend
            function onBaseChanged() { bottomOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper
            function onIsFillChanged() { bottomOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper.barWindow || null
            function onBarPositionChanged() { bottomOuterCorner.requestPaint(); }
            function onBarOpacityChanged() { bottomOuterCorner.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0);
            ctx.beginPath();
            if (barWindow && barWindow.barPosition === "right") {
                ctx.moveTo(width, height);
                ctx.lineTo(0, height);
                ctx.arcTo(width, height, width, 0, width);
                ctx.lineTo(width, 0);
            } else {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.arcTo(0, height, 0, 0, width);
                ctx.lineTo(0, 0);
            }
            ctx.closePath();
            ctx.fill();
        }

        Behavior on opacity {
            enabled: barWindow && !barWindow.positionChanging && barWindow.startupCascadeFinished && !contentWrapper.suppressAnimation
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Repeater {
        id: groupBgRepeater
        model: contentWrapper.groupDefs
        delegate: Rectangle {
            id: groupBgRect
            z: 0
            property var groupIds: modelData

            function getGroupMetrics() {
                let firstY = -1;
                let lastY = -1;
                let lastH = 0;
                let groupW = barWindow ? ((contentWrapper.isSolid && contentWrapper.distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight) : ((contentWrapper.isSolid && contentWrapper.distinctPills) ? 24 : 30);
                for (let i = 0; i < groupIds.length; i++) {
                    let id = groupIds[i];
                    let widget = contentWrapper.getPositionedWidget(id);
                    if (!widget || !widget.visible) continue;

                    let targetH = (widget.targetHeight !== undefined) ? widget.targetHeight : widget.height;
                    if (targetH <= 0) continue;

                    let my = (widget.targetY !== undefined) ? widget.targetY : widget.y;
                    let mh = targetH;

                    if (firstY === -1) firstY = my;
                    lastY = my;
                    lastH = mh;

                    if (id === "timedate" || id === "info" || id === "weather" || id === "media") continue;

                    if (widget.width > groupW) {
                        groupW = widget.width;
                    }
                }
                if (firstY === -1) return { y: 0, h: 0, w: groupW, v: false };
                return { y: firstY, h: (lastY + lastH - firstY), w: groupW, v: true };
            }

            property var metrics: getGroupMetrics()

            x: {
                let bThick = barWindow ? barWindow.barHeight : 40;
                let base = (barWindow && barWindow.baseOffsetX !== undefined) ? barWindow.baseOffsetX : (barWindow && barWindow.barPosition === "right" ? (parent.width - bThick) : 0);
                return base + Math.round((bThick - width) / 2);
            }
            y: metrics.y
            width: metrics.w
            height: metrics.h
            visible: metrics.v && (barWindow ? !barWindow.positionChanging : true) && height > 0 && (!contentWrapper.isSolid || contentWrapper.distinctPills)
            opacity: visible ? 1.0 : 0.0

            color: (contentWrapper.isSolid && contentWrapper.distinctPills)
                ? Qt.alpha(Qt.darker(ThemeBackend.surface0, 1.15), (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
                : Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
            radius: ThemeBackend.borderRadius
            border.width: 0

            Behavior on y {
                enabled: contentWrapper.layoutAnimationsEnabled
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            Behavior on height {
                enabled: contentWrapper.layoutAnimationsEnabled
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            Behavior on width {
                enabled: contentWrapper.layoutAnimationsEnabled
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            Behavior on opacity {
                enabled: barWindow && !barWindow.positionChanging && barWindow.startupCascadeFinished && !contentWrapper.suppressAnimation
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
        }
    }

    SideTopWidget {
        id: leftWidget
        z: 1
        x: contentWrapper.getModuleX(leftWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("left")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("left")
        isGrouped: contentWrapper.isModuleGrouped("left")
        targetY: contentWrapper.getModuleY("left", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideWorkspacesWidget {
        id: workspacesWidget
        z: 1
        x: contentWrapper.getModuleX(workspacesWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("workspaces")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("workspaces")
        isGrouped: contentWrapper.isModuleGrouped("workspaces")
        targetY: contentWrapper.getModuleY("workspaces", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideFocusWidget {
        id: focusWidget
        z: 1
        x: contentWrapper.getModuleX(focusWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("focus")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("focus")
        isGrouped: contentWrapper.isModuleGrouped("focus")
        targetY: contentWrapper.getModuleY("focus", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideMediaWidget {
        id: mediaWidget
        z: 1
        x: contentWrapper.getModuleX(mediaWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("media")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("media")
        isGrouped: contentWrapper.isModuleGrouped("media")
        targetY: contentWrapper.getModuleY("media", contentWrapper.layoutState)
        layoutAnimationsEnabled: contentWrapper.layoutAnimationsEnabled

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideVisWidget {
        id: visWidget
        z: 1
        x: contentWrapper.getModuleX(visWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("vis")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("vis")
        isGrouped: contentWrapper.isModuleGrouped("vis")
        targetY: contentWrapper.getModuleY("vis", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideTrayWidget {
        id: trayWidget
        z: 1
        x: contentWrapper.getModuleX(trayWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("tray")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("tray")
        isGrouped: contentWrapper.isModuleGrouped("tray")
        suppressAnimation: contentWrapper.suppressAnimation
        isBottomAligned: contentWrapper.trayAlignBottom
        targetY: contentWrapper.getModuleY("tray", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideSysMonWidget {
        id: sysMonWidget
        z: 1
        x: contentWrapper.getModuleX(sysMonWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("sysmon")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("sysmon")
        isGrouped: contentWrapper.isModuleGrouped("sysmon")
        targetY: contentWrapper.getModuleY("sysmon", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideKbWidget {
        id: kbWidget
        z: 1
        x: contentWrapper.getModuleX(kbWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("kb")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("kb")
        isGrouped: contentWrapper.isModuleGrouped("kb")
        targetY: contentWrapper.getModuleY("kb", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideWifiWidget {
        id: wifiWidget
        z: 1
        x: contentWrapper.getModuleX(wifiWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("wifi")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("wifi")
        isGrouped: contentWrapper.isModuleGrouped("wifi")
        targetY: contentWrapper.getModuleY("wifi", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideBtWidget {
        id: btWidget
        z: 1
        x: contentWrapper.getModuleX(btWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("bt")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("bt")
        isGrouped: contentWrapper.isModuleGrouped("bt")
        targetY: contentWrapper.getModuleY("bt", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideVolWidget {
        id: volWidget
        z: 1
        x: contentWrapper.getModuleX(volWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("vol")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("vol")
        isGrouped: contentWrapper.isModuleGrouped("vol")
        targetY: contentWrapper.getModuleY("vol", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideBatWidget {
        id: batWidget
        z: 1
        x: contentWrapper.getModuleX(batWidget)
        y: targetY
        visible: contentWrapper.isModuleActive("bat")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("bat")
        isGrouped: contentWrapper.isModuleGrouped("bat")
        targetY: contentWrapper.getModuleY("bat", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: systemWidget
        property alias kbPill: kbWidget.kbPill
        property alias wifiPill: wifiWidget.wifiPill
        property alias btPill: btWidget.btPill
        property alias volPill: volWidget.volPill
        property alias batPill: batWidget.batPill

        function getBounds() {
            let pills = [sysMonWidget, kbWidget, wifiWidget, btWidget, volWidget, batWidget];
            let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
            let found = false;
            for (let i = 0; i < pills.length; i++) {
                let p = pills[i];
                if (p && p.visible && p.height > 0) {
                    found = true;
                    minX = Math.min(minX, p.x);
                    minY = Math.min(minY, p.y);
                    maxX = Math.max(maxX, p.x + p.width);
                    maxY = Math.max(maxY, p.y + p.height);
                }
            }
            if (!found) return { x: 0, y: 0, width: 0, height: 0 };
            return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
        }

        x: getBounds().x
        y: getBounds().y
        width: getBounds().width
        height: getBounds().height
    }

    SideTimeDateWidget {
        id: timeDateWidget
        z: 10
        x: contentWrapper.getModuleX(timeDateWidget)
        visible: contentWrapper.isModuleActive("timedate")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("timedate")
        isGrouped: contentWrapper.isModuleGrouped("timedate")
        targetY: contentWrapper.getModuleY("timedate", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideInfoWidget {
        id: infoWidget
        z: 10
        x: contentWrapper.getModuleX(infoWidget)
        visible: contentWrapper.isModuleActive("info")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("info")
        isGrouped: contentWrapper.isModuleGrouped("info")
        targetY: contentWrapper.getModuleY("info", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SideWeatherWidget {
        id: weatherWidget
        z: 10
        x: contentWrapper.getModuleX(weatherWidget)
        visible: contentWrapper.isModuleActive("weather")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("weather")
        isGrouped: contentWrapper.isModuleGrouped("weather")
        targetY: contentWrapper.getModuleY("weather", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
}
