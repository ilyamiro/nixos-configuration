import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../"
import "../reusables"

PanelWindow {
    id: clipboardWindow

    screen: ClipboardController.screen

    WlrLayershell.namespace: "qs-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: clipboardWindow.isVisible
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region { item: topBarHole; intersection: Intersection.Xor }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function s(val) {
        return (typeof Scaler !== "undefined" && Scaler.s) ? Scaler.s(val) : val;
    }

    function closeClipboard() {
        ClipboardController.hide();
    }

    property bool isVisible: ClipboardController.isVisible
    property int configRevision: 0
    property bool isDirty: true

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            ClipboardController.hide();
            clipboardWindow.configRevision++;
        }
    }

    property var rawBarSettings: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : ({});
    }
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

    property string attachEdge: {
        if (barPosition === "bottom") return "top";
        if (barPosition === "left") return "right";
        if (barPosition === "right") return "left";
        return "bottom";
    }

    onBarPositionChanged: {
        ClipboardController.hide();
    }

    property bool isSideAttached: attachEdge === "left" || attachEdge === "right"

    property real cornerRadius: ThemeBackend.borderRadius <= 16 ? ThemeBackend.borderRadius * 2 : Math.min(32, 32 - 16 * Math.exp(-(ThemeBackend.borderRadius - 16) / 12))
    property real outerCornerRadius: cornerRadius

    property real baseLauncherWidth: isSideAttached ? Math.round(s(460) / 1.1) : Math.round(s(680) / 1.15)
    property int maxVisibleClips: isSideAttached ? 7 : 6

    property real targetLauncherHeight: {
        let count = Math.min(clipBoxModel.count, maxVisibleClips);
        if (count <= 0) {
            return s(64);
        }
        let hasPinned = false;
        let hasUnpinned = false;
        for (let i = 0; i < count; i++) {
            let item = clipBoxModel.get(i);
            if (item) {
                if (item.pinned) hasPinned = true;
                else hasUnpinned = true;
            }
        }
        let sectionCount = (hasPinned ? 1 : 0) + (hasUnpinned ? 1 : 0);
        let sectionH = sectionCount === 2 ? s(48) : (sectionCount === 1 ? s(22) : 0);
        return s(70) + sectionH + (count * s(56));
    }

    property real animatedLauncherHeight: targetLauncherHeight
    Behavior on animatedLauncherHeight {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    visible: isVisible || container.animProgress > 0.001

    property var allFetchedClips: []
    property int clipPageSize: 60
    property int clipOffset: 0
    property bool hasMoreClips: true
    property bool fetchPending: false

    property string expandedClipId: ""
    property string expandedClipFullText: ""
    property bool isClearingClips: false

    property bool isKeyboardNav: false
    property string pendingQuery: ""

    function grabInputFocus() {
        searchInput.forceActiveFocus();
        if (typeof searchInput.forceInputFocus === "function") {
            searchInput.forceInputFocus();
        }
    }

    function toggleExpandCurrent() {
        if (clipList.currentIndex >= 0 && clipList.currentItem && typeof clipList.currentItem.toggleExpand === "function") {
            clipList.currentItem.toggleExpand();
        }
    }

    ListModel {
        id: clipBoxModel
    }

    Process {
        id: clipWatcher
        running: true
        command: ["wl-paste", "--watch", "echo", "1"]
        stdout: SplitParser {
            onRead: (data) => {
                if (clipboardWindow.isVisible) {
                    clipWatchDebounce.restart();
                } else {
                    clipboardWindow.isDirty = true;
                }
            }
        }
    }

    Timer {
        id: clipWatchDebounce
        interval: 150
        repeat: false
        onTriggered: {
            clipboardWindow.refreshClips();
        }
    }

    Process {
        id: fullTextFetcher
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text;
                clipboardWindow.expandedClipFullText = (t && t.length > 0) ? t : "";
            }
        }
    }

    function fetchFullText(id) {
        clipboardWindow.expandedClipFullText = "";
        clipboardWindow.expandedClipId = id ? id.toString() : "";
        if (clipboardWindow.expandedClipId !== "") {
            fullTextFetcher.command = ["cliphist", "decode", clipboardWindow.expandedClipId];
            fullTextFetcher.running = true;
        }
    }

    function isSubsequence(sub, str) {
        let i = 0;
        let j = 0;
        while (i < sub.length && j < str.length) {
            if (sub[i] === str[j]) {
                i++;
            }
            j++;
        }
        return i === sub.length;
    }

    function getClipKey(item) {
        return (item && item.id !== undefined && item.id !== null) ? item.id.toString() : "";
    }

    function syncClipBoxModel(targetItems) {
        let newKeys = {};
        for (let i = 0; i < targetItems.length; i++) {
            newKeys[getClipKey(targetItems[i])] = true;
        }

        for (let i = clipBoxModel.count - 1; i >= 0; i--) {
            let key = getClipKey(clipBoxModel.get(i));
            if (!newKeys[key]) {
                clipBoxModel.remove(i);
            }
        }

        for (let i = 0; i < targetItems.length; i++) {
            let item = targetItems[i];
            let targetKey = getClipKey(item);

            if (i < clipBoxModel.count) {
                let currentKey = getClipKey(clipBoxModel.get(i));
                if (currentKey === targetKey) {
                    let cur = clipBoxModel.get(i);
                    if (cur.pinned !== item.pinned || cur.content !== item.content || cur.type !== item.type || cur.sectionCategory !== item.sectionCategory) {
                        clipBoxModel.set(i, item);
                    }
                } else {
                    let foundIndex = -1;
                    for (let j = i + 1; j < clipBoxModel.count; j++) {
                        if (getClipKey(clipBoxModel.get(j)) === targetKey) {
                            foundIndex = j;
                            break;
                        }
                    }
                    if (foundIndex !== -1) {
                        clipBoxModel.move(foundIndex, i, 1);
                        let cur = clipBoxModel.get(i);
                        if (cur.pinned !== item.pinned || cur.content !== item.content || cur.type !== item.type || cur.sectionCategory !== item.sectionCategory) {
                            clipBoxModel.set(i, item);
                        }
                    } else {
                        clipBoxModel.insert(i, item);
                    }
                }
            } else {
                clipBoxModel.append(item);
            }
        }

        while (clipBoxModel.count > targetItems.length) {
            clipBoxModel.remove(clipBoxModel.count - 1);
        }
    }

    function executeClipFilter(query) {
        clipboardWindow.isKeyboardNav = false;
        if (keyboardNavTimer.running) keyboardNavTimer.stop();

        let rawTrimmed = (query || "").trim();
        let q = rawTrimmed.toLowerCase();
        let filtered = [];

        let pinnedLabel = typeof I18n !== "undefined" ? I18n.t("clipboard.pinned", "Pinned") : "Pinned";
        let recentLabel = typeof I18n !== "undefined" ? I18n.t("clipboard.recent", "Recent") : "Recent";

        for (let i = 0; i < clipboardWindow.allFetchedClips.length; i++) {
            let item = clipboardWindow.allFetchedClips[i];
            let contentLower = (item.content || "").toLowerCase();
            let matchQuality = 0;
            let matches = false;

            if (q.length === 0) {
                matches = true;
            } else {
                if (contentLower === q) {
                    matchQuality = 100000;
                    matches = true;
                } else if (contentLower.startsWith(q)) {
                    matchQuality = 50000;
                    matches = true;
                } else if (contentLower.includes(q)) {
                    matchQuality = 10000;
                    matches = true;
                } else if (isSubsequence(q, contentLower)) {
                    matchQuality = 1000;
                    matches = true;
                }
            }

            if (matches) {
                filtered.push({
                    id: item.id,
                    pinned: Boolean(item.pinned),
                    content: item.content || "",
                    type: item.type || "text",
                    sectionCategory: item.pinned ? pinnedLabel : recentLabel,
                    score: (item.pinned ? 500000 : 0) + matchQuality
                });
            }
        }

        if (q.length > 0) {
            filtered.sort(function(a, b) {
                if (a.score !== b.score) {
                    return b.score - a.score;
                }
                return 0;
            });
        } else {
            let pinnedItems = [];
            let unpinnedItems = [];
            for (let i = 0; i < filtered.length; i++) {
                if (filtered[i].pinned) pinnedItems.push(filtered[i]);
                else unpinnedItems.push(filtered[i]);
            }
            filtered = pinnedItems.concat(unpinnedItems);
        }

        syncClipBoxModel(filtered);

        if (clipBoxModel.count > 0) {
            clipList.currentIndex = 0;
        } else {
            clipList.currentIndex = -1;
        }
    }

    function filterClips(query) {
        clipboardWindow.pendingQuery = query;
        filterDebounceTimer.restart();
    }

    Timer {
        id: filterDebounceTimer
        interval: 80
        repeat: false
        onTriggered: {
            clipboardWindow.executeClipFilter(clipboardWindow.pendingQuery);
        }
    }

    Process {
        id: clipFetcherProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (clipboardWindow.fetchPending) {
                    clipboardWindow.fetchPending = false;
                    clipboardWindow.clipOffset = 0;
                    clipboardWindow.hasMoreClips = true;
                    clipboardWindow.fetchNextClipPage();
                    return;
                }

                try {
                    let txt = this.text.trim();
                    if (txt.length > 0) {
                        let items = JSON.parse(txt);
                        if (items.length < clipboardWindow.clipPageSize) {
                            clipboardWindow.hasMoreClips = false;
                        }

                        if (clipboardWindow.clipOffset === 0) {
                            clipboardWindow.allFetchedClips = items;
                        } else {
                            let existingIds = {};
                            for (let i = 0; i < clipboardWindow.allFetchedClips.length; i++) {
                                existingIds[clipboardWindow.allFetchedClips[i].id] = true;
                            }
                            for (let i = 0; i < items.length; i++) {
                                if (!existingIds[items[i].id]) {
                                    clipboardWindow.allFetchedClips.push(items[i]);
                                    existingIds[items[i].id] = true;
                                }
                            }
                        }
                        clipboardWindow.clipOffset = clipboardWindow.allFetchedClips.length;
                        clipboardWindow.executeClipFilter(searchInput.text);
                    } else {
                        clipboardWindow.hasMoreClips = false;
                        if (clipboardWindow.clipOffset === 0) {
                            clipboardWindow.allFetchedClips = [];
                            clipboardWindow.executeClipFilter(searchInput.text);
                        }
                    }
                } catch(e) {
                    clipboardWindow.hasMoreClips = false;
                }
            }
        }
    }

    Process {
        id: clipActionProc
        running: false
    }

    function refreshClips() {
        clipboardWindow.clipOffset = 0;
        clipboardWindow.hasMoreClips = true;
        if (clipFetcherProc.running) {
            clipboardWindow.fetchPending = true;
            return;
        }
        fetchNextClipPage();
    }

    function fetchNextClipPage() {
        if (clipFetcherProc.running || !clipboardWindow.hasMoreClips) return;
        let qsDir = (typeof Caching !== "undefined" && Caching.qsDir) ? Caching.qsDir : "";
        let cacheDir = (typeof Caching !== "undefined" && Caching.getCacheDir) ? Caching.getCacheDir("clipboard") : "";
        clipFetcherProc.command = ["python3", qsDir + "/clipboard/clip_fetcher.py", clipboardWindow.clipOffset.toString(), clipboardWindow.clipPageSize.toString(), cacheDir];
        clipFetcherProc.running = true;
    }

    function copyClip(id, isPinned) {
        if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
        if (isPinned) {
            Quickshell.execDetached(["bash", "-c", "cliphist decode " + id + " | wl-copy && (sleep 0.15; NEW_ID=$(cliphist list | head -n 1 | awk '{print $1}'); python3 " + Caching.qsDir + "/clipboard/clip_fetcher.py pin $NEW_ID " + Caching.getCacheDir("clipboard") + ") &"]);
        } else {
            Quickshell.execDetached(["bash", "-c", "cliphist decode " + id + " | wl-copy"]);
        }
        closeClipboard();
    }

    function pinClip(id, index) {
        clipActionProc.command = ["python3", Caching.qsDir + "/clipboard/clip_fetcher.py", "pin", id.toString(), Caching.getCacheDir("clipboard")];
        clipActionProc.running = true;
        for (let i = 0; i < clipboardWindow.allFetchedClips.length; i++) {
            if (clipboardWindow.allFetchedClips[i].id.toString() === id.toString()) {
                clipboardWindow.allFetchedClips[i].pinned = !clipboardWindow.allFetchedClips[i].pinned;
                break;
            }
        }
        clipboardWindow.executeClipFilter(searchInput.text);
    }

    function deleteClip(id, index) {
        clipActionProc.command = ["python3", Caching.qsDir + "/clipboard/clip_fetcher.py", "delete", id.toString(), Caching.getCacheDir("clipboard")];
        clipActionProc.running = true;
        clipboardWindow.allFetchedClips = clipboardWindow.allFetchedClips.filter(item => item.id.toString() !== id.toString());
        clipBoxModel.remove(index);
    }

    function clearAllClips() {
        clipboardWindow.allFetchedClips = [];
        clipBoxModel.clear();
        clipActionProc.command = ["python3", Caching.qsDir + "/clipboard/clip_fetcher.py", "wipe", Caching.getCacheDir("clipboard")];
        clipActionProc.running = true;
    }

    Timer {
        id: clearFinishTimer
        interval: 300
        repeat: false
        onTriggered: {
            clipboardWindow.clearAllClips();
            clipboardWindow.isClearingClips = false;
        }
    }

    function animateClear() {
        if (clipboardWindow.isClearingClips || clipBoxModel.count === 0) return;
        clipboardWindow.isClearingClips = true;

        let visibleDelegates = [];
        for (let i = 0; i < clipList.contentItem.children.length; i++) {
            let child = clipList.contentItem.children[i];
            if (child && typeof child.triggerClearSlide === "function") {
                if (child.y + child.height >= clipList.contentY && child.y <= clipList.contentY + clipList.height) {
                    visibleDelegates.push(child);
                }
            }
        }

        visibleDelegates.sort((a, b) => a.y - b.y);

        if (visibleDelegates.length === 0) {
            clipboardWindow.clearAllClips();
            clipboardWindow.isClearingClips = false;
            return;
        }

        let step = 50;
        let totalTime = 0;
        for (let i = 0; i < visibleDelegates.length; i++) {
            let d = i * step;
            visibleDelegates[i].triggerClearSlide(d);
            totalTime = d + 220;
        }

        clearFinishTimer.interval = totalTime + 40;
        clearFinishTimer.start();
    }

    function activateIndex(index) {
        if (index < 0 || index >= clipBoxModel.count) return;
        let item = clipBoxModel.get(index);
        if (!item) return;
        copyClip(item.id, item.pinned);
    }

    Item {
        id: topBarHole

        property int barThickness: 48
        property string bp: clipboardWindow.barPosition
        property bool activeBar: !clipboardWindow.isBarEffectivelyHidden

        x: {
            if (!activeBar) return 0;
            if (bp === "left") return 0;
            if (bp === "right") return clipboardWindow.width - barThickness;
            return 0;
        }

        y: {
            if (!activeBar) return 0;
            if (bp === "top") return 0;
            if (bp === "bottom") return clipboardWindow.height - barThickness;
            return 0;
        }

        width: {
            if (!activeBar) return 0;
            if (bp === "left" || bp === "right") return barThickness;
            return clipboardWindow.width;
        }

        height: {
            if (!activeBar) return 0;
            if (bp === "top" || bp === "bottom") return barThickness;
            return clipboardWindow.height;
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: {
            clipboardWindow.grabInputFocus();
        }
    }

    Timer {
        id: focusRetryTimer
        interval: 120
        repeat: false
        onTriggered: {
            clipboardWindow.grabInputFocus();
        }
    }

    Timer {
        id: focusFinalTimer
        interval: 250
        repeat: false
        onTriggered: {
            clipboardWindow.grabInputFocus();
        }
    }

    Timer {
        id: keyboardNavTimer
        interval: 500
        repeat: false
        onTriggered: {
            clipboardWindow.isKeyboardNav = false;
        }
    }

    onIsVisibleChanged: {
        if (isVisible) {
            searchInput.clear();
            filterDebounceTimer.stop();
            if (clipboardWindow.isDirty || clipboardWindow.allFetchedClips.length === 0) {
                clipboardWindow.isDirty = false;
                refreshClips();
            } else {
                executeClipFilter("");
            }
            clipboardWindow.grabInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
            focusFinalTimer.restart();
        } else {
            clipboardWindow.expandedClipId = "";
            filterDebounceTimer.stop();
            focusTimer.stop();
            focusRetryTimer.stop();
            focusFinalTimer.stop();
            keyboardNavTimer.stop();
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: clipboardWindow.isVisible
        onClicked: closeClipboard()
    }

    Item {
        id: container

        MouseArea {
            anchors.fill: parent
        }

        property real animProgress: clipboardWindow.isVisible ? 1.0 : 0.0
        Behavior on animProgress {
            NumberAnimation {
                duration: clipboardWindow.isVisible ? 300 : 200
                easing.type: Easing.OutCubic
            }
        }

        property real dynamicCornerRadius: Math.max(0, Math.min(clipboardWindow.outerCornerRadius, (clipboardWindow.isSideAttached ? width : height)))

        x: {
            if (clipboardWindow.attachEdge === "left") return 0;
            if (clipboardWindow.attachEdge === "right") return clipboardWindow.width - width;
            return Math.floor((clipboardWindow.width - width) / 2);
        }
        y: {
            if (clipboardWindow.attachEdge === "top") return 0;
            if (clipboardWindow.attachEdge === "bottom") return clipboardWindow.height - height;
            return Math.floor((clipboardWindow.height - height) / 2);
        }
        width: clipboardWindow.isSideAttached
               ? (clipboardWindow.baseLauncherWidth * animProgress)
               : clipboardWindow.baseLauncherWidth
        height: !clipboardWindow.isSideAttached
                ? (clipboardWindow.animatedLauncherHeight * animProgress)
                : clipboardWindow.animatedLauncherHeight

        opacity: (clipboardWindow.isVisible || animProgress > 0.001) ? 1.0 : 0.0

        Shape {
            visible: clipboardWindow.attachEdge === "top" && container.dynamicCornerRadius > 0.5
            x: -container.dynamicCornerRadius
            y: 0
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "top" && container.dynamicCornerRadius > 0.5
            x: parent.width
            y: 0
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: 0
                PathLine { x: 0; y: 0 }
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
            x: -container.dynamicCornerRadius
            y: parent.height - container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: container.dynamicCornerRadius
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: container.dynamicCornerRadius
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
            x: parent.width
            y: parent.height - container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: container.dynamicCornerRadius
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "left" && container.dynamicCornerRadius > 0.5
            x: 0
            y: -container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "left" && container.dynamicCornerRadius > 0.5
            x: 0
            y: parent.height
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: container.dynamicCornerRadius
                PathLine { x: 0; y: 0 }
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: container.dynamicCornerRadius
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "right" && container.dynamicCornerRadius > 0.5
            x: parent.width - container.dynamicCornerRadius
            y: -container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: 0
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: clipboardWindow.attachEdge === "right" && container.dynamicCornerRadius > 0.5
            x: parent.width - container.dynamicCornerRadius
            y: parent.height
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: container.dynamicCornerRadius
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            radius: clipboardWindow.cornerRadius
            color: ThemeBackend.base
            border.width: 0
            border.color: "transparent"
            clip: true

            Rectangle {
                visible: clipboardWindow.attachEdge === "top" && container.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "top" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "left" && container.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "left" && container.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "right" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: clipboardWindow.attachEdge === "right" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Item {
                id: contentContainer
                anchors.fill: parent
                anchors.margins: clipboardWindow.s(14)

                readonly property bool isSearchAtBottom: clipboardWindow.attachEdge === "bottom"

                RowLayout {
                    id: searchRow
                    z: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: contentContainer.isSearchAtBottom ? (parent.height - height) : 0
                    height: clipboardWindow.s(36)
                    spacing: clipboardWindow.s(8)

                    Input {
                        id: searchInput
                        focus: true
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: clipboardWindow.s(36)

                        baseColor: ThemeBackend.surface0
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.text
                        subTextColor: ThemeBackend.subtext0
                        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                        cornerRadius: Math.min(ThemeBackend.borderRadius, clipboardWindow.s(10))
                        fontPixelSize: clipboardWindow.s(12)
                        charSpacing: 1

                        placeholderText: typeof I18n !== "undefined" ? I18n.t("clipboard.search", "Search clipboard") : "Search clipboard"
                        showClearButton: true

                        onTextEdited: function(newText) {
                            filterClips(newText);
                        }
                        onCleared: filterClips("")

                        Keys.onDownPressed: function(event) {
                            clipboardWindow.isKeyboardNav = true;
                            keyboardNavTimer.restart();
                            if (clipList.currentIndex < clipBoxModel.count - 1) {
                                clipList.currentIndex++;
                            }
                            event.accepted = true;
                        }
                        Keys.onUpPressed: function(event) {
                            clipboardWindow.isKeyboardNav = true;
                            keyboardNavTimer.restart();
                            if (clipList.currentIndex > 0) {
                                clipList.currentIndex--;
                            }
                            event.accepted = true;
                        }
                        Keys.onTabPressed: function(event) {
                            clipboardWindow.toggleExpandCurrent();
                            event.accepted = true;
                        }
                        Keys.onBacktabPressed: function(event) {
                            clipboardWindow.toggleExpandCurrent();
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: function(event) {
                            activateIndex(clipList.currentIndex);
                            event.accepted = true;
                        }
                        Keys.onDeletePressed: function(event) {
                            if (clipList.currentIndex >= 0 && clipList.currentIndex < clipBoxModel.count) {
                                let item = clipBoxModel.get(clipList.currentIndex);
                                if (item) {
                                    deleteClip(item.id, clipList.currentIndex);
                                }
                            }
                            event.accepted = true;
                        }
                        Keys.onEscapePressed: function(event) {
                            closeClipboard();
                            event.accepted = true;
                        }
                    }

                    ClickButton {
                        id: clearBtn
                        enabled: !clipboardWindow.isClearingClips && clipBoxModel.count > 0
                        Layout.preferredWidth: clipboardWindow.s(80)
                        Layout.preferredHeight: clipboardWindow.s(36)
                        horizontalPadding: clipboardWindow.s(10)
                        cornerRadius: Math.min(ThemeBackend.borderRadius, clipboardWindow.s(10))
                        buttonText: typeof I18n !== "undefined" ? (I18n.t("clipboard.clear") || "Clear") : "Clear"
                        textFontSize: clipboardWindow.s(11)
                        buttonIcon: "󰆴"
                        iconFontSize: clipboardWindow.s(14)
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.text
                        visible: true

                        onTriggered: {
                            clipboardWindow.animateClear();
                        }
                    }
                }

                Item {
                    id: listContainer
                    z: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: contentContainer.isSearchAtBottom ? 0 : (searchRow.height + clipboardWindow.s(10))
                    height: Math.max(0, parent.height - searchRow.height - clipboardWindow.s(10))
                    clip: true

                    ListView {
                        id: clipList
                        anchors.fill: parent
                        clip: true
                        model: clipBoxModel
                        spacing: clipboardWindow.s(4)
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: !clipboardWindow.isClearingClips && (contentHeight > height)

                        highlightFollowsCurrentItem: false

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0) {
                                positionViewAtIndex(currentIndex, ListView.Contain);
                            }
                        }

                        section.property: "sectionCategory"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            width: ListView.view ? ListView.view.width : 0
                            height: clipboardWindow.s(22)
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: clipboardWindow.s(4)
                                anchors.verticalCenter: parent.verticalCenter
                                text: section
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: clipboardWindow.s(10.5)
                                color: ThemeBackend.subtext0
                                opacity: 0.85
                            }
                        }

                        add: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 0.0
                                to: 1.0
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                property: "scale"
                                from: 0.96
                                to: 1.0
                                duration: 270
                                easing.type: Easing.OutCubic
                            }
                        }

                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                to: 0.0
                                duration: 170
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                property: "scale"
                                to: 0.96
                                duration: 170
                                easing.type: Easing.OutCubic
                            }
                        }

                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 280
                                easing.type: Easing.OutCubic
                            }
                        }

                        move: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 280
                                easing.type: Easing.OutCubic
                            }
                        }

                        moveDisplaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 280
                                easing.type: Easing.OutCubic
                            }
                        }

                        onContentYChanged: {
                            if (clipboardWindow.hasMoreClips && !clipFetcherProc.running && searchInput.text.trim().length === 0) {
                                if (contentY + height >= contentHeight - clipboardWindow.s(450)) {
                                    clipboardWindow.fetchNextClipPage();
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            active: clipList.moving || clipList.movingVertically
                            width: clipboardWindow.s(4)
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: clipboardWindow.s(4); radius: clipboardWindow.s(2); color: ThemeBackend.surface2 }
                        }

                        delegate: Item {
                            id: clipDelegateWrapper
                            width: ListView.view ? ListView.view.width : 0
                            height: clipDelegateCard.height
                            z: isSelected ? 2 : 1

                            property bool isSelected: index === clipList.currentIndex

                            scale: clipCardMa.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                            property bool itemExpanded: false
                            property real itemExpandProgress: itemExpanded ? 1.0 : 0.0
                            Behavior on itemExpandProgress {
                                enabled: !clipCardMa.draggingV
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutQuart
                                    onRunningChanged: {
                                        if (!running && clipDelegateWrapper.isSelected) {
                                            clipList.positionViewAtIndex(clipList.currentIndex, ListView.Contain);
                                        }
                                    }
                                }
                            }

                            property string clipIdString: (typeof model !== "undefined" && model && model.id !== undefined) ? model.id.toString() : (clipBoxModel.get(index) ? clipBoxModel.get(index).id.toString() : "")
                            property real dragX: 0
                            property bool isDismissing: false

                            property real clearDelay: 0
                            NumberAnimation {
                                id: clearSlideAnim
                                target: clipDelegateWrapper
                                property: "dragX"
                                to: clipList.width * 1.2
                                duration: 220
                                easing.type: Easing.OutQuad
                            }
                            Timer {
                                id: clearSlideTimer
                                interval: clipDelegateWrapper.clearDelay
                                onTriggered: clearSlideAnim.start()
                            }
                            function triggerClearSlide(delayMs) {
                                clearDelay = delayMs;
                                clearSlideTimer.start();
                            }

                            Text {
                                id: textMeasure
                                visible: false
                                width: Math.max(10, clipboardWindow.baseLauncherWidth - clipboardWindow.s(96))
                                text: (model && model.content) ? model.content : ""
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: clipboardWindow.s(12)
                                wrapMode: Text.Wrap
                            }

                            function toggleExpand() {
                                if (!clipDelegateCard.canExpand) return;
                                if (!itemExpanded && model.type !== "image") {
                                    clipboardWindow.fetchFullText(clipDelegateWrapper.clipIdString);
                                }
                                itemExpanded = !itemExpanded;
                                itemExpandProgress = Qt.binding(() => itemExpanded ? 1.0 : 0.0);
                            }

                            onItemExpandedChanged: {
                                if (itemExpanded) {
                                    clipList.currentIndex = index;
                                    if (model.type !== "image" && clipboardWindow.expandedClipId !== clipIdString) {
                                        clipboardWindow.fetchFullText(clipIdString);
                                    }
                                    clipList.positionViewAtIndex(index, ListView.Contain);
                                }
                            }

                            NumberAnimation {
                                id: clipResetAnim
                                target: clipDelegateWrapper
                                property: "dragX"
                                from: clipDelegateWrapper.dragX
                                to: 0
                                duration: 200
                                easing.type: Easing.OutCubic
                            }

                            NumberAnimation {
                                id: clipDismissAnim
                                target: clipDelegateWrapper
                                property: "dragX"
                                from: clipDelegateWrapper.dragX
                                to: 0
                                duration: 200
                                easing.type: Easing.OutQuad
                                onFinished: clipboardWindow.deleteClip(clipDelegateWrapper.clipIdString, index)
                            }

                            Rectangle {
                                id: cardMask
                                width: clipDelegateCard.width
                                height: clipDelegateCard.height
                                radius: clipDelegateCard.radius
                                visible: false
                                layer.enabled: clipDelegateCard.isImage
                            }

                            Rectangle {
                                id: clipDelegateCard
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top

                                layer.enabled: clipDelegateCard.isImage
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: cardMask
                                }

                                readonly property bool isImage: model.type === "image"
                                readonly property bool canExpand: {
                                    if (isImage) return true;
                                    let c = (model && model.content) ? model.content : "";
                                    if (c.indexOf("\n") !== -1) return true;
                                    if (c.length > 45) return true;
                                    if (textMeasure.lineCount >= 2) return true;
                                    if (textMeasure.paintedHeight > clipboardWindow.s(18)) return true;
                                    return false;
                                }
                                readonly property real baseH: clipboardWindow.s(52)
                                readonly property real expandedH: isImage ? clipboardWindow.s(250) : clipboardWindow.s(172)
                                height: baseH + (expandedH - baseH) * clipDelegateWrapper.itemExpandProgress

                                transform: Translate { x: clipDelegateWrapper.dragX }
                                opacity: Math.max(0.0, 1.0 - (Math.abs(clipDelegateWrapper.dragX) / (clipDelegateCard.width * 0.75)))

                                radius: Math.min(ThemeBackend.borderRadius, clipboardWindow.s(12))
                                color: {
                                    if (clipDelegateWrapper.isSelected) {
                                        return isImage ? ThemeBackend.surface0 : ThemeBackend.mauve;
                                    }
                                    return isImage ? ThemeBackend.surface0 : (clipCardMa.containsMouse ? Qt.lighter(ThemeBackend.surface1, 1.04) : ThemeBackend.surface1);
                                }
                                clip: true

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                Image {
                                    id: clipCardCropImg
                                    anchors.fill: parent
                                    source: (clipDelegateCard.isImage && model.content) ? (model.content.startsWith("file://") ? model.content : "file://" + model.content) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                    visible: clipDelegateCard.isImage
                                    opacity: 1.0 - (clipDelegateWrapper.itemExpandProgress * 0.85)
                                }

                                Image {
                                    id: clipCardFitImg
                                    anchors.fill: parent
                                    anchors.margins: clipboardWindow.s(6) * clipDelegateWrapper.itemExpandProgress
                                    source: (clipDelegateCard.isImage && model.content) ? (model.content.startsWith("file://") ? model.content : "file://" + model.content) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                    visible: clipDelegateCard.isImage && clipDelegateWrapper.itemExpandProgress > 0.01
                                    opacity: clipDelegateWrapper.itemExpandProgress
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: clipDelegateCard.radius
                                    color: Qt.rgba(0, 0, 0, clipCardMa.containsMouse ? 0.15 : 0.0)
                                    visible: clipDelegateCard.isImage
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Rectangle {
                                    id: imageSelectionBorder
                                    anchors.fill: parent
                                    radius: clipDelegateCard.radius
                                    color: "transparent"
                                    border.width: (clipDelegateWrapper.isSelected && clipDelegateCard.isImage) ? clipboardWindow.s(2) : 0
                                    border.color: (clipDelegateWrapper.isSelected && clipDelegateCard.isImage) ? ThemeBackend.mauve : "transparent"
                                    z: 10
                                    visible: clipDelegateCard.isImage

                                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: clipCardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !clipboardWindow.isClearingClips
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                                    property real startRootX: 0
                                    property real startRootY: 0
                                    property bool draggingH: false
                                    property bool draggingV: false

                                    onPressed: (mouse) => {
                                        clipList.currentIndex = index;
                                        let pt = mapToItem(container, mouse.x, mouse.y);
                                        startRootX = pt.x;
                                        startRootY = pt.y;
                                        draggingH = false;
                                        draggingV = false;
                                        clipResetAnim.stop();
                                        if (model.type !== "image" && clipDelegateCard.canExpand) {
                                            clipboardWindow.fetchFullText(clipDelegateWrapper.clipIdString);
                                        }
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return;
                                        let pt = mapToItem(container, mouse.x, mouse.y);
                                        let dx = pt.x - startRootX;
                                        let dy = pt.y - startRootY;

                                        if (!draggingH && !draggingV) {
                                            if (Math.abs(dx) > clipboardWindow.s(6) && Math.abs(dx) > Math.abs(dy)) {
                                                draggingH = true;
                                                clipCardMa.preventStealing = true;
                                            } else if (clipDelegateCard.canExpand && Math.abs(dy) > clipboardWindow.s(6) && Math.abs(dy) >= Math.abs(dx)) {
                                                draggingV = true;
                                                clipCardMa.preventStealing = true;
                                                if (model.type !== "image" && clipboardWindow.expandedClipId !== clipDelegateWrapper.clipIdString) {
                                                    clipboardWindow.fetchFullText(clipDelegateWrapper.clipIdString);
                                                }
                                            }
                                        }

                                        if (draggingH) {
                                            clipDelegateWrapper.dragX = dx;
                                        } else if (draggingV && clipDelegateCard.canExpand) {
                                            let dragDist = clipboardWindow.s(120);
                                            let targetProg = clipDelegateWrapper.itemExpanded
                                                ? Math.max(0.0, Math.min(1.0, 1.0 + (dy / dragDist)))
                                                : Math.max(0.0, Math.min(1.0, dy / dragDist));
                                            clipDelegateWrapper.itemExpandProgress = targetProg;
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        clipCardMa.preventStealing = false;
                                        if (draggingH) {
                                            let threshold = clipDelegateCard.width * 0.25;
                                            if (Math.abs(clipDelegateWrapper.dragX) > threshold) {
                                                clipDelegateWrapper.isDismissing = true;
                                                clipDismissAnim.from = clipDelegateWrapper.dragX;
                                                clipDismissAnim.to = clipDelegateWrapper.dragX > 0 ? clipDelegateCard.width * 1.2 : -clipDelegateCard.width * 1.2;
                                                clipDismissAnim.start();
                                            } else {
                                                clipResetAnim.from = clipDelegateWrapper.dragX;
                                                clipResetAnim.start();
                                            }
                                            draggingH = false;
                                        } else if (draggingV && clipDelegateCard.canExpand) {
                                            if (!clipDelegateWrapper.itemExpanded && clipDelegateWrapper.itemExpandProgress > 0.35) {
                                                clipDelegateWrapper.itemExpanded = true;
                                            } else if (clipDelegateWrapper.itemExpanded && clipDelegateWrapper.itemExpandProgress < 0.65) {
                                                clipDelegateWrapper.itemExpanded = false;
                                            }
                                            clipDelegateWrapper.itemExpandProgress = Qt.binding(() => clipDelegateWrapper.itemExpanded ? 1.0 : 0.0);
                                            draggingV = false;
                                        } else {
                                            let ptE = mapToItem(clipItemExpandIcon, mouse.x, mouse.y);
                                            let inE = clipItemExpandIcon.visible && ptE.x >= 0 && ptE.y >= 0 && ptE.x <= clipItemExpandIcon.width && ptE.y <= clipItemExpandIcon.height;
                                            if (!inE) {
                                                if (mouse.button === Qt.RightButton) {
                                                    clipboardWindow.pinClip(clipDelegateWrapper.clipIdString, index);
                                                } else {
                                                    clipboardWindow.copyClip(clipDelegateWrapper.clipIdString, model.pinned);
                                                }
                                            }
                                        }
                                    }

                                    onCanceled: {
                                        clipCardMa.preventStealing = false;
                                        if (draggingH) {
                                            clipResetAnim.from = clipDelegateWrapper.dragX;
                                            clipResetAnim.start();
                                            draggingH = false;
                                        }
                                        if (draggingV && clipDelegateCard.canExpand) {
                                            clipDelegateWrapper.itemExpandProgress = Qt.binding(() => clipDelegateWrapper.itemExpanded ? 1.0 : 0.0);
                                            draggingV = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    id: clipTypeIcon
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.leftMargin: clipboardWindow.s(8)
                                    anchors.topMargin: clipboardWindow.s(11)
                                    width: clipboardWindow.s(30)
                                    height: clipboardWindow.s(30)
                                    radius: clipboardWindow.s(8)
                                    color: (!clipDelegateCard.isImage && clipDelegateWrapper.isSelected) ? Qt.rgba(0, 0, 0, 0.15) : ThemeBackend.surface2
                                    clip: true
                                    z: 3
                                    visible: (clipDelegateCard.isImage || clipDelegateWrapper.itemExpandProgress < 0.99) && opacity > 0.001
                                    opacity: clipDelegateCard.isImage ? 1.0 : Math.max(0.0, 1.0 - clipDelegateWrapper.itemExpandProgress * 2.0)

                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    Image {
                                        id: clipThumbImg
                                        anchors.fill: parent
                                        anchors.margins: clipboardWindow.s(2)
                                        source: (!clipDelegateCard.isImage && model.type === "image" && model.content) ? (model.content.startsWith("file://") ? model.content : "file://" + model.content) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                        mipmap: true
                                        visible: model.type === "image" && status === Image.Ready
                                    }

                                    Text {
                                        id: delegateFontIcon
                                        anchors.centerIn: parent
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: clipboardWindow.s(14)
                                        color: (!clipDelegateCard.isImage && clipDelegateWrapper.isSelected) ? ThemeBackend.crust : ThemeBackend.subtext0
                                        text: model.type === "image" ? "󰋩" : "󰈙"
                                        visible: model.type !== "image" || (!model.content || clipThumbImg.status !== Image.Ready)

                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }
                                }

                                FlipIcon {
                                    id: clipItemExpandIcon
                                    z: 4
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: clipboardWindow.s(12.8)
                                    anchors.rightMargin: clipboardWindow.s(8)
                                    size: clipboardWindow.s(26.4)
                                    cornerRadius: clipboardWindow.s(6.6)
                                    accentColor: (!clipDelegateCard.isImage && clipDelegateWrapper.isSelected) ? Qt.rgba(0, 0, 0, 0.15) : ThemeBackend.surface2
                                    iconColor: (!clipDelegateCard.isImage && clipDelegateWrapper.isSelected) ? (isHoveredOrHighlighted ? ThemeBackend.base : ThemeBackend.crust) : (isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.subtext1)
                                    autoToggle: false
                                    visible: clipDelegateCard.canExpand
                                    flipped: clipDelegateWrapper.itemExpandProgress > 0.5
                                    onClicked: {
                                        clipList.currentIndex = index;
                                        clipDelegateWrapper.toggleExpand();
                                    }
                                }

                                Item {
                                    id: clipSummaryContainer
                                    z: 2
                                    anchors.left: clipTypeIcon.right
                                    anchors.leftMargin: clipboardWindow.s(8)
                                    anchors.right: parent.right
                                    anchors.rightMargin: clipDelegateCard.canExpand ? clipboardWindow.s(38) : clipboardWindow.s(12)
                                    anchors.top: parent.top
                                    anchors.topMargin: clipboardWindow.s(10)
                                    height: clipboardWindow.s(32)
                                    visible: !clipDelegateCard.isImage && clipDelegateWrapper.itemExpandProgress < 0.99 && opacity > 0.001
                                    opacity: Math.max(0.0, 1.0 - clipDelegateWrapper.itemExpandProgress * 2.0)
                                    clip: true

                                    Text {
                                        id: clipSummaryText
                                        anchors.fill: parent
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: model.content || ""
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: clipboardWindow.s(12)
                                        font.weight: clipDelegateWrapper.isSelected ? Font.Bold : Font.Normal
                                        color: clipDelegateWrapper.isSelected ? ThemeBackend.crust : ThemeBackend.text
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    id: clipTextExpandArea
                                    z: 3
                                    visible: !clipDelegateCard.isImage && clipDelegateWrapper.itemExpandProgress > 0.01
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: clipboardWindow.s(10)
                                    anchors.topMargin: clipboardWindow.s(10)
                                    anchors.bottomMargin: clipboardWindow.s(10)
                                    anchors.rightMargin: clipDelegateCard.canExpand ? clipboardWindow.s(42) : clipboardWindow.s(10)
                                    clip: true
                                    opacity: Math.max(0.0, (clipDelegateWrapper.itemExpandProgress - 0.15) / 0.85)

                                    Flickable {
                                        id: clipFlickable
                                        anchors.fill: parent
                                        contentWidth: width
                                        contentHeight: clipPreviewText.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height
                                        clip: true

                                        ScrollBar.vertical: ScrollBar {
                                            width: clipboardWindow.s(3)
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { radius: clipboardWindow.s(1.5); color: clipDelegateWrapper.isSelected ? Qt.rgba(0, 0, 0, 0.25) : ThemeBackend.surface2 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: (mouse) => {
                                                clipList.currentIndex = index;
                                                if (mouse.button === Qt.RightButton) {
                                                    clipboardWindow.pinClip(clipDelegateWrapper.clipIdString, index);
                                                } else {
                                                    clipboardWindow.copyClip(clipDelegateWrapper.clipIdString, model.pinned);
                                                }
                                            }
                                        }

                                        Text {
                                            id: clipPreviewText
                                            width: clipFlickable.width
                                            text: clipDelegateWrapper.itemExpandProgress > 0.01 ? ((clipboardWindow.expandedClipId === clipDelegateWrapper.clipIdString && clipboardWindow.expandedClipFullText !== "") ? clipboardWindow.expandedClipFullText : ((model && model.content) ? model.content : "")) : ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: clipboardWindow.s(12)
                                            font.weight: Font.Normal
                                            color: clipDelegateWrapper.isSelected ? ThemeBackend.crust : ThemeBackend.text
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
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
