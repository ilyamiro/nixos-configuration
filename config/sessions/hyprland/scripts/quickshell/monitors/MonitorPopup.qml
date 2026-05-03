import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item
    function s(val) { 
        return scaler.s(val); 
    }

    // Custom File Logger
    function debugLog(msg) {
        let safeMsg = msg.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", "echo '" + safeMsg + "' >> /tmp/monitor_popup.log"]);
    }
    
    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue
    readonly property color pink: _theme.pink
    readonly property color teal: _theme.teal
    readonly property color yellow: _theme.yellow
    readonly property color peach: _theme.peach
    readonly property color green: _theme.green
    readonly property color red: _theme.red
    readonly property color sapphire: _theme.sapphire

    // -------------------------------------------------------------------------
    // STATE & MATH
    // -------------------------------------------------------------------------
    property int activeEditIndex: 0
    property int activeFocusIndex: 0 // 0: Res, 1: Clock, 2: Frame, 3: Apply
    property real uiScale: 0.10 
    
    // Wayland Absolute Anchor tracking
    property int originalLayoutOriginX: 0
    property int originalLayoutOriginY: 0

    ListModel {
        id: monitorsModel
    }
    
    property var resList: [
        {w: 3840, h: 2160, l: "4K",   accent: window.pink}, 
        {w: 2560, h: 1440, l: "QHD",  accent: window.mauve},
        {w: 1920, h: 1080, l: "FHD",  accent: window.blue},
        {w: 1600, h: 900,  l: "HD+",  accent: window.teal}, 
        {w: 1366, h: 768,  l: "WXGA", accent: window.yellow}, 
        {w: 1280, h: 720,  l: "HD",   accent: window.peach}, 
        {w: 1024, h: 768,  l: "XGA",  accent: window.green}, 
        {w: 800,  h: 600,  l: "SVGA", accent: window.red} 
    ]

    property color selectedResAccent: window.mauve
    property color selectedRateAccent: window.blue

    property int currentTransform: monitorsModel.count > 0 ? monitorsModel.get(window.activeEditIndex).transform : 0
    property bool currentIsPortrait: currentTransform === 1 || currentTransform === 3

    property real currentSimW: {
        if (monitorsModel.count === 0) return 1920;
        let mon = monitorsModel.get(window.activeEditIndex);
        return currentIsPortrait ? mon.resH : mon.resW;
    }
    property real currentSimH: {
        if (monitorsModel.count === 0) return 1080;
        let mon = monitorsModel.get(window.activeEditIndex);
        return currentIsPortrait ? mon.resW : mon.resH;
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0
        to: Math.PI * 2
        duration: 90000
        loops: Animation.Infinite
        running: true
    }
    
    // -------------------------------------------------------------------------
    // KEYBOARD NAVIGATION LOGIC
    // -------------------------------------------------------------------------
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Tab) {
            if (event.modifiers & Qt.ControlModifier) {
                if (monitorsModel.count > 1) {
                    window.activeEditIndex = (window.activeEditIndex + 1) % monitorsModel.count;
                }
            } else {
                window.activeFocusIndex = (window.activeFocusIndex + 1) % 4;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Backtab) {
            if (event.modifiers & Qt.ControlModifier) {
                if (monitorsModel.count > 1) {
                    window.activeEditIndex = (window.activeEditIndex - 1 + monitorsModel.count) % monitorsModel.count;
                }
            } else {
                window.activeFocusIndex = (window.activeFocusIndex - 1 + 4) % 4;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            handleArrowKey("Left"); event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            handleArrowKey("Right"); event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            handleArrowKey("Up"); event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            handleArrowKey("Down"); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (activeFocusIndex === 3) {
                window.applyPressed = true;
                window.triggerApply();
            }
            event.accepted = true;
        }
    }
    
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            window.applyPressed = false;
        }
    }

    function handleArrowKey(dir) {
        if (monitorsModel.count === 0) return;
        
        if (activeFocusIndex === 0) {
            let activeMon = monitorsModel.get(window.activeEditIndex);
            let idx = 2; // Default FHD
            for (let i = 0; i < window.resList.length; i++) {
                if (window.resList[i].w === activeMon.resW && window.resList[i].h === activeMon.resH) {
                    idx = i; break;
                }
            }
            
            if (dir === "Left" && idx % 2 !== 0) idx--;
            else if (dir === "Right" && idx % 2 === 0 && idx < 7) idx++;
            else if (dir === "Up" && idx >= 2) idx -= 2;
            else if (dir === "Down" && idx <= 5) idx += 2;

            window.selectedResAccent = window.resList[idx].accent;
            monitorsModel.setProperty(window.activeEditIndex, "resW", window.resList[idx].w);
            monitorsModel.setProperty(window.activeEditIndex, "resH", window.resList[idx].h);
            delayedLayoutUpdate.restart();
            
        } else if (activeFocusIndex === 1) {
            let t = monitorsModel.get(window.activeEditIndex).transform;
            if (dir === "Up") t = 0;
            else if (dir === "Right") t = 1;
            else if (dir === "Down") t = 2;
            else if (dir === "Left") t = 3;
            monitorsModel.setProperty(window.activeEditIndex, "transform", t);
            delayedLayoutUpdate.restart();
            
        } else if (activeFocusIndex === 2) {
            let cIdx = sliderContainer.currentIndex;
            if (dir === "Left" && cIdx > 0) cIdx--;
            else if (dir === "Right" && cIdx < sliderContainer.rates.length - 1) cIdx++;
            sliderContainer.updateSelectionVisual(cIdx);
        }
    }

    // -------------------------------------------------------------------------
    // FLUID STARTUP ANIMATIONS 
    // -------------------------------------------------------------------------
    property real introProgress: 0.0
    property real monitorScale: 0.85
    property real uiYOffset: window.s(25)
    property real screenLight: 0.0

    Component.onCompleted: startupAnim.start()

    ParallelAnimation {
        id: startupAnim
        NumberAnimation { target: window; property: "introProgress"; from: 0.0; to: 1.0; duration: 900; easing.type: Easing.OutQuint }
        NumberAnimation { target: window; property: "monitorScale"; from: 0.85; to: 1.0; duration: 1200; easing.type: Easing.OutQuint }
        NumberAnimation { target: window; property: "uiYOffset"; from: window.s(25); to: 0; duration: 1800; easing.type: Easing.OutQuint }
        NumberAnimation { target: window; property: "screenLight"; from: 0.0; to: 1.0; duration: 1500; easing.type: Easing.InOutQuad }
    }
    property bool applyHovered: false
    property bool applyPressed: false

    onActiveEditIndexChanged: {
        menuTransitionAnim.restart();
    }

    // -------------------------------------------------------------------------
    // MATHEMATICAL PERIMETER GLUE (Virtual Coordinates - Do not scale)
    // -------------------------------------------------------------------------
    function isOverlapping(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function isOverlappingAny(x, y, w, h, skipIdx) {
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === skipIdx) continue;
            let m = monitorsModel.get(i);
            let isP = m.transform === 1 || m.transform === 3;
            let mW = ((isP ? m.resH : m.resW) / m.sysScale) * window.uiScale;
            let mH = ((isP ? m.resW : m.resH) / m.sysScale) * window.uiScale;
            if (isOverlapping(x, y, w, h, m.uiX, m.uiY, mW, mH)) return true;
        }
        return false;
    }

    function getPerimeterSnap(pX, pY, sX, sY, sW, sH, mW, mH, snapT) {
        let edges = [
            { x1: sX - mW, x2: sX + sW, y1: sY - mH, y2: sY - mH }, // Top Edge
            { x1: sX - mW, x2: sX + sW, y1: sY + sH, y2: sY + sH }, // Bottom Edge
            { x1: sX - mW, x2: sX - mW, y1: sY - mH, y2: sY + sH }, // Left Edge
            { x1: sX + sW, x2: sX + sW, y1: sY - mH, y2: sY + sH }  // Right Edge
        ];

        let bestX = pX;
        let bestY = pY;
        let minDist = 999999;

        for (let i = 0; i < 4; i++) {
            let e = edges[i];
            
            let cx = Math.max(e.x1, Math.min(pX, e.x2));
            let cy = Math.max(e.y1, Math.min(pY, e.y2));

            if (Math.abs(cx - sX) < snapT) cx = sX;
            if (Math.abs(cx - (sX + sW - mW)) < snapT) cx = sX + sW - mW;
            if (Math.abs(cx - (sX + sW/2 - mW/2)) < snapT) cx = sX + sW/2 - mW/2;
            
            if (Math.abs(cy - sY) < snapT) cy = sY;
            if (Math.abs(cy - (sY + sH - mH)) < snapT) cy = sY + sH - mH;
            if (Math.abs(cy - (sY + sH/2 - mH/2)) < snapT) cy = sY + sH/2 - mH/2;

            let dist = Math.hypot(pX - cx, pY - cy);
            if (dist < minDist) {
                minDist = dist;
                bestX = cx;
                bestY = cy;
            }
        }
        return { x: bestX, y: bestY };
    }

    function forceLayoutUpdate() {
        if (monitorsModel.count < 2) return;
        
        let mIdx = window.activeEditIndex;
        let mModel = monitorsModel.get(mIdx);
        let isP = mModel.transform === 1 || mModel.transform === 3;
        let mW = ((isP ? mModel.resH : mModel.resW) / mModel.sysScale) * window.uiScale;
        let mH = ((isP ? mModel.resW : mModel.resH) / mModel.sysScale) * window.uiScale;

        let bestX = mModel.uiX;
        let bestY = mModel.uiY;
        let bestDist = 999999;

        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === mIdx) continue;
            let sModel = monitorsModel.get(i);
            let sIsP = sModel.transform === 1 || sModel.transform === 3;
            let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * window.uiScale;
            let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * window.uiScale;
            
            let snapped = window.getPerimeterSnap(
                mModel.uiX, mModel.uiY,
                sModel.uiX, sModel.uiY,
                sW, sH, mW, mH, window.s(20)
            );
            
            let dist = Math.hypot(snapped.x - mModel.uiX, snapped.y - mModel.uiY);
            if (dist < bestDist) {
                bestDist = dist;
                bestX = snapped.x;
                bestY = snapped.y;
            }
        }

        monitorsModel.setProperty(mIdx, "uiX", bestX);
        monitorsModel.setProperty(mIdx, "uiY", bestY);
    }

    Timer {
        id: delayedLayoutUpdate
        interval: 10
        running: false
        repeat: false
        onTriggered: window.forceLayoutUpdate()
    }

    // -------------------------------------------------------------------------
    // NATIVE SYSTEM PROCESSES 
    // -------------------------------------------------------------------------
    Process {
        id: displayPoller
        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text.trim());
                    monitorsModel.clear();
                    
                    let minX = 999999, minY = 999999;

                    for (let i = 0; i < data.length; i++) {
                        if (data[i].x < minX) minX = data[i].x;
                        if (data[i].y < minY) minY = data[i].y;
                    }

                    window.originalLayoutOriginX = minX !== 999999 ? minX : 0;
                    window.originalLayoutOriginY = minY !== 999999 ? minY : 0;

                    for (let i = 0; i < data.length; i++) {
                        let scl = data[i].scale !== undefined ? data[i].scale : 1.0;
                        let tf = data[i].transform !== undefined ? data[i].transform : 0;
                        let normalizedX = (data[i].x - minX) * window.uiScale;
                        let normalizedY = (data[i].y - minY) * window.uiScale;

                        monitorsModel.append({
                            name: data[i].name,
                            resW: data[i].width,
                            resH: data[i].height,
                            sysScale: scl,
                            rate: Math.round(data[i].refreshRate).toString(),
                            uiX: normalizedX,
                            uiY: normalizedY,
                            transform: tf
                        });

                        if (data[i].focused) window.activeEditIndex = i;
                    }
                    
                    window.forceLayoutUpdate();
                } catch(e) {}
            }
        }
    }

    // -------------------------------------------------------------------------
    // SYSTEM APPLY FUNCTION & DEBUG LOGGING
    // -------------------------------------------------------------------------
    function triggerApply() {
        flashRect.opacity = 0.8; 
        applyFlashAnim.start();

        if (monitorsModel.count === 0) return;

        window.debugLog("================= NEW APPLY RUN =================");

        if (monitorsModel.count === 1) {
            let m = monitorsModel.get(0);
            let monitorStr = m.name + "," + m.resW + "x" + m.resH + "@" + m.rate + ",0x0," + m.sysScale;
            if (m.transform !== 0) {
                monitorStr += ",transform," + m.transform;
            }

            let jsonMonitorsArray = [{
                name: m.name, resW: m.resW, resH: m.resH, rate: parseInt(m.rate),
                x: 0, y: 0, scale: m.sysScale, transform: m.transform
            }];
            let safeJson = JSON.stringify(jsonMonitorsArray).replace(/'/g, "'\\''");
            let jsonCmd = "jq '.monitors = " + safeJson + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json";
            let postReloadCmd = "awww kill ; sleep 0.2 ; awww-daemon &";

            Quickshell.execDetached(["notify-send", "Display Update", "Applied & Saved: " + m.resW + "x" + m.resH + " @ " + m.rate + "Hz"]);
            Quickshell.execDetached(["sh", "-c", "hyprctl keyword monitor " + monitorStr + " ; " + jsonCmd + " ; " + postReloadCmd]);
            
            window.debugLog("Executed single monitor apply.");
        } else {
            let rects = [];
            let finalMinX = 999999;
            let finalMinY = 999999;

            for (let i = 0; i < monitorsModel.count; i++) {
                let m = monitorsModel.get(i);
                let isP = m.transform === 1 || m.transform === 3;
                let physW = Math.round((isP ? m.resH : m.resW) / m.sysScale);
                let physH = Math.round((isP ? m.resW : m.resH) / m.sysScale);
                
                let rawX = m.uiX / window.uiScale;
                let rawY = m.uiY / window.uiScale;
                
                rects.push({
                    x: rawX, y: rawY, w: physW, h: physH, 
                    resW: m.resW, resH: m.resH, name: m.name, 
                    rate: m.rate, sysScale: m.sysScale, transform: m.transform
                });
            }

            function getTightSnap(pX, pY, sX, sY, sW, sH, mW, mH, t) {
                let cx = pX; let cy = pY;
                if (Math.abs(cx - (sX - mW)) < t) cx = sX - mW;
                else if (Math.abs(cx - (sX + sW)) < t) cx = sX + sW;
                else if (Math.abs(cx - sX) < t) cx = sX;
                else if (Math.abs(cx - (sX + sW - mW)) < t) cx = sX + sW - mW;
                else if (Math.abs(cx - (sX + sW/2 - mW/2)) < t) cx = sX + sW/2 - mW/2;
                
                if (Math.abs(cy - (sY - mH)) < t) cy = sY - mH;
                else if (Math.abs(cy - (sY + sH)) < t) cy = sY + sH;
                else if (Math.abs(cy - sY) < t) cy = sY;
                else if (Math.abs(cy - (sY + sH - mH)) < t) cy = sY + sH - mH;
                else if (Math.abs(cy - (sY + sH/2 - mH/2)) < t) cy = sY + sH/2 - mH/2;
                
                return {x: cx, y: cy};
            }

            for (let i = 1; i < rects.length; i++) {
                let bestX = rects[i].x;
                let bestY = rects[i].y;
                let bestDist = 999999;
                for (let j = 0; j < i; j++) {
                    let r0 = rects[j];
                    let snapped = getTightSnap(
                        rects[i].x, rects[i].y,
                        r0.x, r0.y,
                        r0.w, r0.h, rects[i].w, rects[i].h, 25 // Intentionally unscaled (Physical display coordinates)
                    );
                    let dist = Math.hypot(rects[i].x - snapped.x, rects[i].y - snapped.y);
                    if (dist < bestDist) {
                        bestDist = dist;
                        bestX = Math.round(snapped.x);
                        bestY = Math.round(snapped.y);
                    }
                }
                rects[i].x = bestX;
                rects[i].y = bestY;
            }

            for (let i = 0; i < rects.length; i++) {
                if (rects[i].x < finalMinX) finalMinX = rects[i].x;
                if (rects[i].y < finalMinY) finalMinY = rects[i].y;
            }
            
            let batchCmds = [];
            let summaryString = "";
            let jsonMonitorsArray = [];

            for (let i = 0; i < rects.length; i++) {
                let r = rects[i];
                
                r.x = Math.round(r.x - finalMinX);
                r.y = Math.round(r.y - finalMinY);
                
                let monitorStr = r.name + "," + r.resW + "x" + r.resH + "@" + r.rate + "," + r.x + "x" + r.y + "," + r.sysScale;
                if (r.transform !== 0) {
                    monitorStr += ",transform," + r.transform;
                }
                
                batchCmds.push("keyword monitor " + monitorStr);
                summaryString += r.name + " ";

                jsonMonitorsArray.push({
                    name: r.name, resW: r.resW, resH: r.resH, rate: parseInt(r.rate),
                    x: r.x, y: r.y, scale: r.sysScale, transform: r.transform
                });
            }
            
            let fullHyprCmd = "hyprctl --batch '" + batchCmds.join(" ; ") + "'";
            let safeJson = JSON.stringify(jsonMonitorsArray).replace(/'/g, "'\\''");
            let jsonCmd = "jq '.monitors = " + safeJson + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json";
            let postReloadCmd = "awww kill ; sleep 0.2 ; awww-daemon &";

            Quickshell.execDetached(["sh", "-c", fullHyprCmd + " ; " + jsonCmd + " ; " + postReloadCmd]);
            Quickshell.execDetached(["notify-send", "Display Update", "Applied & Saved layout for: " + summaryString]);
            
            window.debugLog("Executed multi monitor apply: " + fullHyprCmd);
        }
    }


    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * window.introProgress)
        opacity: window.introProgress

        Rectangle {
            anchors.fill: parent
            radius: window.s(30)
            color: window.base
            border.color: window.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.8
                height: width
                radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: 0.04
                color: window.selectedResAccent
                Behavior on color { ColorAnimation { duration: 1000 } }
            }
            Rectangle {
                width: parent.width * 0.9
                height: width
                radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: 0.04
                color: window.selectedRateAccent
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            // ==========================================
            // LEFT SIDE VISUAL AREA
            // ==========================================
            Item {
                id: leftVisualArea
                width: window.s(380)
                height: window.s(300)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: window.s(20)

                // --------------------------------------------------
                // MODE 1: SINGLE MONITOR
                // --------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: monitorsModel.count === 1

                    Item {
                        id: singleMonitorZoom
                        anchors.centerIn: parent
                        width: window.s(380)
                        height: window.s(280)
                        
                        property real baseScale: Math.min(1.0, Math.min(2200 / window.currentSimW, 1400 / Math.max(1, window.currentSimH)))
                        scale: baseScale * window.monitorScale
                        opacity: window.introProgress
                        Behavior on baseScale { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                        Rectangle {
                            id: deskSurface
                            width: window.s(1000)
                            height: window.s(14)
                            radius: window.s(6)
                            anchors.top: standBase.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: window.mantle
                            border.color: window.surface0
                            border.width: 1

                            Rectangle { 
                                width: window.s(24)
                                height: window.s(350)
                                radius: window.s(4)
                                color: window.crust
                                anchors.top: parent.bottom
                                anchors.topMargin: window.s(-5)
                                anchors.left: parent.left
                                anchors.leftMargin: window.s(100)
                                z: -1 
                            }
                            Rectangle { 
                                width: window.s(24)
                                height: window.s(350)
                                radius: window.s(4)
                                color: window.crust
                                anchors.top: parent.bottom
                                anchors.topMargin: window.s(-5)
                                anchors.right: parent.right
                                anchors.rightMargin: window.s(100)
                                z: -1 
                            }
                        }

                        Rectangle {
                            id: standBase
                            width: window.s(130)
                            height: window.s(8)
                            radius: window.s(4)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: window.s(20)
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: window.surface1
                        }
                        
                        Rectangle {
                            id: standNeck
                            width: window.s(34)
                            height: window.s(70)
                            anchors.bottom: standBase.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: window.surface0
                            Rectangle { 
                                width: window.s(10)
                                height: window.s(30)
                                radius: window.s(5)
                                anchors.centerIn: parent
                                color: window.base 
                            }
                        }

                        Rectangle {
                            id: screenBezel
                            
                            // Perfect aspect ratio AND scales up physically on the desk at higher resolutions
                            width: window.s(320) * (window.currentSimW / 1920.0)
                            height: window.s(320) * (window.currentSimH / 1920.0)

                            anchors.bottom: standNeck.top
                            anchors.bottomMargin: window.s(-10)
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: window.s(12)
                            color: window.crust
                            border.color: window.surface2
                            border.width: window.s(2)
                            
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: window.s(10)
                                radius: window.s(6)
                                color: window.surface0
                                clip: true

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    opacity: window.screenLight
                                    
                                    gradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { 
                                            position: 0.0
                                            color: Qt.tint(window.surface0, Qt.alpha(window.selectedResAccent, 0.15))
                                            Behavior on color { ColorAnimation { duration: 400 } } 
                                        }
                                        GradientStop { 
                                            position: 1.0
                                            color: Qt.tint(window.surface0, Qt.alpha(window.selectedRateAccent, 0.1))
                                            Behavior on color { ColorAnimation { duration: 400 } } 
                                        }
                                    }
                                    
                                    Grid { 
                                        anchors.centerIn: parent
                                        rows: 10
                                        columns: 15
                                        spacing: window.s(20)
                                        Repeater { 
                                            model: 150
                                            Rectangle { width: window.s(2); height: window.s(2); radius: window.s(1); color: Qt.alpha(window.text, 0.1) } 
                                        } 
                                    }
                                }

                                Item {
                                    anchors.centerIn: parent
                                    width: window.s(160)
                                    height: window.s(100)
                                    
                                    // 1. Counteract the environmental zoom factor
                                    property real counterScale: 1.0 / singleMonitorZoom.scale
                                    
                                    // 2. Compute a safe physical boundary based on current visual rotation
                                    // If rotated (portrait), we compare the wrapper's height to the screen's width, etc.
                                    property real maxPhysicalScale: window.currentIsPortrait 
                                        ? Math.min((parent.width * 0.9) / height, (parent.height * 0.9) / width)
                                        : Math.min((parent.width * 0.9) / width, (parent.height * 0.9) / height)
                                    
                                    scale: Math.min(counterScale, maxPhysicalScale)
                                    
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: window.s(4)

                                        // Restored Rotation: Acts as a pointer to the monitor's physical bottom
                                        rotation: window.currentTransform * 90
                                        Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                                        Text { 
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(38)
                                            color: window.selectedResAccent
                                            text: "󰍹"
                                            Behavior on color { ColorAnimation { duration: 400 } } 
                                        }
                                        Text { 
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Bold
                                            font.pixelSize: window.s(16)
                                            color: window.text
                                            text: monitorsModel.count > 0 ? monitorsModel.get(0).name : "Unknown" 
                                        }
                                        Text { 
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(12)
                                            color: window.subtext0
                                            text: window.currentSimW + "x" + window.currentSimH + " @ " + (monitorsModel.count > 0 ? monitorsModel.get(0).rate : "60") + "Hz" 
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --------------------------------------------------
                // MODE 2: MULTI-MONITOR (3+ Supported)
                // --------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: monitorsModel.count > 1

                    Item {
                        id: multiMonitorView
                        width: window.s(380)
                        height: window.s(280)
                        anchors.centerIn: parent
                        clip: true 

                        Grid {
                            anchors.centerIn: parent
                            rows: 25
                            columns: 34
                            spacing: window.s(18)
                            Repeater { 
                                model: 850
                                Rectangle { width: window.s(2); height: window.s(2); radius: window.s(1); color: Qt.alpha(window.text, 0.1) } 
                            }
                        }

                        property real targetScale: {
                            if (monitorsModel.count < 2) return 1.0;
                            let minX = 999999, minY = 999999, maxX = -999999, maxY = -999999;
                            
                            for (let i = 0; i < monitorsModel.count; i++) {
                                let m = monitorsModel.get(i);
                                let isP = m.transform === 1 || m.transform === 3;
                                let w = ((isP ? m.resH : m.resW) / m.sysScale) * window.uiScale;
                                let h = ((isP ? m.resW : m.resH) / m.sysScale) * window.uiScale;
                                
                                minX = Math.min(minX, m.uiX);
                                minY = Math.min(minY, m.uiY);
                                maxX = Math.max(maxX, m.uiX + w);
                                maxY = Math.max(maxY, m.uiY + h);
                            }
                            
                            let requiredW = (maxX - minX) + window.s(80);
                            let requiredH = (maxY - minY) + window.s(80);
                            
                            return Math.min(1.8 * scaler.baseScale, Math.min(window.s(340) / requiredW, window.s(240) / requiredH));
                        }

                        property real offsetX: {
                            if (monitorsModel.count < 2) return 0;
                            let minX = 999999, maxX = -999999;
                            
                            for (let i = 0; i < monitorsModel.count; i++) {
                                let m = monitorsModel.get(i);
                                let isP = m.transform === 1 || m.transform === 3;
                                let w = ((isP ? m.resH : m.resW) / m.sysScale) * window.uiScale;
                                
                                minX = Math.min(minX, m.uiX);
                                maxX = Math.max(maxX, m.uiX + w);
                            }
                            
                            let centerX = minX + (maxX - minX) / 2;
                            return window.s(190) - (centerX * targetScale);
                        }

                        property real offsetY: {
                            if (monitorsModel.count < 2) return 0;
                            let minY = 999999, maxY = -999999;
                            
                            for (let i = 0; i < monitorsModel.count; i++) {
                                let m = monitorsModel.get(i);
                                let isP = m.transform === 1 || m.transform === 3;
                                let h = ((isP ? m.resW : m.resH) / m.sysScale) * window.uiScale;
                                
                                minY = Math.min(minY, m.uiY);
                                maxY = Math.max(maxY, m.uiY + h);
                            }
                            
                            let centerY = minY + (maxY - minY) / 2;
                            return window.s(140) - (centerY * targetScale);
                        }

                        Item {
                            id: transformNode
                            x: multiMonitorView.offsetX
                            y: multiMonitorView.offsetY
                            scale: multiMonitorView.targetScale
                            transformOrigin: Item.TopLeft

                            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                            Repeater {
                                id: monitorRepeater
                                model: monitorsModel

                                Item {
                                    property bool isActive: window.activeEditIndex === index
                                    property bool isPortrait: model.transform === 1 || model.transform === 3

                                    // THE VISIBLE SNAPPED MONITOR CARD
                                    Rectangle {
                                        id: monitorCard
                                        x: model.uiX
                                        y: model.uiY
                                        
                                        width: (isPortrait ? model.resH : model.resW) / model.sysScale * window.uiScale
                                        height: (isPortrait ? model.resW : model.resH) / model.sysScale * window.uiScale
                                        
                                        radius: window.s(8)
                                        color: isActive ? window.surface1 : window.crust
                                        border.color: isActive ? window.selectedResAccent : window.surface2
                                        border.width: isActive ? window.s(2) : window.s(1)
                                        z: isActive ? 5 : 0

                                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                        
                                        Behavior on border.color { ColorAnimation { duration: 300 } }
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                                        Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                                        Item {
                                            anchors.centerIn: parent
                                            width: window.s(110)
                                            height: window.s(80)
                                            
                                            property real idealScale: 1.2 / transformNode.scale
                                            // Ensure the bounded box checks against the correct axis when visually rotated
                                            property real maxPhysicalScale: isPortrait 
                                                ? Math.min((parent.width * 0.9) / height, (parent.height * 0.9) / width) 
                                                : Math.min((parent.width * 0.9) / width, (parent.height * 0.9) / height)
                                            
                                            scale: Math.min(idealScale, maxPhysicalScale)
                                            
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: window.s(2)
                                                
                                                // Restored Rotation for Multi-Monitor cards
                                                rotation: model.transform * 90
                                                Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                                                Text { 
                                                    Layout.alignment: Qt.AlignHCenter
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(32)
                                                    color: isActive ? window.selectedResAccent : window.text
                                                    text: "󰍹"
                                                    Behavior on color { ColorAnimation { duration: 300 } } 
                                                }
                                                Text { 
                                                    Layout.alignment: Qt.AlignHCenter
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Black
                                                    font.pixelSize: window.s(13)
                                                    color: window.text
                                                    text: model.name 
                                                }
                                                Text { 
                                                    Layout.alignment: Qt.AlignHCenter
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: window.s(10)
                                                    color: window.subtext0
                                                    text: model.resW + "x" + model.resH + " @ " + model.rate + "Hz" 
                                                }
                                            }
                                        }
                                    }

                                    // THE INVISIBLE GHOST DRAGGER
                                    Item {
                                        id: ghostDrag
                                        x: model.uiX
                                        y: model.uiY
                                        width: monitorCard.width
                                        height: monitorCard.height
                                        z: isActive ? 10 : 1

                                        MouseArea {
                                            id: ghostMa
                                            anchors.fill: parent
                                            drag.target: ghostDrag
                                            drag.axis: Drag.XAndYAxis
                                            
                                            onPressed: {
                                                window.activeEditIndex = index;
                                                ghostDrag.x = model.uiX;
                                                ghostDrag.y = model.uiY;
                                            }

                                            onPositionChanged: {
                                                if (drag.active && monitorsModel.count >= 2) {
                                                    let mW = monitorCard.width;
                                                    let mH = monitorCard.height;

                                                    let padding = window.s(40);
                                                    let boundMinX = 999999, boundMinY = 999999;
                                                    let boundMaxX = -999999, boundMaxY = -999999;
                                                    
                                                    for (let j = 0; j < monitorsModel.count; j++) {
                                                        if (j === index) continue;
                                                        let sModel = monitorsModel.get(j);
                                                        let sIsP = sModel.transform === 1 || sModel.transform === 3;
                                                        let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * window.uiScale;
                                                        let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * window.uiScale;
                                                        
                                                        boundMinX = Math.min(boundMinX, sModel.uiX - mW - padding);
                                                        boundMinY = Math.min(boundMinY, sModel.uiY - mH - padding);
                                                        boundMaxX = Math.max(boundMaxX, sModel.uiX + sW + padding);
                                                        boundMaxY = Math.max(boundMaxY, sModel.uiY + sH + padding);
                                                    }

                                                    ghostDrag.x = Math.max(boundMinX, Math.min(ghostDrag.x, boundMaxX));
                                                    ghostDrag.y = Math.max(boundMinY, Math.min(ghostDrag.y, boundMaxY));

                                                    let bestX = ghostDrag.x;
                                                    let bestY = ghostDrag.y;
                                                    let bestDist = 999999;
                                                    
                                                    for (let j = 0; j < monitorsModel.count; j++) {
                                                        if (j === index) continue;
                                                        let sModel = monitorsModel.get(j);
                                                        let sIsP = sModel.transform === 1 || sModel.transform === 3;
                                                        let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * window.uiScale;
                                                        let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * window.uiScale;
                                                        
                                                        let snapped = window.getPerimeterSnap(
                                                            ghostDrag.x, ghostDrag.y,
                                                            sModel.uiX, sModel.uiY,
                                                            sW, sH, mW, mH, window.s(20)
                                                        );
                                                        
                                                        let dist = Math.hypot(ghostDrag.x - snapped.x, ghostDrag.y - snapped.y);
                                                        if (dist < bestDist) {
                                                            bestDist = dist;
                                                            bestX = snapped.x;
                                                            bestY = snapped.y;
                                                        }
                                                    }

                                                    if (!window.isOverlappingAny(bestX, bestY, mW, mH, index)) {
                                                        monitorsModel.setProperty(index, "uiX", bestX);
                                                        monitorsModel.setProperty(index, "uiY", bestY);
                                                    }
                                                }
                                            }

                                            onReleased: {
                                                ghostDrag.x = model.uiX;
                                                ghostDrag.y = model.uiY;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // INTERACTIVE SELECTION GRIDS
            // ==========================================
            Item {
                anchors.left: leftVisualArea.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: window.s(-10) // Tweak layout slightly downwards 
                anchors.leftMargin: window.s(10)
                anchors.rightMargin: window.s(30)
                height: rightSideContainer.implicitHeight 

                opacity: window.introProgress
                transform: Translate { y: window.uiYOffset }

                SequentialAnimation {
                    id: menuTransitionAnim
                    ParallelAnimation {
                        ScaleAnimator { 
                            target: rightSideContainer
                            from: 0.99
                            to: 1.0
                            duration: 200
                            easing.type: Easing.OutSine 
                        }
                        NumberAnimation { 
                            target: highlightFlash
                            property: "opacity"
                            from: 0.05
                            to: 0.0
                            duration: 250
                            easing.type: Easing.OutQuad 
                        }
                    }
                }

                Rectangle {
                    id: highlightFlash
                    anchors.fill: rightSideContainer
                    anchors.margins: window.s(-10)
                    color: window.selectedResAccent
                    opacity: 0.0
                    radius: window.s(12)
                }

                ColumnLayout {
                    id: rightSideContainer
                    anchors.fill: parent
                    spacing: window.s(10)

                    // --- RESOLUTION CARDS SECTION ---
                    GridLayout {
                        id: resGrid
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: window.s(10)
                        rowSpacing: window.s(10)

                        Repeater {
                            model: window.resList

                            delegate: Rectangle {
                                property var modelData: window.resList[index]
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(45)
                                radius: window.s(12)
                                
                                property bool isSel: {
                                    if (monitorsModel.count === 0) return false;
                                    let activeMon = monitorsModel.get(window.activeEditIndex);
                                    return activeMon.resW === modelData.w && activeMon.resH === modelData.h;
                                }
                                property color accentColor: modelData.accent
                                
                                color: isSel ? Qt.alpha(accentColor, 0.15) : (resMa.containsMouse ? window.surface0 : window.mantle)
                                border.color: isSel ? accentColor : (resMa.containsMouse ? window.surface1 : "transparent")
                                border.width: isSel ? window.s(2) : window.s(1)
                                
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: window.s(12)
                                    spacing: window.s(8)
                                    
                                    Text { 
                                        font.family: "JetBrains Mono"
                                        font.weight: isSel ? Font.Black : Font.Bold
                                        font.pixelSize: window.s(15)
                                        color: isSel ? accentColor : window.text
                                        text: modelData.l
                                        Behavior on color { ColorAnimation { duration: 200 } } 
                                    }
                                    
                                    Item { Layout.fillWidth: true } 
                                    
                                    Text { 
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(11)
                                        color: isSel ? window.text : window.overlay0
                                        text: modelData.w + "x" + modelData.h
                                        Behavior on color { ColorAnimation { duration: 200 } } 
                                    }
                                }

                                scale: resMa.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutSine } }

                                MouseArea {
                                    id: resMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.activeFocusIndex = 0;
                                        if (monitorsModel.count > 0) {
                                            window.selectedResAccent = accentColor;
                                            monitorsModel.setProperty(window.activeEditIndex, "resW", modelData.w);
                                            monitorsModel.setProperty(window.activeEditIndex, "resH", modelData.h);
                                            delayedLayoutUpdate.restart();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: window.s(2) } 

                    // --- ROTATION DIAL (CLOCK-STYLE) SECTION ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: window.s(120)
                        
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: clockDial
                            // Use Layout properties instead of standard width/height to prevent 
                            // the layout engine from breaking your dimensions during resize
                            Layout.preferredWidth: window.s(120)
                            Layout.preferredHeight: window.s(120)
                            Layout.alignment: Qt.AlignCenter
                            
                            radius: width / 2
                            color: window.surface0 
                            
                            border.color: window.activeFocusIndex === 1 ? window.selectedResAccent : window.surface1 
                            border.width: window.activeFocusIndex === 1 ? window.s(3) : window.s(2)
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                            Behavior on border.width { NumberAnimation { duration: 200 } }

                            // 12-Hour Clock Tick Marks
                            Repeater {
                                model: 12
                                Item {
                                    anchors.fill: parent
                                    rotation: index * 30
                                    Rectangle {
                                        width: index % 3 === 0 ? window.s(4) : window.s(2)
                                        height: index % 3 === 0 ? window.s(8) : window.s(4)
                                        radius: width / 2
                                        color: index % 3 === 0 ? window.subtext0 : window.surface2 
                                        anchors.top: parent.top
                                        anchors.topMargin: window.s(4)
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            // The Interactive Pointer
                            Item {
                                id: dialPointer
                                anchors.fill: parent
                                property int activeTransform: monitorsModel.count > 0 ? monitorsModel.get(window.activeEditIndex).transform : 0
                                rotation: activeTransform * 90
                                Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutBack;} }

                                // Pointer Line
                                Rectangle {
                                    width: window.s(5)
                                    height: parent.height / 2 - window.s(20)
                                    radius: window.s(2.5)
                                    color: window.selectedResAccent
                                    anchors.bottom: parent.verticalCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                                
                                // Center Dot
                                Rectangle {
                                    width: window.s(18)
                                    height: window.s(18) // Replaced height: width binding
                                    radius: width / 2
                                    color: window.base
                                    border.color: window.selectedResAccent
                                    border.width: window.s(4)
                                    anchors.centerIn: parent
                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                }
                            }

                            MouseArea {
                                id: dialMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                function updateAngle(mouse) {
                                    if (monitorsModel.count === 0) return;
                                    window.activeFocusIndex = 1;
                                    
                                    let dx = mouse.x - width / 2;
                                    let dy = mouse.y - height / 2;

                                    if (Math.hypot(dx, dy) < window.s(20)) return;

                                    let snap = 0;
                                    if (Math.abs(dx) > Math.abs(dy)) {
                                        snap = dx > 0 ? 1 : 3;
                                    } else {
                                        snap = dy > 0 ? 2 : 0;
                                    }
                                    
                                    monitorsModel.setProperty(window.activeEditIndex, "transform", snap);
                                    delayedLayoutUpdate.restart();
                                }

                                onPressed: (mouse) => updateAngle(mouse)
                                onPositionChanged: (mouse) => { if (pressed) updateAngle(mouse) }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }                    Item { Layout.preferredHeight: window.s(2) }

                    // --- REFRESH RATE SLIDER SECTION ---
                    Item {
                        id: sliderContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: window.s(45)
                        Layout.leftMargin: window.s(6)
                        Layout.rightMargin: window.s(6)
                        
                        property var rates: [60, 75, 100, 120, 144, 165, 180, 240, 360]
                        property var rateColors: [window.red, window.mauve, window.blue, window.sapphire, window.teal, window.pink, window.yellow, window.green, window.peach]
                        
                        property int currentIndex: {
                            if (monitorsModel.count === 0) return 0;
                            let currentVal = parseInt(monitorsModel.get(window.activeEditIndex).rate) || 60;
                            let closestIdx = 0;
                            let minDiff = 9999;
                            for (let i = 0; i < rates.length; i++) {
                                let diff = Math.abs(rates[i] - currentVal);
                                if (diff < minDiff) { 
                                    minDiff = diff; 
                                    closestIdx = i; 
                                }
                            }
                            return closestIdx;
                        }

                        property real visualPct: currentIndex / (rates.length - 1)

                        onCurrentIndexChanged: { 
                            if (!sliderMa.pressed) visualPct = currentIndex / (rates.length - 1); 
                        }
                        
                        function updateSelectionVisual(idx) {
                            if (monitorsModel.count === 0) return;
                            visualPct = idx / (rates.length - 1);
                            monitorsModel.setProperty(window.activeEditIndex, "rate", rates[idx].toString());
                            window.selectedRateAccent = rateColors[idx];
                        }

                        Rectangle {
                            id: track
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: window.s(15)
                            anchors.rightMargin: window.s(15)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: window.s(-10)
                            height: window.s(12)
                            radius: window.s(6)
                            color: window.mantle
                            border.color: window.crust
                            border.width: 1
                            
                            Rectangle { 
                                id: trackFill
                                width: Math.max(0, knob.x + knob.width / 2)
                                height: parent.height
                                radius: parent.radius
                                color: window.selectedRateAccent
                                Behavior on color { ColorAnimation { duration: 200 } } 
                            }

                            Rectangle {
                                id: knob
                                width: window.s(24)
                                height: window.s(24)
                                radius: window.s(12)
                                color: sliderMa.containsPress ? window.selectedRateAccent : window.text
                                anchors.verticalCenter: parent.verticalCenter
                                x: (sliderContainer.visualPct * parent.width) - width / 2
                                
                                Behavior on x { 
                                    enabled: !sliderMa.pressed
                                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic } 
                                }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                
                                border.width: (sliderMa.containsMouse || window.activeFocusIndex === 2) ? window.s(4) : 0
                                border.color: Qt.alpha(window.selectedRateAccent, 0.4)
                                Behavior on border.width { NumberAnimation { duration: 150 } }
                            }
                        }

                        Repeater {
                            model: sliderContainer.rates.length
                            Item {
                                x: track.x + (index / (sliderContainer.rates.length - 1)) * track.width
                                y: track.y + window.s(20)
                                
                                Text { 
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: sliderContainer.rates[index]
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(13)
                                    font.weight: sliderContainer.currentIndex === index ? Font.Bold : Font.Normal
                                    color: sliderContainer.currentIndex === index ? window.selectedRateAccent : window.overlay0
                                    Behavior on color { ColorAnimation { duration: 200 } } 
                                }
                            }
                        }

                        MouseArea {
                            id: sliderMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            function updateSelection(mouseX, snapToGrid) {
                                if (monitorsModel.count === 0) return;
                                window.activeFocusIndex = 2;
                                
                                let pct = (mouseX - track.x) / track.width;
                                pct = Math.max(0, Math.min(1, pct));
                                let idx = Math.round(pct * (sliderContainer.rates.length - 1));
                                
                                if (snapToGrid) {
                                    sliderContainer.visualPct = idx / (sliderContainer.rates.length - 1);
                                } else {
                                    sliderContainer.visualPct = pct;
                                }

                                monitorsModel.setProperty(window.activeEditIndex, "rate", sliderContainer.rates[idx].toString());
                                window.selectedRateAccent = sliderContainer.rateColors[idx];
                            }

                            onPressed: (mouse) => updateSelection(mouse.x, false)
                            onPositionChanged: (mouse) => { if (pressed) updateSelection(mouse.x, false) }
                            onReleased: (mouse) => updateSelection(mouse.x, true)
                            onCanceled: () => sliderContainer.visualPct = sliderContainer.currentIndex / (sliderContainer.rates.length - 1)
                        }
                    }

                    Item { Layout.preferredHeight: window.s(15) } 

                    // ==========================================
                    // FLOATING APPLY BUTTON 
                    // ==========================================
                    Item {
                        id: applyButtonContainer
                        Layout.alignment: Qt.AlignRight
                        Layout.preferredWidth: window.s(170)
                        Layout.preferredHeight: window.s(50)

                        MultiEffect {
                            source: applyBtn
                            anchors.fill: applyBtn
                            shadowEnabled: true
                            shadowColor: window.selectedRateAccent
                            shadowBlur: window.applyHovered || window.activeFocusIndex === 3 ? 1.2 : 0.6
                            shadowOpacity: window.applyHovered || window.activeFocusIndex === 3 ? 0.6 : 0.2
                            shadowVerticalOffset: window.s(4)
                            z: -1
                            Behavior on shadowBlur { NumberAnimation { duration: 300 } } 
                            Behavior on shadowOpacity { NumberAnimation { duration: 300 } } 
                            Behavior on shadowColor { ColorAnimation { duration: 400 } }
                        }

                        Rectangle {
                            id: applyBtn
                            anchors.fill: parent
                            radius: window.s(25)
                            
                            gradient: Gradient { 
                                orientation: Gradient.Horizontal
                                GradientStop { 
                                    position: 0.0
                                    color: window.selectedResAccent
                                    Behavior on color { ColorAnimation { duration: 400 } } 
                                } 
                                GradientStop { 
                                    position: 1.0
                                    color: window.selectedRateAccent
                                    Behavior on color { ColorAnimation { duration: 400 } } 
                                } 
                            }
                            
                            border.color: window.activeFocusIndex === 3 ? window.crust : "transparent"
                            border.width: window.activeFocusIndex === 3 ? window.s(2) : 0
                            
                            scale: window.applyPressed ? 0.94 : (window.applyHovered || window.activeFocusIndex === 3 ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                            Rectangle {
                                id: flashRect
                                anchors.fill: parent
                                radius: window.s(25)
                                color: window.text
                                opacity: 0.0
                                PropertyAnimation on opacity { 
                                    id: applyFlashAnim
                                    to: 0.0
                                    duration: 400
                                    easing.type: Easing.OutExpo 
                                }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: window.s(8)
                                
                                Text { 
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(20)
                                    color: window.crust
                                    text: "󰸵" 
                                }
                                
                                Text { 
                                    font.family: "JetBrains Mono"
                                    font.weight: Font.Black
                                    font.pixelSize: window.s(14)
                                    color: window.crust
                                    text: monitorsModel.count > 1 ? "Apply All" : "Apply" 
                                }
                            }
                        }

                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            z: 10
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            
                            onEntered: { window.applyHovered = true; window.activeFocusIndex = 3; }
                            onExited: window.applyHovered = false
                            onPressed: window.applyPressed = true
                            onReleased: window.applyPressed = false
                            onCanceled: window.applyPressed = false

                            onClicked: window.triggerApply()
                        }
                    }
                }
            }
        }
    }
}
