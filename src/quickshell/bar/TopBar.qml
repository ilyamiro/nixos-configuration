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
import "modules"

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
        "right": ["tray", "sysmon", "netspeed", "kb", "wifi", "bt", "vol", "bat"]
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
                        if (arr[i][j] === "system") group.push("sysmon", "netspeed", "kb", "wifi", "bt", "vol", "bat");
                        else group.push(arr[i][j]);
                    }
                    if (group.length === 1) res.push(group[0]);
                    else if (group.length > 1) res.push(group);
                } else {
                    if (arr[i] === "system") res.push(["sysmon", "netspeed", "kb", "wifi", "bt", "vol", "bat"]);
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

    property string layoutState: {
        if (isFill) return "default";
        if (barWindow && barWindow.isNotifOpen) return "settings";
        if (barWindow && barWindow.isSysOpen) return "sys";
        return "default";
    }

    property var leftArr: contentWrapper.moduleSettings["left"] || []
    property var centerArr: contentWrapper.moduleSettings["center"] || []
    property var rightArr: contentWrapper.moduleSettings["right"] || []

    property var flatLeftArr: { let r=[]; for(let i=0; i<leftArr.length; i++){ if(Array.isArray(leftArr[i])) r.push(...leftArr[i]); else r.push(leftArr[i]); } return r; }
    property var flatCenterArr: { let r=[]; for(let i=0; i<centerArr.length; i++){ if(Array.isArray(centerArr[i])) r.push(...centerArr[i]); else r.push(centerArr[i]); } return r; }
    property var flatRightArr: { let r=[]; for(let i=0; i<rightArr.length; i++){ if(Array.isArray(rightArr[i])) r.push(...rightArr[i]); else r.push(rightArr[i]); } return r; }

    property var groupDefs: {
        let defs = [];
        let all = [contentWrapper.leftArr, contentWrapper.centerArr, contentWrapper.rightArr];
        for (let i = 0; i < all.length; i++) {
            for (let j = 0; j < all[i].length; j++) {
                if (Array.isArray(all[i][j])) defs.push(all[i][j]);
            }
        }
        return defs;
    }

    property bool trayInLeft: flatLeftArr.indexOf("tray") !== -1
    property bool trayInCenter: flatCenterArr.indexOf("tray") !== -1
    property bool trayInRight: flatRightArr.indexOf("tray") !== -1

    property bool trayAlignRight: {
        if (trayInLeft) return false;
        if (trayInRight) return true;
        if (trayInCenter) return layoutState !== "sys";
        return true;
    }

    function isModuleActive(moduleId) {
        if (moduleId === "timedate") return flatLeftArr.indexOf("timedate") !== -1 || flatCenterArr.indexOf("timedate") !== -1 || flatRightArr.indexOf("timedate") !== -1 || flatLeftArr.indexOf("time") !== -1 || flatCenterArr.indexOf("time") !== -1 || flatRightArr.indexOf("time") !== -1 || flatLeftArr.indexOf("clock") !== -1 || flatCenterArr.indexOf("clock") !== -1 || flatRightArr.indexOf("clock") !== -1;
        if (moduleId === "info") return flatLeftArr.indexOf("info") !== -1 || flatCenterArr.indexOf("info") !== -1 || flatRightArr.indexOf("info") !== -1 || flatLeftArr.indexOf("indicator") !== -1 || flatCenterArr.indexOf("indicator") !== -1 || flatRightArr.indexOf("indicator") !== -1 || flatLeftArr.indexOf("indicators") !== -1 || flatCenterArr.indexOf("indicators") !== -1 || flatRightArr.indexOf("indicators") !== -1 || flatLeftArr.indexOf("record") !== -1 || flatCenterArr.indexOf("record") !== -1 || flatRightArr.indexOf("record") !== -1;
        return flatLeftArr.indexOf(moduleId) !== -1 || flatCenterArr.indexOf(moduleId) !== -1 || flatRightArr.indexOf(moduleId) !== -1;
    }

    function isModuleGrouped(id) {
        let allArrs = [leftArr, centerArr, rightArr];
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

    property real wLeft: isModuleActive("left") ? (leftWidget.targetWidth !== undefined ? leftWidget.targetWidth : leftWidget.width) : 0
    property real wWorkspaces: isModuleActive("workspaces") ? (workspacesWidget.targetWidth !== undefined ? workspacesWidget.targetWidth : workspacesWidget.width) : 0
    property real wFocus: isModuleActive("focus") ? (focusWidget.targetWidth !== undefined ? focusWidget.targetWidth : focusWidget.width) : 0
    property real wMedia: isModuleActive("media") ? (mediaWidget.targetWidth !== undefined ? mediaWidget.targetWidth : mediaWidget.width) : 0
    property real wVis: isModuleActive("vis") ? (visWidget.targetWidth !== undefined ? visWidget.targetWidth : visWidget.width) : 0
    property real wTray: isModuleActive("tray") ? (trayWidget.targetWidth !== undefined ? trayWidget.targetWidth : trayWidget.width) : 0
    property real wSysmon: isModuleActive("sysmon") ? (sysMonWidget.targetWidth !== undefined ? sysMonWidget.targetWidth : sysMonWidget.width) : 0
    property real wNetSpeed: isModuleActive("netspeed") ? (netSpeedWidget.targetWidth !== undefined ? netSpeedWidget.targetWidth : netSpeedWidget.width) : 0
    property real wKb: isModuleActive("kb") ? (kbWidget.targetWidth !== undefined ? kbWidget.targetWidth : kbWidget.width) : 0
    property real wWifi: isModuleActive("wifi") ? (wifiWidget.targetWidth !== undefined ? wifiWidget.targetWidth : wifiWidget.width) : 0
    property real wBt: isModuleActive("bt") ? (btWidget.targetWidth !== undefined ? btWidget.targetWidth : btWidget.width) : 0
    property real wVol: isModuleActive("vol") ? (volWidget.targetWidth !== undefined ? volWidget.targetWidth : volWidget.width) : 0
    property real wBat: isModuleActive("bat") ? (batWidget.targetWidth !== undefined ? batWidget.targetWidth : batWidget.width) : 0
    property real wTimedate: isModuleActive("timedate") ? (timeDateWidget.targetWidth !== undefined ? timeDateWidget.targetWidth : timeDateWidget.width) : 0
    property real wInfo: isModuleActive("info") ? (infoWidget.targetWidth !== undefined ? infoWidget.targetWidth : infoWidget.width) : 0
    property real wWeather: isModuleActive("weather") ? (weatherWidget.targetWidth !== undefined ? weatherWidget.targetWidth : weatherWidget.width) : 0

    function getW(moduleId) {
        if (moduleId === "left") return wLeft;
        if (moduleId === "workspaces") return wWorkspaces;
        if (moduleId === "focus") return wFocus;
        if (moduleId === "media") return wMedia;
        if (moduleId === "vis") return wVis;
        if (moduleId === "tray") return wTray;
        if (moduleId === "sysmon") return wSysmon;
        if (moduleId === "netspeed") return wNetSpeed;
        if (moduleId === "kb") return wKb;
        if (moduleId === "wifi") return wWifi;
        if (moduleId === "bt") return wBt;
        if (moduleId === "vol") return wVol;
        if (moduleId === "bat") return wBat;
        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;
        if (moduleId === "info" || moduleId === "indicator" || moduleId === "indicators" || moduleId === "record") return wInfo;
        if (moduleId === "weather") return wWeather;
        return 0;
    }

    property real gap: barWindow ? barWindow.s(2) : 2
    property real groupGap: barWindow ? -barWindow.s(4) : -4
    property real gap8: barWindow ? barWindow.s(10) : 10

    function calcTargetWidth(arr) {
        let total = 0;
        let groupCount = 0;
        for (let i = 0; i < arr.length; i++) {
            if (Array.isArray(arr[i])) {
                let gw = 0;
                let gItems = 0;
                for (let j = 0; j < arr[i].length; j++) {
                    let w = getW(arr[i][j]);
                    if (w > 0) {
                        if (gItems > 0) gw += groupGap;
                        gw += w;
                        gItems++;
                    }
                }
                if (gItems > 0) {
                    total += gw;
                    groupCount++;
                }
            } else {
                let w = getW(arr[i]);
                if (w > 0) { total += w; groupCount++; }
            }
        }
        return total + (groupCount > 1 ? gap * (groupCount - 1) : 0);
    }

    property real lWidthTarget: calcTargetWidth(leftArr)
    property real cWidthTarget: calcTargetWidth(centerArr)
    property real rWidthTarget: calcTargetWidth(rightArr)

    property real lcGap: (lWidthTarget > 0 && cWidthTarget > 0) ? gap8 : 0
    property real crGap: (cWidthTarget > 0 && rWidthTarget > 0) ? gap8 : 0

    property real distinctEdgePadding: (isSolid && distinctPills) ? (barWindow ? barWindow.s(4) : 4) : 4
    property real fillInset: distinctEdgePadding

    property real baseMinLeft: isFill ? fillInset : (barWindow ? (barWindow.horizontalOffset + barWindow.s(1) + distinctEdgePadding) : distinctEdgePadding)
    property real baseMaxRight: isFill ? (contentWrapper.width - fillInset) : (barWindow ? (contentWrapper.width - barWindow.horizontalOffset - barWindow.s(1) - distinctEdgePadding) : (contentWrapper.width - distinctEdgePadding))

    property real screenMinLeft: isFill ? fillInset : (barWindow ? (barWindow.s(1) + distinctEdgePadding) : distinctEdgePadding)
    property real screenMaxRight: isFill ? (contentWrapper.width - fillInset) : (barWindow ? (contentWrapper.width - barWindow.s(1) - distinctEdgePadding) : (contentWrapper.width - distinctEdgePadding))

    property real rawCNaturalX: {
        if (layoutState === "settings") return screenMaxRight - rWidthTarget - crGap - cWidthTarget;
        if (layoutState === "sys") return screenMinLeft + lWidthTarget + lcGap;
        return (contentWrapper.width - cWidthTarget) / 2;
    }

    property real absMinC: (lWidthTarget > 0) ? (screenMinLeft + lWidthTarget + lcGap) : screenMinLeft
    property real absMaxC: (rWidthTarget > 0) ? (screenMaxRight - rWidthTarget - crGap - cWidthTarget) : (screenMaxRight - cWidthTarget)

    property real cResolvedX: {
        if (absMinC <= absMaxC) {
            return Math.max(absMinC, Math.min(absMaxC, rawCNaturalX));
        }
        return Math.max(screenMinLeft, Math.min(screenMaxRight - cWidthTarget, rawCNaturalX));
    }

    property real cFinalX: cResolvedX

    property real lFinalX: {
        if (lWidthTarget <= 0) return baseMinLeft;
        if (layoutState === "settings") {
            return Math.max(screenMinLeft, cFinalX - lcGap - lWidthTarget);
        }
        let pushedX = Math.min(baseMinLeft, cFinalX - lcGap - lWidthTarget);
        return Math.max(screenMinLeft, pushedX);
    }

    property real rFinalX: {
        if (rWidthTarget <= 0) return baseMaxRight;
        if (layoutState === "sys") {
            return Math.min(screenMaxRight - rWidthTarget, cFinalX + cWidthTarget + crGap);
        }
        let pushedX = Math.max(baseMaxRight - rWidthTarget, cFinalX + cWidthTarget + crGap);
        return Math.min(screenMaxRight - rWidthTarget, pushedX);
    }
    property real rFinalClampedX: Math.max(screenMinLeft, Math.min(screenMaxRight - rWidthTarget, rFinalX))

    property real dynamicMinX: {
        if (isFill) return 0;
        let m = contentWrapper.width;
        let hasModules = (lWidthTarget > 0 || cWidthTarget > 0 || rWidthTarget > 0);
        if (lWidthTarget > 0) m = Math.min(m, lFinalX - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (cWidthTarget > 0) m = Math.min(m, cFinalX - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (rWidthTarget > 0) m = Math.min(m, rFinalClampedX - (barWindow ? barWindow.s(1) : 0) - distinctEdgePadding);
        if (layoutState !== "default") {
            return hasModules ? Math.max(0, m) : contentWrapper.width / 2;
        }
        return Math.max(0, Math.min(m, barWindow ? barWindow.horizontalOffset : 0));
    }

    property real dynamicMaxX: {
        if (isFill) return contentWrapper.width;
        let m = 0;
        let hasModules = (lWidthTarget > 0 || cWidthTarget > 0 || rWidthTarget > 0);
        if (lWidthTarget > 0) m = Math.max(m, lFinalX + lWidthTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (cWidthTarget > 0) m = Math.max(m, cFinalX + cWidthTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (rWidthTarget > 0) m = Math.max(m, rFinalClampedX + rWidthTarget + (barWindow ? barWindow.s(1) : 0) + distinctEdgePadding);
        if (layoutState !== "default") {
            return hasModules ? Math.min(contentWrapper.width, m) : contentWrapper.width / 2;
        }
        return Math.min(contentWrapper.width, Math.max(m, barWindow ? (barWindow.horizontalOffset + barWindow.effectiveBarWidth) : contentWrapper.width));
    }

    function matchId(item, id) {
        if (item === id) return true;
        if (id === "timedate" && (item === "time" || item === "clock")) return true;
        if (id === "info" && (item === "indicator" || item === "indicators" || item === "record")) return true;
        return false;
    }

    function getModuleX(id, state) {
        let arr = null, isLeft = false, isCenter = false, isRight = false;
        let checkFlat = (fArr) => {
            for (let i = 0; i < fArr.length; i++) {
                if (matchId(fArr[i], id)) return true;
            }
            return false;
        };

        if (checkFlat(flatLeftArr)) { arr = leftArr; isLeft = true; }
        else if (checkFlat(flatCenterArr)) { arr = centerArr; isCenter = true; }
        else if (checkFlat(flatRightArr)) { arr = rightArr; isRight = true; }

        if (!arr) return 0;

        let offset = 0;
        let baseX = isLeft ? lFinalX : (isCenter ? cFinalX : rFinalClampedX);

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
                    let w = getW(mId);
                    if (matchId(mId, id)) {
                        if (gItems > 0) offset += groupGap;
                        return baseX + offset;
                    }
                    if (w > 0) {
                        if (gItems > 0) offset += groupGap;
                        offset += w;
                        gItems++;
                    }
                }
                if (gItems > 0 && !groupHasId) {
                    offset += gap;
                }
            } else {
                if (matchId(item, id)) {
                    return baseX + offset;
                }
                let w = getW(item);
                if (w > 0) {
                    offset += w + gap;
                }
            }
        }
        return 0;
    }

    function getPositionedWidget(id) {
        if (id === "left") return leftWidget;
        if (id === "workspaces") return workspacesWidget;
        if (id === "focus") return focusWidget;
        if (id === "media") return mediaWidget;
        if (id === "vis") return visWidget;
        if (id === "tray") return trayWidget;
        if (id === "sysmon") return sysMonWidget;
        if (id === "netspeed") return netSpeedWidget;
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
        if (widgetName === "left") return leftWidget;
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
        else if (widgetName === "record") return infoWidget ? infoWidget.recRow : null;
        return null;
    }

    function getModuleY(widget) {
        if (!barWindow) return 0;
        let base = barWindow.baseOffsetY;
        let bHeight = barWindow.barHeight;
        let h = widget ? widget.height : 0;
        if (h > 0 && h < bHeight) {
            return base + Math.round((bHeight - h) / 2);
        }
        return base;
    }

    anchors.fill: parent
    visible: barWindow ? (!barWindow.isVertical && !barWindow.positionChanging) : true
    opacity: (visible && (!barWindow || !barWindow.positionChanging) && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0

    property real hideOffsetY: {
        if (!barWindow || barWindow.isRevealed) return 0;
        let offset = barWindow.barHeight + (barWindow.edgePadding !== undefined ? barWindow.edgePadding : 0) + barWindow.s(10);
        return barWindow.barPosition === "bottom" ? offset : -offset;
    }

    transform: Translate {
        y: contentWrapper.hideOffsetY
        Behavior on y {
            enabled: barWindow ? !barWindow.positionChanging : true
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
    }

    Behavior on opacity {
        enabled: barWindow ? (!barWindow.positionChanging && barWindow.startupCascadeFinished) : true
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: solidBackground
        x: isFill ? 0 : contentWrapper.dynamicMinX
        width: isFill ? contentWrapper.width : (contentWrapper.dynamicMaxX - contentWrapper.dynamicMinX)
        height: barWindow ? barWindow.barHeight : 0
        y: barWindow ? barWindow.baseOffsetY : 0
        color: Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        radius: isFill ? 0 : ThemeBackend.borderRadius
        border.width: (isSolid || isFill) ? 0 : 1
        border.color: (isSolid || isFill) ? "transparent" : Qt.alpha(ThemeBackend.surface0, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        visible: (isSolid || isFill) && (barWindow ? !barWindow.positionChanging : true)
        opacity: visible ? 1.0 : 0.0

        Behavior on x {
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

    Canvas {
        id: leftOuterCorner
        x: 0
        y: barWindow ? (barWindow.barPosition === "bottom" ? (barWindow.baseOffsetY - height) : (barWindow.baseOffsetY + barWindow.barHeight)) : 0
        width: contentWrapper.cornerRadius
        height: contentWrapper.cornerRadius
        visible: contentWrapper.isFill && (barWindow ? !barWindow.positionChanging : true)
        opacity: (visible && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0
        z: 0

        Connections {
            target: ThemeBackend
            function onBaseChanged() { leftOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper
            function onIsFillChanged() { leftOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper.barWindow || null
            function onBarPositionChanged() { leftOuterCorner.requestPaint(); }
            function onBarOpacityChanged() { leftOuterCorner.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0);
            ctx.beginPath();
            if (barWindow && barWindow.barPosition === "bottom") {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.arcTo(0, height, 0, 0, width);
                ctx.lineTo(0, 0);
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
        id: rightOuterCorner
        x: parent.width - width
        y: barWindow ? (barWindow.barPosition === "bottom" ? (barWindow.baseOffsetY - height) : (barWindow.baseOffsetY + barWindow.barHeight)) : 0
        width: contentWrapper.cornerRadius
        height: contentWrapper.cornerRadius
        visible: contentWrapper.isFill && (barWindow ? !barWindow.positionChanging : true)
        opacity: (visible && (!barWindow || barWindow.isRevealed)) ? 1.0 : 0.0
        z: 0

        Connections {
            target: ThemeBackend
            function onBaseChanged() { rightOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper
            function onIsFillChanged() { rightOuterCorner.requestPaint(); }
        }
        Connections {
            target: contentWrapper.barWindow || null
            function onBarPositionChanged() { rightOuterCorner.requestPaint(); }
            function onBarOpacityChanged() { rightOuterCorner.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0);
            ctx.beginPath();
            if (barWindow && barWindow.barPosition === "bottom") {
                ctx.moveTo(width, height);
                ctx.lineTo(0, height);
                ctx.arcTo(width, height, width, 0, width);
                ctx.lineTo(width, 0);
            } else {
                ctx.moveTo(width, 0);
                ctx.lineTo(0, 0);
                ctx.arcTo(width, 0, width, height, width);
                ctx.lineTo(width, height);
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
                let firstX = -1;
                let lastX = -1;
                let lastW = 0;
                let groupH = barWindow ? ((contentWrapper.isSolid && contentWrapper.distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight) : ((contentWrapper.isSolid && contentWrapper.distinctPills) ? 24 : 30);
                for (let i = 0; i < groupIds.length; i++) {
                    let id = groupIds[i];
                    let widget = contentWrapper.getPositionedWidget(id);
                    if (!widget || !widget.visible) continue;

                    let targetW = (widget.targetWidth !== undefined) ? widget.targetWidth : widget.width;
                    if (targetW <= 0) continue;

                    let mx = (widget.targetX !== undefined) ? widget.targetX : widget.x;
                    let mw = targetW;

                    if (firstX === -1) firstX = mx;
                    lastX = mx;
                    lastW = mw;
                }
                if (firstX === -1) return { x: 0, w: 0, h: groupH, v: false };
                return { x: firstX, w: (lastX + lastW - firstX), h: groupH, v: true };
            }

            property var metrics: getGroupMetrics()

            x: metrics.x
            height: metrics.h
            y: barWindow ? (barWindow.baseOffsetY + (barWindow.barHeight - height) / 2) : 0
            width: metrics.w
            visible: metrics.v && (barWindow ? !barWindow.positionChanging : true) && width > 0 && (!contentWrapper.isSolid || contentWrapper.distinctPills)
            opacity: visible ? 1.0 : 0.0

            color: (contentWrapper.isSolid && contentWrapper.distinctPills)
                ? Qt.alpha(Qt.darker(ThemeBackend.surface0, 1.15), (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
                : Qt.alpha(ThemeBackend.base, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
            radius: ThemeBackend.borderRadius
            border.width: 0

            Behavior on x {
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

    LeftWidget {
        id: leftWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(leftWidget)
        visible: contentWrapper.isModuleActive("left")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("left")
        isGrouped: contentWrapper.isModuleGrouped("left")
        targetX: contentWrapper.getModuleX("left", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    WorkspacesWidget {
        id: workspacesWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(workspacesWidget)
        visible: contentWrapper.isModuleActive("workspaces")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("workspaces")
        isGrouped: contentWrapper.isModuleGrouped("workspaces")
        targetX: contentWrapper.getModuleX("workspaces", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    FocusWidget {
        id: focusWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(focusWidget)
        visible: contentWrapper.isModuleActive("focus")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("focus")
        isGrouped: contentWrapper.isModuleGrouped("focus")
        targetX: contentWrapper.getModuleX("focus", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    MediaWidget {
        id: mediaWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(mediaWidget)
        visible: contentWrapper.isModuleActive("media")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        contentWrapperWidth: contentWrapper.width
        moduleActive: contentWrapper.isModuleActive("media")
        isGrouped: contentWrapper.isModuleGrouped("media")
        targetX: contentWrapper.getModuleX("media", contentWrapper.layoutState)
        layoutAnimationsEnabled: contentWrapper.layoutAnimationsEnabled

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    VisWidget {
        id: visWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(visWidget)
        visible: contentWrapper.isModuleActive("vis")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("vis")
        isGrouped: contentWrapper.isModuleGrouped("vis")
        targetX: contentWrapper.getModuleX("vis", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    TrayWidget {
        id: trayWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(trayWidget)
        visible: contentWrapper.isModuleActive("tray")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("tray")
        isGrouped: contentWrapper.isModuleGrouped("tray")
        suppressAnimation: contentWrapper.suppressAnimation
        isRightAligned: contentWrapper.trayAlignRight
        targetX: contentWrapper.getModuleX("tray", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SysMonWidget {
        id: sysMonWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(sysMonWidget)
        visible: contentWrapper.isModuleActive("sysmon")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("sysmon")
        isGrouped: contentWrapper.isModuleGrouped("sysmon")
        targetX: contentWrapper.getModuleX("sysmon", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    NetSpeedWidget {
        id: netSpeedWidget
        z: 1
        x: targetX
        y: barWindow ? barWindow.baseOffsetY : 0
        visible: contentWrapper.isModuleActive("netspeed")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        moduleActive: contentWrapper.isModuleActive("netspeed")
        isGrouped: contentWrapper.isModuleGrouped("netspeed")
        targetX: contentWrapper.getModuleX("netspeed", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    KbWidget {
        id: kbWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(kbWidget)
        visible: contentWrapper.isModuleActive("kb")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("kb")
        isGrouped: contentWrapper.isModuleGrouped("kb")
        targetX: contentWrapper.getModuleX("kb", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    WifiWidget {
        id: wifiWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(wifiWidget)
        visible: contentWrapper.isModuleActive("wifi")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("wifi")
        isGrouped: contentWrapper.isModuleGrouped("wifi")
        targetX: contentWrapper.getModuleX("wifi", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    BtWidget {
        id: btWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(btWidget)
        visible: contentWrapper.isModuleActive("bt")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("bt")
        isGrouped: contentWrapper.isModuleGrouped("bt")
        targetX: contentWrapper.getModuleX("bt", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    VolWidget {
        id: volWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(volWidget)
        visible: contentWrapper.isModuleActive("vol")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("vol")
        isGrouped: contentWrapper.isModuleGrouped("vol")
        targetX: contentWrapper.getModuleX("vol", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    BatWidget {
        id: batWidget
        z: 1
        x: targetX
        y: contentWrapper.getModuleY(batWidget)
        visible: contentWrapper.isModuleActive("bat")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("bat")
        isGrouped: contentWrapper.isModuleGrouped("bat")
        targetX: contentWrapper.getModuleX("bat", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
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
            let pills = [sysMonWidget, netSpeedWidget, kbWidget, wifiWidget, btWidget, volWidget, batWidget];
            let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
            let found = false;
            for (let i = 0; i < pills.length; i++) {
                let p = pills[i];
                if (p && p.visible && p.width > 0) {
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

    TimeDateWidget {
        id: timeDateWidget
        z: 10
        x: targetX
        y: contentWrapper.getModuleY(timeDateWidget)
        visible: contentWrapper.isModuleActive("timedate")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("timedate")
        isGrouped: contentWrapper.isModuleGrouped("timedate")
        targetX: contentWrapper.getModuleX("timedate", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    InfoWidget {
        id: infoWidget
        z: 10
        x: targetX
        y: contentWrapper.getModuleY(infoWidget)
        visible: contentWrapper.isModuleActive("info")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("info")
        isGrouped: contentWrapper.isModuleGrouped("info")
        targetX: contentWrapper.getModuleX("info", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    WeatherWidget {
        id: weatherWidget
        z: 10
        x: targetX
        y: contentWrapper.getModuleY(weatherWidget)
        visible: contentWrapper.isModuleActive("weather")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("weather")
        isGrouped: contentWrapper.isModuleGrouped("weather")
        targetX: contentWrapper.getModuleX("weather", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
}
