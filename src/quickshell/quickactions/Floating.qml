import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../"

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: floatingWidget
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "qs-floating-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            focusable: isSidebarVisible && (!isPinned || (typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered))

            anchors {
                top: true; bottom: true; left: true; right: true
            }
            onIsSidebarVisibleChanged: {
                if (isSidebarVisible) SysData.prewarm();
            }

            property string barPosition: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.position !== undefined) ? Config.rawSettings.bar.position : "top"
            property bool barAutohide: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.autohide !== undefined) ? Config.rawSettings.bar.autohide : false

            property real barInset: barAutohide ? 0 : s(48)
            property real topBound: barPosition === "top" ? barInset : 0
            property real bottomBound: floatingWidget.height - (barPosition === "bottom" ? barInset : 0)
            property real leftBound: barPosition === "left" ? barInset : 0
            property real rightBound: floatingWidget.width - (barPosition === "right" ? barInset : 0)

            property real edgeHitSize: Math.max(2, Math.round(s(3)))

            Connections {
                target: (typeof Config !== "undefined") ? Config : null
                function onSettingsLoaded() {
                    if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
                        if (Config.rawSettings.bar.position !== undefined && Config.rawSettings.bar.position !== floatingWidget.barPosition) {
                            floatingWidget.disableAnim = true;
                            floatingWidget.barPosition = Config.rawSettings.bar.position;
                            positionChangeAnimTimer.restart();
                        }
                        if (Config.rawSettings.bar.autohide !== undefined) {
                            floatingWidget.barAutohide = Config.rawSettings.bar.autohide;
                        }
                    }
                }
            }

            Timer {
                id: initAnimTimer
                interval: 500
                running: true
                onTriggered: floatingWidget.disableAnim = false
            }

            Timer {
                id: positionChangeAnimTimer
                interval: 350
                onTriggered: {
                    if (!edgeTransitionTimer.running && !teleportTimer.running) {
                        floatingWidget.disableAnim = false;
                    }
                }
            }

            onBarPositionChanged: {
                floatingWidget.disableAnim = true;
                if (activeEdge === barPosition) {
                    if (barPosition === "top") activeEdge = "bottom";
                    else if (barPosition === "bottom") activeEdge = "top";
                    else if (barPosition === "left") activeEdge = "right";
                    else if (barPosition === "right") activeEdge = "left";
                }
                positionChangeAnimTimer.restart();
            }

            onActiveEdgeChanged: {
                if (!isSidebarVisible && !isPeekVisible) {
                    floatingWidget.disableAnim = true;
                    positionChangeAnimTimer.restart();
                }
            }

            Item {
                id: focusTracker
                focus: true
                onActiveFocusChanged: {
                    if (!activeFocus && !floatingWidget.isPinned && !floatingWidget.moduleKeepAlive()) {
                        floatingWidget.isExpanded = false;
                        hideTimer.restart();
                    }
                }
            }

            property bool isPinned: false
            property bool useGraceTimer: false

            onIsPinnedChanged: {
                if (!isPinned) kickTimer();
            }

            property int hoveredBars: 0

            property var tabModules: [
                "actions/DrawAction.qml",
                "actions/SystemUsage.qml",
                "actions/Timer.qml",
                "actions/Notepad.qml",
            ]

            property int tabCount: Math.max(1, tabModules.length)

            Connections {
                target: FloatingController

                function onSetIndexRequested(screen, index) {
                    if (floatingWidget.matchesScreen(screen)) {
                        floatingWidget.setIndex(index);
                    }
                }

                function onShowSystemUsageRequested(screen) {
                    if (floatingWidget.matchesScreen(screen)) {
                        floatingWidget.showSystemUsage();
                    }
                }
            }

            function matchesScreen(targetScreen) {
                return targetScreen && floatingWidget.screen
                    && (targetScreen === floatingWidget.screen || targetScreen.name === floatingWidget.screen.name);
            }

            function setIndex(index) {
                let newIndex = parseInt(index);
                if (!isNaN(newIndex) && newIndex >= 0 && newIndex < floatingWidget.tabCount) {
                    floatingWidget.activeIndex = newIndex;
                }
            }

            function showSystemUsage() {
                let sysIndex = 1;
                for (let i = 0; i < floatingWidget.tabModules.length; i++) {
                    if (floatingWidget.tabModules[i].indexOf("SystemUsage") !== -1) {
                        sysIndex = i;
                        break;
                    }
                }
                floatingWidget.activeIndex = sysIndex;
                let sideEdge = (floatingWidget.barPosition === "left") ? "right" : "left";
                let centerPos = floatingWidget.height / 2;
                floatingWidget.useGraceTimer = true;
                floatingWidget.showSidebar(sideEdge, centerPos, true);
                hideTimer.restart();
            }

            function childIntercepts(sequenceStr) {
                if (!isExpanded) return false;

                if (typeof moduleRepeater !== "undefined" && activeIndex >= 0 && activeIndex < moduleRepeater.count) {
                    let loader = moduleRepeater.itemAt(activeIndex);
                    
                    if (loader && loader.status === Loader.Ready && loader.item) {
                        if (loader.item.interceptedShortcuts !== undefined) {
                            return loader.item.interceptedShortcuts.includes(sequenceStr);
                        }
                    }
                }
                return false;
            }

            function moduleKeepAlive() {
                if (typeof moduleRepeater === "undefined" || activeIndex < 0 || activeIndex >= moduleRepeater.count)
                    return false;
                let loader = moduleRepeater.itemAt(activeIndex);
                if (loader && loader.status === Loader.Ready && loader.item && loader.item.keepAlive !== undefined)
                    return loader.item.keepAlive === true;
                return false;
            }

            function kickTimer() {
                if (!isPinned) {
                    if (floatingWidget.moduleKeepAlive()) return;
                    if ((typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered) ||
                        (typeof sidebarDragArea !== "undefined" && (sidebarDragArea.containsMouse || sidebarDragArea.pressed)) ||
                        (typeof gridMouseArea !== "undefined" && (gridMouseArea.containsMouse || gridMouseArea.pressed)) ||
                        (typeof peekMouse !== "undefined" && (peekMouse.containsMouse || peekMouse.pressed)) ||
                        (typeof pinMouse !== "undefined" && pinMouse.containsMouse) ||
                        (typeof expandMouse !== "undefined" && expandMouse.containsMouse) ||
                        floatingWidget.hoveredBars > 0) {
                        return;
                    }
                    hideTimer.restart();
                }
            }

            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Tab"); sequence: "Tab"; onActivated: { floatingWidget.activeIndex = (floatingWidget.activeIndex + 1) % floatingWidget.tabCount; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Shift+Tab"); sequence: "Shift+Tab"; onActivated: { floatingWidget.activeIndex = (floatingWidget.activeIndex + (floatingWidget.tabCount - 1)) % floatingWidget.tabCount; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Return"); sequence: "Return"; onActivated: { floatingWidget.isExpanded = !floatingWidget.isExpanded; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Enter"); sequence: "Enter"; onActivated: { floatingWidget.isExpanded = !floatingWidget.isExpanded; floatingWidget.kickTimer(); } }
            
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") && !floatingWidget.childIntercepts("Left")
                sequence: "Left"
                onActivated: { floatingWidget.activeIndex = Math.max(0, floatingWidget.activeIndex - 1); floatingWidget.kickTimer(); } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") && !floatingWidget.childIntercepts("Right")
                sequence: "Right"
                onActivated: { floatingWidget.activeIndex = Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + 1); floatingWidget.kickTimer(); } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") && !floatingWidget.childIntercepts("Up")
                sequence: "Up"
                onActivated: { 
                    let step = floatingWidget.activeEdge === "right" ? 1 : -1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step)); 
                    floatingWidget.kickTimer(); 
                } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") && !floatingWidget.childIntercepts("Down")
                sequence: "Down"
                onActivated: { 
                    let step = floatingWidget.activeEdge === "right" ? -1 : 1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step)); 
                    floatingWidget.kickTimer(); 
                } 
            }

            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Escape")
                sequence: "Escape"
                onActivated: {
                    if (floatingWidget.isExpanded) {
                        floatingWidget.isExpanded = false;
                        floatingWidget.kickTimer();
                    } else if (!floatingWidget.isPinned) {
                        floatingWidget.isSidebarVisible = false;
                        floatingWidget.isPeekVisible = true;
                        peekHideTimer.restart();
                    }
                }
            }

            property real baseScale: Scaler.baseScale
            function s(val) { 
                let res = Scaler.s(val); 
                return isNaN(res) ? val : res; 
            }

            property int activeIndex: 0 
            property bool isExpanded: false 

            property var currentLayoutTemplate: [{x: 0, y: 0, w: 1, h: 1}]

            function evaluateDrag(gpStartX, gpStartY, gpMouseX, gpMouseY) {
                let delta = 0;
                if (activeEdge === "left") delta = gpMouseX - gpStartX;
                else if (activeEdge === "right") delta = gpStartX - gpMouseX;
                else if (activeEdge === "bottom") delta = gpStartY - gpMouseY;
                else if (activeEdge === "top") delta = gpMouseY - gpStartY;

                if (delta > s(30) && !isExpanded) {
                    isExpanded = true;
                } else if (delta < -s(30) && (isExpanded || isSidebarVisible)) {
                    isExpanded = false;
                    if (!isPinned) {
                        isSidebarVisible = false;
                        isPeekVisible = true;
                        peekHideTimer.restart();
                    }
                }
            }
            
            property real containerRadius: s(16)
            property real outerCornerRadius: s(24)

            property real h_in: s(26)
            property real h_ac: s(86)
            property real itemSpacing: s(7)

            property real buttonSize: s(18)
            property real controlAreaHeight: buttonSize * 2 + s(10)

            property real barOffsetY: activeEdge === "left" ? (controlAreaHeight + itemSpacing) : 0

            function getTargetY(idx, activeIdx) {
                let y = 0;
                for (let i = 0; i < idx; i++) {
                    y += (i === activeIdx ? h_ac : h_in) + itemSpacing;
                }
                return y;
            }

            property real baseExpandedWidth: s(340)
            property real baseExpandedExtraLength: s(200)
            property real expandedPadding: s(4)
            
            property real targetExpandedExtraLength: baseExpandedExtraLength

            property real expandedWidth: baseExpandedWidth
            property real expandedExtraLength: baseExpandedExtraLength

            Behavior on expandedWidth { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
            Behavior on expandedExtraLength { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }

            property real expandProgress: isExpanded ? 1.0 : 0.0
            Behavior on expandProgress { 
                enabled: !floatingWidget.disableAnim
                NumberAnimation { duration: 450; easing.type: Easing.OutQuart } 
            }

            property real visibleProgress: isSidebarVisible ? 1.0 : 0.0
            Behavior on visibleProgress { 
                enabled: !floatingWidget.disableAnim
                NumberAnimation { duration: 300; easing.type: Easing.OutExpo } 
            }

            property real currentExtraWidth: (expandedWidth + expandedPadding) * expandProgress
            property real currentExtraLength: expandedExtraLength * expandProgress
            
            property real totalSidebarWidth: sidebarW + currentExtraWidth

            property var activeMaskAABB: {
                if (!floatingWidget.isSidebarVisible) return Qt.rect(0, 0, 0, 0);
                let cw = sidebarContainer.width;
                let ch = sidebarContainer.height;
                let cx = sidebarContainer.x + cw / 2;
                let cy = sidebarContainer.y + ch / 2;

                let innerW = floatingWidget.sidebarW + floatingWidget.currentExtraWidth;
                let innerH = floatingWidget.baseSidebarH + floatingWidget.currentExtraLength;

                let outerR = floatingWidget.outerCornerRadius;
                let buffer = floatingWidget.s(6); 

                let relMinX = -cw / 2 - buffer;
                let relMaxX = -cw / 2 + innerW + buffer;
                let relMinY = -innerH / 2 - outerR - buffer;
                let relMaxY = innerH / 2 + outerR + buffer;

                let rot = floatingWidget.targetRotation;
                let aabbX = 0, aabbY = 0, aabbW = 0, aabbH = 0;
                
                if (rot === 0) {
                    aabbX = cx + relMinX;
                    aabbY = cy + relMinY;
                    aabbW = relMaxX - relMinX;
                    aabbH = relMaxY - relMinY;
                } else if (rot === 180) {
                    aabbX = cx - relMaxX;
                    aabbY = cy - relMaxY;
                    aabbW = relMaxX - relMinX;
                    aabbH = relMaxY - relMinY;
                } else if (rot === -90) {
                    aabbX = cx + relMinY;
                    aabbY = cy - relMaxX;
                    aabbW = relMaxY - relMinY; 
                    aabbH = relMaxX - relMinX;
                } else if (rot === 90) {
                    aabbX = cx - relMaxY;
                    aabbY = cy + relMinX;
                    aabbW = relMaxY - relMinY;
                    aabbH = relMaxX - relMinX;
                } else {
                    aabbW = innerW + buffer * 2; 
                    aabbH = innerH + outerR * 2 + buffer * 2;
                    aabbX = cx - aabbW / 2; 
                    aabbY = cy - aabbH / 2;
                }
                
                return Qt.rect(aabbX, aabbY, aabbW, aabbH);
            }

            mask: Region {
                Region {
                    x: leftBound
                    y: topBound
                    width: floatingWidget.barPosition === "top" ? 0 : (rightBound - leftBound)
                    height: floatingWidget.barPosition === "top" ? 0 : floatingWidget.edgeHitSize
                }
                Region {
                    x: leftBound
                    y: bottomBound - floatingWidget.edgeHitSize
                    width: floatingWidget.barPosition === "bottom" ? 0 : (rightBound - leftBound)
                    height: floatingWidget.barPosition === "bottom" ? 0 : floatingWidget.edgeHitSize
                }
                Region {
                    x: leftBound
                    y: topBound
                    width: floatingWidget.barPosition === "left" ? 0 : floatingWidget.edgeHitSize
                    height: floatingWidget.barPosition === "left" ? 0 : (bottomBound - topBound)
                }
                Region {
                    x: rightBound - floatingWidget.edgeHitSize
                    y: topBound
                    width: floatingWidget.barPosition === "right" ? 0 : floatingWidget.edgeHitSize
                    height: floatingWidget.barPosition === "right" ? 0 : (bottomBound - topBound)
                }

                Region {
                    x: floatingWidget.isPeekVisible ? peekBar.x - floatingWidget.s(8) : 0
                    y: floatingWidget.isPeekVisible ? peekBar.y - floatingWidget.s(8) : 0
                    width: floatingWidget.isPeekVisible ? peekBar.width + floatingWidget.s(16) : 0
                    height: floatingWidget.isPeekVisible ? peekBar.height + floatingWidget.s(16) : 0
                }

                Region {
                    x: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.x : 0
                    y: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.y : 0
                    width: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.width : 0
                    height: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.height : 0
                }
            }

            function safeClampX(pos, margin) {
                let minCenter = leftBound + margin;
                let maxCenter = rightBound - margin;
                if (minCenter <= maxCenter) {
                    return Math.max(minCenter, Math.min(maxCenter, pos));
                } else {
                    return (leftBound + rightBound) / 2;
                }
            }

            function safeClampY(pos, margin) {
                let minCenter = topBound + margin;
                let maxCenter = bottomBound - margin;
                if (minCenter <= maxCenter) {
                    return Math.max(minCenter, Math.min(maxCenter, pos));
                } else {
                    return (topBound + bottomBound) / 2;
                }
            }

            property real targetEdgeMargin: {
                let length = baseSidebarH;
                if (isExpanded) {
                    length += targetExpandedExtraLength;
                }
                return (length / 2) + outerCornerRadius + s(5);
            }

            property real clampedCenterX: safeClampX(currentPos, targetEdgeMargin)
            property real clampedCenterY: safeClampY(currentPos, targetEdgeMargin)

            property string pendingEdge: ""
            property real pendingPos: 0
            property bool pendingWasExpanded: false
            property string pendingMode: "" 

            Timer {
                id: edgeTransitionTimer
                interval: 350
                onTriggered: {
                    floatingWidget.disableAnim = true;
                    floatingWidget.activeEdge = floatingWidget.pendingEdge;
                    floatingWidget.currentPos = floatingWidget.pendingPos;
                    teleportTimer.restart();
                }
            }

            Timer {
                id: teleportTimer
                interval: 32 
                onTriggered: {
                    floatingWidget.disableAnim = false;
                    if (floatingWidget.pendingMode === "sidebar") {
                        floatingWidget.isSidebarVisible = true;
                        floatingWidget.isExpanded = floatingWidget.pendingWasExpanded;
                        floatingWidget.isPeekVisible = false;
                        hideTimer.restart();
                    } else if (floatingWidget.pendingMode === "peek") {
                        floatingWidget.isPeekVisible = true;
                        floatingWidget.isSidebarVisible = false;
                        floatingWidget.isExpanded = false;
                    }
                    floatingWidget.pendingMode = "";
                }
            }

            property bool isSidebarVisible: false
            property bool isPeekVisible: false
            property bool disableAnim: true
            
            property string activeEdge: barPosition === "left" ? "right" : "left"
            property real currentPos: (activeEdge === "left" || activeEdge === "right") ? (floatingWidget.height / 2) : (floatingWidget.width / 2)

            property real baseSidebarH: {
                let count = floatingWidget.tabCount;
                let activeTabH = count > 0 ? floatingWidget.h_ac : 0;
                let inactiveTabsH = Math.max(0, count - 1) * floatingWidget.h_in;
                let tabsSpacing = Math.max(0, count - 1) * floatingWidget.itemSpacing;
                
                let controlSpacing = count > 0 ? floatingWidget.itemSpacing : 0;
                let margins = floatingWidget.s(12); 
                
                return floatingWidget.controlAreaHeight + controlSpacing + activeTabH + inactiveTabsH + tabsSpacing + margins;
            }

            property real sidebarW: s(31)
            
            property real sidebarTargetX: {
                if (activeEdge === "left") return leftBound;
                if (activeEdge === "right") return rightBound - sidebarW;
                if (activeEdge === "bottom" || activeEdge === "top") return clampedCenterX - sidebarW / 2;
                return 0;
            }

            property real sidebarTargetY: {
                if (activeEdge === "left" || activeEdge === "right") return clampedCenterY - baseSidebarH / 2;
                if (activeEdge === "bottom") return bottomBound - sidebarW / 2 - baseSidebarH / 2; 
                if (activeEdge === "top") return topBound + sidebarW / 2 - baseSidebarH / 2;
                return 0;
            }

            property real targetRotation: {
                if (activeEdge === "left") return 0;
                if (activeEdge === "right") return 180;
                if (activeEdge === "bottom") return -90;
                if (activeEdge === "top") return 90;
                return 0;
            }

            function showPeek(edge, pos) {
                SysData.prewarm();
                if (isPinned || isSidebarVisible || pendingMode === "sidebar" || edge === barPosition) return;

                if (activeEdge !== edge) {
                    if (isPeekVisible || edgeTransitionTimer.running) {
                        pendingEdge = edge;
                        pendingPos = pos;
                        pendingMode = "peek";
                        
                        if (!edgeTransitionTimer.running) {
                            isPeekVisible = false;
                            edgeTransitionTimer.restart();
                        }
                    } else {
                        disableAnim = true;
                        activeEdge = edge;
                        currentPos = pos;
                        pendingMode = "peek";
                        teleportTimer.restart();
                    }
                    return;
                } else {
                    if (edgeTransitionTimer.running) {
                        edgeTransitionTimer.stop();
                        pendingMode = "";
                    }
                }

                currentPos = pos;
                isPeekVisible = true;
                peekHideTimer.stop();
            }

            function showSidebar(edge, pos, expand) {
                SysData.prewarm();
                if (isPinned || edge === barPosition) return;
                let shouldExpand = (typeof expand === "boolean") ? expand : isExpanded;

                if (activeEdge !== edge) {
                    if (isSidebarVisible || isExpanded || edgeTransitionTimer.running) {
                        pendingEdge = edge;
                        pendingPos = pos;
                        pendingMode = "sidebar";
                        
                        if (!edgeTransitionTimer.running) {
                            pendingWasExpanded = shouldExpand;
                            isExpanded = false;
                            isSidebarVisible = false;
                            isPeekVisible = false;
                            edgeTransitionTimer.restart();
                        }
                    } else {
                        disableAnim = true;
                        activeEdge = edge;
                        currentPos = pos;
                        pendingMode = "sidebar";
                        pendingWasExpanded = shouldExpand;
                        teleportTimer.restart(); 
                    }
                    return; 
                } else {
                    if (edgeTransitionTimer.running) {
                        edgeTransitionTimer.stop();
                        if (pendingMode === "sidebar") {
                            isExpanded = pendingWasExpanded;
                        }
                        pendingMode = "";
                    }
                }

                currentPos = pos;
                isSidebarVisible = true;
                if (typeof expand === "boolean") {
                    isExpanded = expand;
                }
                isPeekVisible = false;
                hideTimer.restart();
            }

            Timer {
                id: peekHideTimer
                interval: 50
                onTriggered: {
                    if (typeof peekMouse !== "undefined" && peekMouse.pressed) {
                        peekHideTimer.restart();
                        return;
                    }
                    if (!peekMouse.containsMouse && 
                        !leftEdge.containsMouse && !rightEdge.containsMouse && !topEdge.containsMouse && !bottomEdge.containsMouse) {
                        floatingWidget.isPeekVisible = false;
                    }
                }
            }

            Timer {
                id: hideTimer
                interval: floatingWidget.useGraceTimer ? 3000 : 800
                onTriggered: {
                    if (floatingWidget.isPinned) return;
                    if (floatingWidget.moduleKeepAlive()) {
                        hideTimer.restart();
                        return;
                    }

                    if ((typeof sidebarDragArea !== "undefined" && sidebarDragArea.pressed) || 
                        (typeof peekMouse !== "undefined" && peekMouse.pressed) ||
                        (typeof gridMouseArea !== "undefined" && gridMouseArea.pressed)) {
                        hideTimer.restart();
                        return;
                    }

                    floatingWidget.isExpanded = false;
                    floatingWidget.isSidebarVisible = false;
                    floatingWidget.useGraceTimer = false;
                }
            }

            Timer {
                id: peekShowTimer
                interval: 300
                property string pendingShowEdge: ""
                property real pendingShowPos: 0
                onTriggered: {
                    if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") {
                        floatingWidget.showSidebar(pendingShowEdge, pendingShowPos);
                    } else {
                        floatingWidget.showPeek(pendingShowEdge, pendingShowPos);
                    }
                }
            }

            Item {
                id: mainHitArea 
                anchors.fill: parent

                MouseArea {
                    id: topEdge
                    x: leftBound
                    y: topBound
                    width: rightBound - leftBound
                    height: floatingWidget.edgeHitSize
                    hoverEnabled: true
                    enabled: floatingWidget.barPosition !== "top"
                    onEntered: { 
                        SysData.prewarm();
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("top", mouseX + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("top", mouseX + x);
                        } else {
                            peekShowTimer.pendingShowEdge = "top";
                            peekShowTimer.pendingShowPos = mouseX + x;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("top", mouse.x + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("top", mouse.x + x);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.x + x;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }

                MouseArea {
                    id: leftEdge
                    x: leftBound
                    y: topBound
                    width: floatingWidget.edgeHitSize
                    height: bottomBound - topBound
                    hoverEnabled: true
                    enabled: floatingWidget.barPosition !== "left"
                    onEntered: { 
                        SysData.prewarm();
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("left", mouseY + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("left", mouseY + y);
                        } else {
                            peekShowTimer.pendingShowEdge = "left";
                            peekShowTimer.pendingShowPos = mouseY + y;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("left", mouse.y + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("left", mouse.y + y);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.y + y;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }

                MouseArea {
                    id: rightEdge
                    x: rightBound - floatingWidget.edgeHitSize
                    y: topBound
                    width: floatingWidget.edgeHitSize
                    height: bottomBound - topBound
                    hoverEnabled: true
                    enabled: floatingWidget.barPosition !== "right"
                    onEntered: { 
                        SysData.prewarm();
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("right", mouseY + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("right", mouseY + y);
                        } else {
                            peekShowTimer.pendingShowEdge = "right";
                            peekShowTimer.pendingShowPos = mouseY + y;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("right", mouse.y + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("right", mouse.y + y);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.y + y;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }

                MouseArea {
                    id: bottomEdge
                    x: leftBound
                    y: bottomBound - floatingWidget.edgeHitSize
                    width: rightBound - leftBound
                    height: floatingWidget.edgeHitSize
                    hoverEnabled: true
                    enabled: floatingWidget.barPosition !== "bottom"
                    onEntered: { 
                        SysData.prewarm();
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("bottom", mouseX + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("bottom", mouseX + x);
                        } else {
                            peekShowTimer.pendingShowEdge = "bottom";
                            peekShowTimer.pendingShowPos = mouseX + x;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("bottom", mouse.x + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("bottom", mouse.x + x);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.x + x;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }
            }

            property real peekBarLength: Math.max(floatingWidget.s(20), (floatingWidget.baseSidebarH - floatingWidget.s(20)) * 0.75)

            Rectangle {
                id: peekBar
                width: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? peekBarLength : floatingWidget.s(11)
                height: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? floatingWidget.s(11) : peekBarLength
                radius: Math.min(floatingWidget.containerRadius, Math.min(width, height) / 2)
                
                color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 1.0)
                border.width: 0
                
                opacity: (floatingWidget.isPeekVisible && !floatingWidget.isSidebarVisible) ? (peekMouse.containsMouse || peekMouse.pressed ? 1.0 : 0.6) : 0.0
                scale: floatingWidget.isPeekVisible ? 1.0 : 0.6
                
                Behavior on opacity { NumberAnimation { duration: 250 } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                property real visualDragOffset: {
                    if (!peekMouse.pressed) return 0;
                    return Math.max(-floatingWidget.s(15), Math.min(peekMouse.currentDragDelta, floatingWidget.s(15))); 
                }

                x: {
                    let offscreen = 0, visibleX = 0;
                    if (floatingWidget.activeEdge === "left") {
                        offscreen = leftBound - width - floatingWidget.s(10);
                        visibleX = leftBound + floatingWidget.s(4); 
                        return (floatingWidget.isPeekVisible ? visibleX : offscreen) + visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "right") {
                        offscreen = rightBound + floatingWidget.s(10);
                        visibleX = rightBound - width - floatingWidget.s(4); 
                        return (floatingWidget.isPeekVisible ? visibleX : offscreen) - visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") return clampedCenterX - width / 2;
                    return 0;
                }

                y: {
                    let offscreen = 0, visibleY = 0;
                    if (floatingWidget.activeEdge === "bottom") {
                        offscreen = bottomBound + floatingWidget.s(10);
                        visibleY = bottomBound - height - floatingWidget.s(4); 
                        return (floatingWidget.isPeekVisible ? visibleY : offscreen) - visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "top") {
                        offscreen = topBound - height - floatingWidget.s(10);
                        visibleY = topBound + floatingWidget.s(4); 
                        return (floatingWidget.isPeekVisible ? visibleY : offscreen) + visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") return clampedCenterY - height / 2;
                    return 0;
                }

                Behavior on x { enabled: !floatingWidget.disableAnim && !peekMouse.pressed && floatingWidget.isPeekVisible; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                Behavior on y { enabled: !floatingWidget.disableAnim && !peekMouse.pressed && floatingWidget.isPeekVisible; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                Rectangle {
                    anchors.centerIn: parent
                    width: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? floatingWidget.s(20) : floatingWidget.s(3.5)
                    height: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? floatingWidget.s(3.5) : floatingWidget.s(20)
                    radius: Math.min(ThemeBackend.borderRadius, Math.min(width, height) / 2)
                    color: Qt.darker(ThemeBackend.mauve, 1.8)
                }

                MouseArea {
                    id: peekMouse
                    anchors.fill: parent
                    anchors.margins: -floatingWidget.s(15) 
                    hoverEnabled: true
                    enabled: floatingWidget.isPeekVisible || pressed
                    
                    property real startGlobalX: 0
                    property real startGlobalY: 0
                    property real currentDragDelta: 0

                    onEntered: { floatingWidget.isPeekVisible = true; peekHideTimer.stop(); }
                    onExited: { if (!pressed) peekHideTimer.restart(); }
                    
                    onPressed: mouse => { 
                        let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                        startGlobalX = gp.x; 
                        startGlobalY = gp.y;
                        currentDragDelta = 0;
                        floatingWidget.useGraceTimer = true;
                    }
                    
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        
                        let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                        let delta = 0;
                        
                        if (floatingWidget.activeEdge === "left") delta = gp.x - startGlobalX;
                        else if (floatingWidget.activeEdge === "right") delta = startGlobalX - gp.x;
                        else if (floatingWidget.activeEdge === "bottom") delta = startGlobalY - gp.y;
                        else if (floatingWidget.activeEdge === "top") delta = gp.y - startGlobalY;

                        currentDragDelta = delta;

                        if (delta > floatingWidget.s(15) && !floatingWidget.isExpanded) {
                            floatingWidget.showSidebar(floatingWidget.activeEdge, floatingWidget.currentPos);
                            floatingWidget.isExpanded = true;
                        } else if (delta < -floatingWidget.s(10) && floatingWidget.isPeekVisible) {
                            floatingWidget.isPeekVisible = false;
                        }
                    }
                    
                    onReleased: { 
                        currentDragDelta = 0;
                        peekHideTimer.restart(); 
                    }
                    
                    onClicked: floatingWidget.showSidebar(floatingWidget.activeEdge, floatingWidget.currentPos)
                }
            }

            Item {
                id: sidebarContainer
                
                width: floatingWidget.sidebarW
                height: floatingWidget.baseSidebarH

                transformOrigin: Item.Center
                rotation: floatingWidget.targetRotation
                Behavior on rotation { enabled: !floatingWidget.disableAnim && floatingWidget.isSidebarVisible; NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                x: {
                    if (floatingWidget.isSidebarVisible) return floatingWidget.sidebarTargetX;
                    if (floatingWidget.activeEdge === "left") return leftBound - width - floatingWidget.s(20);
                    if (floatingWidget.activeEdge === "right") return rightBound + floatingWidget.s(20);
                    return floatingWidget.sidebarTargetX;
                }

                y: {
                    if (floatingWidget.isSidebarVisible) return floatingWidget.sidebarTargetY;
                    if (floatingWidget.activeEdge === "bottom") return bottomBound + floatingWidget.s(10) - floatingWidget.baseSidebarH / 2 + floatingWidget.sidebarW / 2;
                    if (floatingWidget.activeEdge === "top") return topBound - floatingWidget.baseSidebarH - floatingWidget.s(20);
                    return floatingWidget.sidebarTargetY; 
                }

                Behavior on x { enabled: !floatingWidget.disableAnim && (floatingWidget.isSidebarVisible || floatingWidget.visibleProgress > 0); NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                Behavior on y { enabled: !floatingWidget.disableAnim && (floatingWidget.isSidebarVisible || floatingWidget.visibleProgress > 0); NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                Item {
                    id: morphOrigin
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    
                    width: floatingWidget.sidebarW + floatingWidget.currentExtraWidth
                    height: floatingWidget.baseSidebarH + floatingWidget.currentExtraLength

                    HoverHandler {
                        id: mainHoverTracker
                        onHoveredChanged: {
                            if (hovered) {
                                floatingWidget.useGraceTimer = false;
                                hideTimer.stop();
                            } else {
                                floatingWidget.kickTimer();
                            }
                        }
                    }

                    Shape {
                        visible: floatingWidget.outerCornerRadius > 0.5
                        x: 0
                        y: -floatingWidget.outerCornerRadius
                        width: floatingWidget.outerCornerRadius
                        height: floatingWidget.outerCornerRadius
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.95)
                            strokeColor: "transparent"
                            startX: 0
                            startY: 0
                            PathLine { x: 0; y: floatingWidget.outerCornerRadius }
                            PathLine { x: floatingWidget.outerCornerRadius; y: floatingWidget.outerCornerRadius }
                            PathArc {
                                x: 0
                                y: 0
                                radiusX: floatingWidget.outerCornerRadius
                                radiusY: floatingWidget.outerCornerRadius
                                direction: PathArc.Clockwise
                            }
                        }
                    }

                    Shape {
                        visible: floatingWidget.outerCornerRadius > 0.5
                        x: 0
                        y: parent.height
                        width: floatingWidget.outerCornerRadius
                        height: floatingWidget.outerCornerRadius
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.95)
                            strokeColor: "transparent"
                            startX: 0
                            startY: floatingWidget.outerCornerRadius
                            PathLine { x: 0; y: 0 }
                            PathLine { x: floatingWidget.outerCornerRadius; y: 0 }
                            PathArc {
                                x: 0
                                y: floatingWidget.outerCornerRadius
                                radiusX: floatingWidget.outerCornerRadius
                                radiusY: floatingWidget.outerCornerRadius
                                direction: PathArc.Counterclockwise
                            }
                        }
                    }

                    Rectangle {
                        id: morphingBackground
                        x: 0
                        y: 0
                        width: parent.width
                        height: parent.height
                        radius: floatingWidget.containerRadius
                        topLeftRadius: 0
                        bottomLeftRadius: 0
                        topRightRadius: floatingWidget.containerRadius
                        bottomRightRadius: floatingWidget.containerRadius
                        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.95) 
                        border.width: 0

                        MouseArea {
                            id: sidebarDragArea
                            anchors.fill: parent
                            anchors.margins: floatingWidget.isExpanded ? -floatingWidget.s(20) : -floatingWidget.s(4) 
                            hoverEnabled: true
                            enabled: floatingWidget.isSidebarVisible 
                            
                            property real startGlobalX: 0
                            property real startGlobalY: 0

                            onEntered: hideTimer.stop()
                            onExited: { if (!pressed && !gridMouseArea.containsMouse) floatingWidget.kickTimer(); }
                            onPressed: mouse => { 
                                let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                startGlobalX = gp.x; 
                                startGlobalY = gp.y; 
                                floatingWidget.useGraceTimer = true;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                            }
                            onReleased: { if (!containsMouse) floatingWidget.kickTimer(); }
                        }
                    }

                    Item {
                        id: expandedContainer
                        x: floatingWidget.sidebarW 
                        y: 0
                        height: parent.height
                        width: floatingWidget.currentExtraWidth
                        opacity: floatingWidget.expandProgress
                        clip: true 

                        component EmptyBlock : Rectangle {
                            radius: Math.min(floatingWidget.s(10), Math.min(width, height) / 2)
                            color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.05)
                            border.width: 0
                            border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)
                            clip: true
                        }

                        Item {
                            anchors.fill: parent
                            anchors.topMargin: floatingWidget.s(4)
                            anchors.bottomMargin: floatingWidget.s(4)
                            anchors.leftMargin: floatingWidget.s(4)
                            anchors.rightMargin: floatingWidget.s(4)
                            visible: floatingWidget.expandProgress > 0.01

                            Item {
                                anchors.centerIn: parent
                                width: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? parent.height : parent.width
                                height: (floatingWidget.activeEdge === "bottom" || floatingWidget.activeEdge === "top") ? parent.width : parent.height
                                rotation: floatingWidget.activeEdge === "right" ? 180 : (floatingWidget.activeEdge === "bottom" ? 90 : (floatingWidget.activeEdge === "top" ? -90 : 0))

                                property real sp: floatingWidget.s(6) 
                                property real cw: Math.max(0, width) 
                                property real ch: Math.max(0, height) 
                                
                                Repeater {
                                    model: floatingWidget.currentLayoutTemplate
                                    delegate: EmptyBlock {
                                        x: (modelData.x * parent.cw) + (modelData.x > 0 ? parent.sp / 2 : 0)
                                        y: (modelData.y * parent.ch) + (modelData.y > 0 ? parent.sp / 2 : 0)
                                        width: (modelData.w * parent.cw) - ((modelData.x > 0 ? parent.sp / 2 : 0) + ((modelData.x + modelData.w) < 0.99 ? parent.sp / 2 : 0))
                                        height: (modelData.h * parent.ch) - ((modelData.y > 0 ? parent.sp / 2 : 0) + ((modelData.y + modelData.h) < 0.99 ? parent.sp / 2 : 0))
                                    }
                                }
                            }
                        }

                        Repeater {
                            id: moduleRepeater
                            model: floatingWidget.tabModules

                            delegate: Loader {
                                id: contentLoader
                                z: 10
                                anchors.fill: parent
                                anchors.topMargin: floatingWidget.s(4)
                                anchors.bottomMargin: floatingWidget.s(4)
                                anchors.leftMargin: floatingWidget.s(4)
                                anchors.rightMargin: floatingWidget.s(4)

                                visible: index === floatingWidget.activeIndex && floatingWidget.expandProgress > 0.01
                                source: modelData
                                asynchronous: false

                                property var scaleFunc: floatingWidget.s
                                property var mochaColors: ThemeBackend 
                                property string activeEdge: floatingWidget.activeEdge 

                                property bool isCurrentTarget: index === floatingWidget.activeIndex
                                property real modWidth: (status === Loader.Ready && item && item.preferredWidth !== undefined) ? item.preferredWidth : floatingWidget.baseExpandedWidth
                                property real modExt: (status === Loader.Ready && item && item.preferredExtraLength !== undefined) ? item.preferredExtraLength : floatingWidget.baseExpandedExtraLength
                                
                                property var modLayout: {
                                    if (status === Loader.Ready && item && item.requestedLayoutTemplate !== undefined) {
                                        let req = item.requestedLayoutTemplate;
                                        if (typeof req === "number") {
                                            if (req === 0) return [ {x:0, y:0, w:0.5, h:0.5}, {x:0.5, y:0, w:0.5, h:0.5}, {x:0, y:0.5, w:0.5, h:0.5}, {x:0.5, y:0.5, w:0.5, h:0.5} ];
                                            else return [ {x:0, y:0, w:1, h:1} ]; 
                                        }
                                        return req; 
                                    }
                                    return [ {x:0, y:0, w:1, h:1} ];
                                }

                                function updateSizes() {
                                    if (isCurrentTarget) {
                                        floatingWidget.targetExpandedExtraLength = modExt;
                                        floatingWidget.expandedWidth = modWidth;
                                        floatingWidget.expandedExtraLength = modExt;
                                        floatingWidget.currentLayoutTemplate = modLayout;
                                    }
                                }

                                onLoaded: updateSizes()
                                onIsCurrentTargetChanged: updateSizes()
                                onModWidthChanged: updateSizes()
                                onModExtChanged: updateSizes()
                                onModLayoutChanged: updateSizes()
                                Component.onCompleted: updateSizes()
                            }
                        }

                        MouseArea {
                            id: gridMouseArea
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton 
                            hoverEnabled: true
                            
                            onEntered: hideTimer.stop()
                            onExited: { if (!sidebarDragArea.containsMouse) floatingWidget.kickTimer(); }
                            onWheel: wheel => {
                                let step = 0;
                                if (wheel.angleDelta.y > 0) step = (floatingWidget.activeEdge === "right" || floatingWidget.activeEdge === "top") ? 1 : -1;
                                else if (wheel.angleDelta.y < 0) step = (floatingWidget.activeEdge === "right" || floatingWidget.activeEdge === "top") ? -1 : 1;
                                
                                if (step !== 0) {
                                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step));
                                }
                            }
                        }
                    }

                    Item {
                        id: staticContentWrapper
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter 
                        width: floatingWidget.sidebarW
                        height: floatingWidget.baseSidebarH

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: floatingWidget.s(4) + 1
                            anchors.rightMargin: floatingWidget.s(4) + 1
                            anchors.topMargin: floatingWidget.s(6)
                            anchors.bottomMargin: floatingWidget.s(6)

                            Item {
                                id: controlArea
                                width: parent.width
                                height: floatingWidget.controlAreaHeight
                                x: 0
                                y: floatingWidget.activeEdge === "left"
                                    ? 0
                                    : floatingWidget.getTargetY(floatingWidget.tabCount, floatingWidget.activeIndex)

                                Behavior on y {
                                    enabled: !floatingWidget.disableAnim
                                    NumberAnimation { duration: 350; easing.type: Easing.OutExpo }
                                }

                                Item {
                                    id: expandButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    x: (parent.width - width) / 2
                                    y: floatingWidget.activeEdge === "left"
                                        ? floatingWidget.s(4)
                                        : parent.height - height - floatingWidget.s(4)

                                    rotation: floatingWidget.isExpanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                                    Item {
                                        anchors.fill: parent
                                        
                                        property color iconColor: floatingWidget.isExpanded ? ThemeBackend.mauve : 
                                                                  (expandMouse.pressed ? Qt.darker(ThemeBackend.mauve, 1.2) : 
                                                                  (expandMouse.containsMouse ? ThemeBackend.mauve : 
                                                                  Qt.tint(ThemeBackend.base, Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.3))))
                                                                  
                                        property real pivotX: parent.width / 2 - floatingWidget.s(3)

                                        Rectangle {
                                            width: floatingWidget.s(4)
                                            height: floatingWidget.s(4)
                                            radius: width / 2
                                            color: parent.iconColor
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: parent.pivotX - (width / 2)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }

                                        Rectangle {
                                            x: parent.pivotX
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: floatingWidget.s(10)
                                            height: floatingWidget.s(3.5)
                                            radius: height / 2
                                            transformOrigin: Item.Left
                                            rotation: 42
                                            color: parent.iconColor
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }

                                        Rectangle {
                                            x: parent.pivotX
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: floatingWidget.s(10)
                                            height: floatingWidget.s(3.5)
                                            radius: height / 2
                                            transformOrigin: Item.Left
                                            rotation: -42
                                            color: parent.iconColor
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }

                                    MouseArea {
                                        id: expandMouse
                                        anchors.fill: parent
                                        hoverEnabled: true

                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false

                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()

                                        onPressed: mouse => {
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x;
                                            startGlobalY = gp.y;
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            if (deltaX > 5 || deltaY > 5) isDragging = true;
                                            floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                floatingWidget.isExpanded = !floatingWidget.isExpanded;
                                                floatingWidget.kickTimer();
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: pinButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    radius: width / 2
                                    x: (parent.width - width) / 2
                                    y: floatingWidget.activeEdge === "left"
                                        ? expandButton.y + expandButton.height + floatingWidget.s(6)
                                        : expandButton.y - height - floatingWidget.s(6)

                                    color: floatingWidget.isPinned
                                        ? ThemeBackend.mauve
                                        : (pinMouse.pressed
                                            ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.4)
                                            : (pinMouse.containsMouse
                                                ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.25)
                                                : "transparent"))
                                    border.width: floatingWidget.s(2)
                                    border.color: floatingWidget.isPinned
                                        ? ThemeBackend.mauve
                                        : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.2)
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    MouseArea {
                                        id: pinMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false

                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()
                                        
                                        onPressed: mouse => { 
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x; 
                                            startGlobalY = gp.y; 
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            if (deltaX > 5 || deltaY > 5) isDragging = true;
                                            floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                floatingWidget.isPinned = !floatingWidget.isPinned;
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: activeHighlight
                                x: 0
                                width: parent.width
                                z: 0
                                radius: Math.min(ThemeBackend.borderRadius, width / 2) 
                                color: ThemeBackend.mauve

                                property int prevIdx: 0
                                property int curIdx: floatingWidget.activeIndex

                                onCurIdxChanged: {
                                    if (curIdx > prevIdx) { bottomAnim.duration = 200; topAnim.duration = 350; } 
                                    else if (curIdx < prevIdx) { topAnim.duration = 200; bottomAnim.duration = 350; }
                                    prevIdx = curIdx;
                                }

                                property real targetTop: floatingWidget.barOffsetY + floatingWidget.getTargetY(curIdx, curIdx)
                                property real targetBottom: targetTop + floatingWidget.h_ac

                                property real actualTop: targetTop
                                property real actualBottom: targetBottom

                                Behavior on actualTop { enabled: !floatingWidget.disableAnim; NumberAnimation { id: topAnim; duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on actualBottom { enabled: !floatingWidget.disableAnim; NumberAnimation { id: bottomAnim; duration: 250; easing.type: Easing.OutExpo } }

                                y: actualTop
                                height: actualBottom - actualTop
                            }

                            Repeater {
                                model: floatingWidget.tabCount
                                delegate: Rectangle {
                                    id: barPill
                                    property bool isActive: floatingWidget.activeIndex === index
                                    property bool isHovered: barMouse.containsMouse
                                    property bool isPressed: barMouse.pressed
                                    
                                    x: 0
                                    width: parent.width
                                    radius: Math.min(ThemeBackend.borderRadius, width / 2) 
                                    z: 1 

                                    y: floatingWidget.barOffsetY + floatingWidget.getTargetY(index, floatingWidget.activeIndex)
                                    Behavior on y { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                                    height: isActive ? floatingWidget.h_ac : floatingWidget.h_in
                                    Behavior on height { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                                    color: isActive ? "transparent" : (isPressed ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.4) : (isHovered ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.25) : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.15)))
                                    Behavior on color { ColorAnimation { duration: 250 } }

                                    scale: isActive ? 1.0 : (isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                    MouseArea {
                                        id: barMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false
                                        
                                        onEntered: { floatingWidget.hoveredBars++; hideTimer.stop(); }
                                        onExited: { floatingWidget.hoveredBars = Math.max(0, floatingWidget.hoveredBars - 1); floatingWidget.kickTimer(); }
                                        
                                        onPressed: mouse => { 
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x; 
                                            startGlobalY = gp.y; 
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            if (deltaX > 5 || deltaY > 5) isDragging = true;
                                            floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                if (!barPill.isActive) floatingWidget.activeIndex = index; 
                                                else floatingWidget.isExpanded = !floatingWidget.isExpanded;
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
