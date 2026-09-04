import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../reusables"
import "faces"

PanelWindow {
    id: redactorWindow
    color: "transparent"

    property string monitorName: {
        let envMon = Quickshell.env("QS_WIDGET_MONITOR");
        if (envMon && envMon.trim() !== "") return envMon.trim();
        return (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
    }

    FileView {
        id: targetMonitorFile
        path: (Caching.runDir && Caching.runDir !== "") ? (Caching.runDir + "/redactor_target_monitor") : ""
        watchChanges: true
        onLoaded: {
            let txt = text().trim();
            if (txt !== "" && redactorWindow.monitorName !== txt) {
                redactorWindow.monitorName = txt;
            }
        }
    }

    property var targetScreen: {
        let scr = Quickshell.screens.find(s => s.name === redactorWindow.monitorName);
        return scr || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }
    readonly property string safeMonitorName: (monitorName || (targetScreen ? targetScreen.name : "default")).replace(/[^a-zA-Z0-9_-]/g, "_")
    screen: redactorWindow.targetScreen

    ListModel {
        id: activeWidgetsModel
        onCountChanged: redactorMode.updateToolbarObscured()
    }

    WlrLayershell.namespace: "qs-widget-redactor-" + redactorWindow.safeMonitorName
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    exclusionMode: ExclusionMode.Ignore
    focusable: true

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true

    margins.left: 0
    margins.top: 0

    function s(val) { return Scaler.s(val); }

    function sendIpc(funcName, args) {
        let cmd = ["quickshell", "-p", Caching.mainQml, "ipc", "call", "widgets-" + redactorWindow.safeMonitorName, funcName];
        if (args && args.length > 0) {
            cmd = cmd.concat(args);
        }
        Quickshell.execDetached(cmd);
    }

    function sendBarIpc(funcName, args) {
        let cmd = ["quickshell", "-p", Caching.mainQml, "ipc", "call", "topbar", funcName];
        if (args && args.length > 0) {
            cmd = cmd.concat(args);
        }
        Quickshell.execDetached(cmd);
    }

    Timer {
        id: exitTimer
        interval: 150
        repeat: false
        onTriggered: Qt.quit()
    }

    function exitRedactor() {
        WidgetSync.setRedactMode(redactorWindow.safeMonitorName, false);
        sendIpc("setRedactMode", ["false"]);
        sendBarIpc("setRedactMode", ["false"]);
        exitTimer.start();
    }

    Component.onDestruction: {
        WidgetSync.setRedactMode(redactorWindow.safeMonitorName, false);
        sendIpc("setRedactMode", ["false"]);
        sendBarIpc("setRedactMode", ["false"]);
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            redactorMode.selectedId = "";
            redactorWindow.exitRedactor();
        }
    }

    Item {
        id: redactorMode
        anchors.fill: parent

        property string selectedId: ""
        property bool gridEnabled: false
        property real activeGuideX: -1
        property real activeGuideY: -1
        property bool toolbarObscured: false
        property bool isReady: false
        property bool isInitializing: true
        property int topZ: 1

        onWidthChanged: updateToolbarObscured()
        onHeightChanged: updateToolbarObscured()

        property real safeMinX: 0
        property real safeMinY: 0
        property real safeWidth: redactorMode.width
        property real safeHeight: redactorMode.height

        Timer {
            id: toolbarCheckTimer
            interval: 100
            repeat: false
            onTriggered: redactorMode.updateToolbarObscured()
        }

        function queueUpdateToolbarObscured() {
            toolbarCheckTimer.restart();
        }

        function removeAllWidgets() {
            redactorMode.selectedId = "";
            activeWidgetsModel.clear();
            WidgetSync.clearWidgets(redactorWindow.safeMonitorName);
            redactorWindow.sendIpc("clear", []);
            redactorMode.updateToolbarObscured();
        }

        function updateToolbarObscured() {
            if (activeWidgetsModel.count === 0) {
                toolbarObscured = false;
                return;
            }

            let margin = s(50);
            let tbW = toolbar.width;
            let tbH = toolbar.height;
            let tbX = (redactorMode.width - tbW) / 2;
            let tbY = toolbar.y;

            let zX1 = tbX - margin;
            let zX2 = tbX + tbW + margin;
            let zY1 = tbY - margin;
            let zY2 = redactorMode.height;

            let obscured = false;
            let repCount = widgetRepeater.count;

            if (repCount > 0) {
                for (let i = 0; i < repCount; i++) {
                    let proxy = widgetRepeater.itemAt(i);
                    if (!proxy) continue;

                    let isSel = (redactorMode.selectedId === proxy.wId);
                    let gap = isSel ? s(20) : 0;
                    let chromeH = isSel ? s(90) : 0;

                    let wX1 = proxy.x - gap;
                    let wY1 = proxy.y - gap;
                    let wX2 = proxy.x + proxy.width + gap;
                    let wY2 = proxy.y + proxy.height + gap + chromeH;

                    if (wX1 < zX2 && wX2 > zX1 && wY1 < zY2 && wY2 > zY1) {
                        obscured = true;
                        break;
                    }
                }
            } else {
                for (let i = 0; i < activeWidgetsModel.count; i++) {
                    let item = activeWidgetsModel.get(i);
                    if (!item) continue;
                    let rot = (item.wRotation !== undefined && !isNaN(item.wRotation)) ? Math.abs(Math.round(item.wRotation)) : 0;
                    let bw = (rot % 180 === 0) ? item.wWidth : item.wHeight;
                    let bh = (rot % 180 === 0) ? item.wHeight : item.wWidth;
                    let isSel = (redactorMode.selectedId === item.wId);
                    let gap = isSel ? s(20) : 0;
                    let chromeH = isSel ? s(90) : 0;

                    let wX1 = item.wX - gap;
                    let wY1 = item.wY - gap;
                    let wX2 = item.wX + bw + gap;
                    let wY2 = item.wY + bh + gap + chromeH;

                    if (wX1 < zX2 && wX2 > zX1 && wY1 < zY2 && wY2 > zY1) {
                        obscured = true;
                        break;
                    }
                }
            }
            toolbarObscured = obscured;
        }

        function getConstraints(loaderItem) {
            if (!loaderItem) return null;
            return {
                minW: loaderItem.minWidth !== undefined ? loaderItem.minWidth : 10,
                minH: loaderItem.minHeight !== undefined ? loaderItem.minHeight : 10,
                maxW: loaderItem.maxWidth !== undefined ? loaderItem.maxWidth : 9999,
                maxH: loaderItem.maxHeight !== undefined ? loaderItem.maxHeight : 9999,
                minA: loaderItem.minAspect !== undefined ? loaderItem.minAspect : 0,
                maxA: loaderItem.maxAspect !== undefined ? loaderItem.maxAspect : 9999
            };
        }

        function clampResize(loaderItem, rawW, rawH, dx, dy, isCorner) {
            let c = getConstraints(loaderItem);
            if (!c) return { w: rawW, h: rawH };

            let w = Math.max(c.minW, Math.min(c.maxW, rawW));
            let h = Math.max(c.minH, Math.min(c.maxH, rawH));

            if (!isCorner) {
                if (dx !== 0) {
                    let effMinW = Math.max(c.minW, h * c.minA);
                    let effMaxW = Math.min(c.maxW, h * c.maxA);
                    if (effMinW <= effMaxW) {
                        w = Math.max(effMinW, Math.min(effMaxW, w));
                    } else {
                        h = Math.max(c.minH, Math.min(c.maxH, w / (c.minA > 0 ? c.minA : 1)));
                        w = Math.max(c.minW, Math.min(c.maxW, h * c.minA));
                    }
                } else {
                    let effMinH = Math.max(c.minH, c.maxA > 0 ? w / c.maxA : 0);
                    let effMaxH = Math.min(c.maxH, c.minA > 0 ? w / c.minA : 9999);
                    if (effMinH <= effMaxH) {
                        h = Math.max(effMinH, Math.min(effMaxH, h));
                    } else {
                        w = Math.max(c.minW, Math.min(c.maxW, h * c.minA));
                        h = Math.max(c.minH, Math.min(c.maxH, c.minA > 0 ? w / c.minA : h));
                    }
                }
                return { w: w, h: h };
            }

            let ratio = w / h;
            if (ratio < c.minA && c.minA > 0) {
                let mA = c.minA;
                let hProj = (w * mA + h) / (mA * mA + 1);
                let hMin = Math.max(c.minH, c.minW / mA);
                let hMax = Math.min(c.maxH, c.maxW / mA);
                h = Math.max(hMin, Math.min(hMax, hProj));
                w = h * mA;
            } else if (ratio > c.maxA && c.maxA > 0) {
                let mA = c.maxA;
                let hProj = (w * mA + h) / (mA * mA + 1);
                let hMin = Math.max(c.minH, c.minW / mA);
                let hMax = Math.min(c.maxH, c.maxW / mA);
                h = Math.max(hMin, Math.min(hMax, hProj));
                w = h * mA;
            }

            w = Math.max(c.minW, Math.min(c.maxW, w));
            h = Math.max(c.minH, Math.min(c.maxH, h));

            return { w: w, h: h };
        }

        function calculateSnap(draggedItem, rawX, rawY) {
            let snapThreshold = 12;
            let res = { x: rawX, y: rawY, guideX: -1, guideY: -1 };
            let gridStep = s(20);

            if (gridEnabled) {
                res.x = Math.round(rawX / gridStep) * gridStep;
                res.y = Math.round(rawY / gridStep) * gridStep;
            } else {
                let bestDx = snapThreshold;
                let bestDy = snapThreshold;

                let dXEdges = [rawX, rawX + draggedItem.width / 2.0, rawX + draggedItem.width];
                let dYEdges = [rawY, rawY + draggedItem.height / 2.0, rawY + draggedItem.height];

                let screenCenterX = safeWidth / 2.0;
                let screenCenterY = safeHeight / 2.0;

                for (let j = 0; j < dXEdges.length; j++) {
                    let diff = Math.abs(dXEdges[j] - screenCenterX);
                    if (diff < bestDx) {
                        bestDx = diff;
                        res.x = rawX + (screenCenterX - dXEdges[j]);
                        res.guideX = screenCenterX;
                    }
                }

                for (let j = 0; j < dYEdges.length; j++) {
                    let diff = Math.abs(dYEdges[j] - screenCenterY);
                    if (diff < bestDy) {
                        bestDy = diff;
                        res.y = rawY + (screenCenterY - dYEdges[j]);
                        res.guideY = screenCenterY;
                    }
                }

                for (let i = 0; i < widgetRepeater.count; i++) {
                    let other = widgetRepeater.itemAt(i);
                    if (!other || other === draggedItem) continue;

                    let oXEdges = [other.x, other.x + other.width / 2.0, other.x + other.width];
                    let oYEdges = [other.y, other.y + other.height / 2.0, other.y + other.height];

                    for (let j = 0; j < dXEdges.length; j++) {
                        for (let k = 0; k < oXEdges.length; k++) {
                            let diff = Math.abs(dXEdges[j] - oXEdges[k]);
                            if (diff < bestDx) {
                                bestDx = diff;
                                res.x = rawX + (oXEdges[k] - dXEdges[j]);
                                res.guideX = oXEdges[k];
                            }
                        }
                    }

                    for (let j = 0; j < dYEdges.length; j++) {
                        for (let k = 0; k < oYEdges.length; k++) {
                            let diff = Math.abs(dYEdges[j] - oYEdges[k]);
                            if (diff < bestDy) {
                                bestDy = diff;
                                res.y = rawY + (oYEdges[k] - dYEdges[j]);
                                res.guideY = oYEdges[k];
                            }
                        }
                    }
                }
            }

            let mX = Math.max(0, safeWidth - draggedItem.width);
            let mY = Math.max(0, safeHeight - draggedItem.height);
            res.x = Math.max(0, Math.min(mX, res.x));
            res.y = Math.max(0, Math.min(mY, res.y));

            return res;
        }

        function snapBoxToGrid(loaderItem, x, y, w, h) {
            let gridStep = s(20);
            let L = Math.round(x / gridStep) * gridStep;
            let T = Math.round(y / gridStep) * gridStep;
            let R = Math.round((x + w) / gridStep) * gridStep;
            let B = Math.round((y + h) / gridStep) * gridStep;

            L = Math.max(0, Math.min(safeWidth, L));
            T = Math.max(0, Math.min(safeHeight, T));
            R = Math.max(0, Math.min(safeWidth, R));
            B = Math.max(0, Math.min(safeHeight, B));

            if (R <= L) R = L + gridStep;
            if (B <= T) B = T + gridStep;

            let snappedW = R - L;
            let snappedH = B - T;

            let clamped = clampResize(loaderItem, snappedW, snappedH, 0, 0, true);

            let finalX = L;
            let finalY = T;
            let mX = Math.max(0, safeWidth - clamped.w);
            let mY = Math.max(0, safeHeight - clamped.h);
            finalX = Math.max(0, Math.min(mX, finalX));
            finalY = Math.max(0, Math.min(mY, finalY));

            return { x: finalX, y: finalY, w: clamped.w, h: clamped.h };
        }

        function calculateResize(loaderItem, startX, startY, startW, startH, dx, dy, edges, isCorner, rot) {
            let rawW = startW;
            let rawH = startH;

            if (edges.left) rawW = startW - dx;
            else if (edges.right) rawW = startW + dx;

            if (edges.top) rawH = startH - dy;
            else if (edges.bottom) rawH = startH + dy;

            let gridStep = s(20);
            if (gridEnabled) {
                if (edges.left || edges.right) rawW = Math.round(rawW / gridStep) * gridStep;
                if (edges.top || edges.bottom) rawH = Math.round(rawH / gridStep) * gridStep;
            }

            let normRot = ((Math.round(rot || 0) % 360) + 360) % 360;
            let isRot90 = (normRot % 180 !== 0);
            let maxAllowedW = isRot90 ? safeHeight : safeWidth;
            let maxAllowedH = isRot90 ? safeWidth : safeHeight;

            rawW = Math.max(10, Math.min(maxAllowedW, rawW));
            rawH = Math.max(10, Math.min(maxAllowedH, rawH));

            let clamped = clampResize(loaderItem, rawW, rawH, dx, dy, isCorner);
            let finalW = Math.max(10, Math.min(maxAllowedW, clamped.w));
            let finalH = Math.max(10, Math.min(maxAllowedH, clamped.h));

            return { x: startX, y: startY, w: finalW, h: finalH };
        }

        function snapAllWidgetsToGrid() {
            for (let i = 0; i < widgetRepeater.count; i++) {
                let proxy = widgetRepeater.itemAt(i);
                if (!proxy || !proxy.preview || proxy.preview.status !== Loader.Ready) continue;

                let row = activeWidgetsModel.get(i);
                let res = snapBoxToGrid(proxy.preview.item, row.wX, row.wY, row.wWidth, row.wHeight);

                if (res.x !== row.wX || res.y !== row.wY || res.w !== row.wWidth || res.h !== row.wHeight) {
                    activeWidgetsModel.setProperty(i, "wX", res.x);
                    activeWidgetsModel.setProperty(i, "wY", res.y);
                    activeWidgetsModel.setProperty(i, "wWidth", res.w);
                    activeWidgetsModel.setProperty(i, "wHeight", res.h);
                    proxy.finalizeSync();
                }
            }
        }

        function openImagePicker(targetIdx, targetId, curImg, isRound) {
            imagePickerLoader.active = true;
            let trigger = () => {
                if (imagePickerLoader.item) {
                    imagePickerLoader.item.targetWidgetIndex = targetIdx;
                    imagePickerLoader.item.targetWidgetId = String(targetId);
                    imagePickerLoader.item.openPicker(curImg, isRound);
                }
            };
            if (imagePickerLoader.status === Loader.Ready) {
                trigger();
            } else {
                let conn = function() {
                    if (imagePickerLoader.status === Loader.Ready) {
                        imagePickerLoader.statusChanged.disconnect(conn);
                        trigger();
                    }
                };
                imagePickerLoader.statusChanged.connect(conn);
            }
        }

        function addWidget(typeKey) {
            let t = WidgetRegistry.types[typeKey];
            if (!t) return;
            if (t.requiresFilePicker) {
                openImagePicker(-1, "", "", false);
                return;
            }
            let def = WidgetRegistry.defaultSize(typeKey);
            let defW = def.w;
            let defH = def.h;
            let spawnX = Math.max(0, (redactorMode.safeWidth - s(defW)) / 2);
            let spawnY = Math.max(0, (redactorMode.safeHeight - s(defH)) / 2);
            let newId = "w_" + Date.now() + "_" + Math.floor(Math.random() * 1000);

            if (redactorMode.gridEnabled) {
                let snapped = redactorMode.snapBoxToGrid(null, spawnX, spawnY, defW, defH);
                spawnX = snapped.x;
                spawnY = snapped.y;
                defW = snapped.w;
                defH = snapped.h;
            }

            let defVar = WidgetRegistry.defaultVariant(typeKey);

            activeWidgetsModel.append({
                "wType": typeKey,
                "wVariant": defVar,
                "wX": spawnX,
                "wY": spawnY,
                "wWidth": defW,
                "wHeight": defH,
                "wOpacity": 1.0,
                "wRotation": 0,
                "wImagePath": "",
                "wId": newId
            });

            redactorMode.topZ += 1;
            redactorMode.selectedId = newId;
            WidgetSync.addWidget(redactorWindow.safeMonitorName, newId, typeKey, spawnX, spawnY, defW, defH, 1.0, "", 0);
            WidgetSync.bringToFront(redactorWindow.safeMonitorName, newId);
            redactorWindow.sendIpc("add", [newId, typeKey, spawnX.toString(), spawnY.toString(), defW.toString(), defH.toString(), "1.0", "", "0"]);
            redactorWindow.sendIpc("bringToFront", [newId]);
            redactorMode.updateToolbarObscured();
        }

        function handleAdditionalAction(action, itemIndex, itemId, proxy) {
            if (action === "pickImage") {
                let curImg = activeWidgetsModel.get(itemIndex) ? (activeWidgetsModel.get(itemIndex).wImagePath || "") : "";
                openImagePicker(itemIndex, itemId, curImg, proxy.wVariant === "round");
            } else if (action === "stretchWidth") {
                let item = activeWidgetsModel.get(itemIndex);
                if (!item) return;

                let rot = Math.abs(Math.round(proxy.wRotation || 0)) % 360;
                if (rot % 180 === 0) {
                    item.wX = 0;
                    item.wWidth = redactorMode.safeWidth;
                } else {
                    item.wY = 0;
                    item.wWidth = redactorMode.safeHeight;
                }
                proxy.finalizeSync();
            }
        }

        function resolveThemeColor(colorName) {
            if (colorName === "mauve") return ThemeBackend.mauve;
            if (colorName === "surface0") return ThemeBackend.surface0;
            if (colorName === "surface1") return ThemeBackend.surface1;
            if (colorName === "crust") return ThemeBackend.crust;
            if (colorName === "base") return ThemeBackend.base;
            if (colorName === "red") return ThemeBackend.red;
            return ThemeBackend.text;
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.4)
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: redactorMode.selectedId = ""
        }

        Rectangle {
            x: redactorMode.activeGuideX
            y: 0
            width: s(1)
            height: parent.height
            color: ThemeBackend.mauve
            visible: redactorMode.activeGuideX >= 0
            z: 100000
        }

        Rectangle {
            x: 0
            y: redactorMode.activeGuideY
            width: parent.width
            height: s(1)
            color: ThemeBackend.mauve
            visible: redactorMode.activeGuideY >= 0
            z: 100000
        }

        Item {
            id: workspaceArea
            anchors.fill: parent

            Loader {
                anchors.fill: parent
                active: redactorMode.gridEnabled
                sourceComponent: Canvas {
                    id: gridCanvas
                    anchors.fill: parent
                    property real stepSize: s(20)

                    Connections {
                        target: redactorMode
                        function onWidthChanged() { gridCanvas.requestPaint() }
                        function onHeightChanged() { gridCanvas.requestPaint() }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.1);
                        ctx.lineWidth = 1;
                        ctx.beginPath();

                        for (let x = 0; x <= width; x += stepSize) {
                            ctx.moveTo(x, 0);
                            ctx.lineTo(x, height);
                        }
                        for (let y = 0; y <= height; y += stepSize) {
                            ctx.moveTo(0, y);
                            ctx.lineTo(width, y);
                        }
                        ctx.stroke();
                    }
                }
            }

            Repeater {
                id: widgetRepeater
                model: activeWidgetsModel
                delegate: Item {
                    id: widgetProxy
                    property real wRotation: (model.wRotation !== undefined && !isNaN(model.wRotation)) ? model.wRotation : 0

                    x: model.wX
                    y: model.wY
                    width: (Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 === 0) ? model.wWidth : model.wHeight
                    height: (Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 === 0) ? model.wHeight : model.wWidth

                    property int currentZ: index
                    z: (widgetProxy.isSelected ? 50000 : 0) + currentZ
                    opacity: (redactorMode.selectedId === "" || widgetProxy.isSelected) ? 1.0 : 0.6
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Component.onCompleted: {
                        if (!redactorMode.isInitializing) {
                            redactorMode.topZ += 1;
                            widgetProxy.currentZ = redactorMode.topZ;
                        }
                    }

                    function bringToFront() {
                        redactorMode.topZ += 1;
                        widgetProxy.currentZ = redactorMode.topZ;
                        WidgetSync.bringToFront(redactorWindow.safeMonitorName, String(widgetProxy.wId));
                        redactorWindow.sendIpc("bringToFront", [String(widgetProxy.wId)]);
                    }

                    property real selectionGap: s(20)

                    property alias preview: preview
                    property string wType: model.wType || ""
                    property string wVariant: model.wVariant || ""
                    property string wImagePath: model.wImagePath || ""
                    property string wId: model.wId || ""
                    property real wOpacity: model.wOpacity !== undefined ? model.wOpacity : 1.0
                    property int wIndex: index

                    property bool isSelected: redactorMode.selectedId === widgetProxy.wId
                    property bool hasUnsyncedChanges: false

                    property var savedAspects: ({})

                    Connections {
                        target: baseSelectMa
                        function onPressedChanged() {
                            if (!baseSelectMa.pressed) {
                                bottomChrome.posMode = bottomChrome.calculatedPosMode;
                            }
                        }
                    }

                    function applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, mouseArea, edges, isCorner) {
                        let localPos = mouseArea.mapToItem(workspaceArea, mouse.x, mouse.y);
                        let dx = localPos.x - startMouseX;
                        let dy = localPos.y - startMouseY;

                        let rot = widgetProxy.wRotation || 0;
                        let rad = rot * Math.PI / 180.0;
                        let cos = Math.cos(rad);
                        let sin = Math.sin(rad);

                        let ldx = dx * cos + dy * sin;
                        let ldy = -dx * sin + dy * cos;

                        let passLdx = isCorner ? ldx : (edges.left || edges.right ? ldx : 0);
                        let passLdy = isCorner ? ldy : (edges.top || edges.bottom ? ldy : 0);

                        let res = redactorMode.calculateResize(preview.item, startWidgetX, startWidgetY, startWidth, startHeight, passLdx, passLdy, edges, isCorner, widgetProxy.wRotation);
                        let finalW = res.w;
                        let finalH = res.h;

                        let pxFixed = 0;
                        let pyFixed = 0;
                        if (edges.left) pxFixed = startWidth / 2.0;
                        else if (edges.right) pxFixed = -startWidth / 2.0;
                        if (edges.top) pyFixed = startHeight / 2.0;
                        else if (edges.bottom) pyFixed = -startHeight / 2.0;

                        let pxFixedNew = 0;
                        let pyFixedNew = 0;
                        if (edges.left) pxFixedNew = finalW / 2.0;
                        else if (edges.right) pxFixedNew = -finalW / 2.0;
                        if (edges.top) pyFixedNew = finalH / 2.0;
                        else if (edges.bottom) pyFixedNew = -finalH / 2.0;

                        let curBW = (Math.abs(Math.round(rot)) % 180 === 0) ? startWidth : startHeight;
                        let curBH = (Math.abs(Math.round(rot)) % 180 === 0) ? startHeight : startWidth;
                        let startCX = startWidgetX + curBW / 2.0;
                        let startCY = startWidgetY + curBH / 2.0;

                        let fixedX = startCX + pxFixed * cos - pyFixed * sin;
                        let fixedY = startCY + pxFixed * sin + pyFixed * cos;

                        let newCX = fixedX - (pxFixedNew * cos - pyFixedNew * sin);
                        let newCY = fixedY - (pxFixedNew * sin + pyFixedNew * cos);

                        let nextBW = (Math.abs(Math.round(rot)) % 180 === 0) ? finalW : finalH;
                        let nextBH = (Math.abs(Math.round(rot)) % 180 === 0) ? finalH : finalW;

                        let newX = newCX - nextBW / 2.0;
                        let newY = newCY - nextBH / 2.0;

                        let mX = Math.max(0, redactorMode.safeWidth - nextBW);
                        let mY = Math.max(0, redactorMode.safeHeight - nextBH);
                        newX = Math.max(0, Math.min(mX, newX));
                        newY = Math.max(0, Math.min(mY, newY));

                        if (redactorMode.gridEnabled) {
                            let gridStep = s(20);
                            newX = Math.round(newX / gridStep) * gridStep;
                            newY = Math.round(newY / gridStep) * gridStep;
                            newX = Math.max(0, Math.min(mX, newX));
                            newY = Math.max(0, Math.min(mY, newY));
                        }

                        model.wWidth = finalW;
                        model.wHeight = finalH;
                        model.wX = newX;
                        model.wY = newY;

                        widgetProxy.triggerSync();
                    }

                    function rotateWidget() {
                        let currentRot = Math.abs(Math.round(widgetProxy.wRotation || 0)) % 360;
                        let nextRot = currentRot + 90;

                        let curBW = (currentRot % 180 === 0) ? model.wWidth : model.wHeight;
                        let curBH = (currentRot % 180 === 0) ? model.wHeight : model.wWidth;

                        let centerX = model.wX + curBW / 2.0;
                        let centerY = model.wY + curBH / 2.0;

                        let unscaledBW = (nextRot % 180 === 0) ? model.wWidth : model.wHeight;
                        let unscaledBH = (nextRot % 180 === 0) ? model.wHeight : model.wWidth;

                        let limitX = redactorMode.safeWidth;
                        let limitY = redactorMode.safeHeight;

                        if (toolbar && toolbar.visible && toolbar.opacity > 0.1 && toolbar.y > centerY) {
                            limitY = toolbar.y;
                        }

                        let maxBW = Math.max(20, 2.0 * Math.min(centerX, limitX - centerX));
                        let maxBH = Math.max(20, 2.0 * Math.min(centerY, limitY - centerY));

                        let scaleX = (maxBW > 0 && unscaledBW > maxBW) ? (maxBW / unscaledBW) : 1.0;
                        let scaleY = (maxBH > 0 && unscaledBH > maxBH) ? (maxBH / unscaledBH) : 1.0;
                        let scale = Math.min(scaleX, scaleY);

                        let targetW = model.wWidth;
                        let targetH = model.wHeight;

                        if (scale < 1.0) {
                            targetW = model.wWidth * scale;
                            targetH = model.wHeight * scale;
                        }

                        let clamped = redactorMode.clampResize(preview.item, targetW, targetH, 0, 0, true);
                        let finalW = clamped.w;
                        let finalH = clamped.h;

                        let nextBW = (nextRot % 180 === 0) ? finalW : finalH;
                        let nextBH = (nextRot % 180 === 0) ? finalH : finalW;

                        let newX = centerX - nextBW / 2.0;
                        let newY = centerY - nextBH / 2.0;

                        let mX = Math.max(0, redactorMode.safeWidth - nextBW);
                        let mY = Math.max(0, redactorMode.safeHeight - nextBH);
                        newX = Math.max(0, Math.min(mX, newX));
                        newY = Math.max(0, Math.min(mY, newY));

                        if (redactorMode.gridEnabled) {
                            let gridStep = s(20);
                            newX = Math.round(newX / gridStep) * gridStep;
                            newY = Math.round(newY / gridStep) * gridStep;
                            newX = Math.max(0, Math.min(mX, newX));
                            newY = Math.max(0, Math.min(mY, newY));
                        }

                        model.wWidth = finalW;
                        model.wHeight = finalH;
                        model.wRotation = nextRot;
                        model.wX = newX;
                        model.wY = newY;

                        WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), nextRot);
                        redactorWindow.sendIpc("rotate", [String(widgetProxy.wId), nextRot.toString()]);
                        finalizeSync();
                    }

                    function getDefaultSize(loaderItem) {
                        let defSize = WidgetRegistry.defaultSize(widgetProxy.wType);
                        let defW = defSize.w;
                        let defH = defSize.h;
                        if (loaderItem && loaderItem.minAspect !== undefined && loaderItem.maxAspect !== undefined && loaderItem.minAspect === loaderItem.maxAspect && loaderItem.minAspect > 0) {
                            let aspect = loaderItem.minAspect;
                            if (aspect === 1.0) {
                                defW = 180;
                                defH = 180;
                            } else {
                                defH = 120;
                                defW = Math.round(defH * aspect);
                            }
                        }
                        return { w: defW, h: defH };
                    }

                    function applyVariant(variantId) {
                        if (widgetProxy.wVariant === variantId) return;

                        let currentAspect = model.wWidth / model.wHeight;
                        savedAspects[widgetProxy.wVariant] = currentAspect;

                        let targetAspect = savedAspects[variantId];

                        model.wVariant = variantId;

                        if (targetAspect) {
                            let area = model.wWidth * model.wHeight;
                            let newH = Math.max(10, Math.sqrt(area / targetAspect));
                            let newW = Math.max(10, newH * targetAspect);
                            model.wWidth = newW;
                            model.wHeight = newH;
                        }

                        WidgetSync.setVariant(redactorWindow.safeMonitorName, String(widgetProxy.wId), variantId);
                        redactorWindow.sendIpc("variant", [String(widgetProxy.wId), variantId]);
                        finalizeSync();
                    }

                    function resetWidgetSize() {
                        let currentRot = Math.abs(Math.round(widgetProxy.wRotation || 0)) % 360;
                        let curBW = (currentRot % 180 === 0) ? model.wWidth : model.wHeight;
                        let curBH = (currentRot % 180 === 0) ? model.wHeight : model.wWidth;
                        let cx = model.wX + curBW / 2.0;
                        let cy = model.wY + curBH / 2.0;

                        let def = getDefaultSize(preview.item);
                        let clamped = redactorMode.clampResize(preview.item, def.w, def.h, 0, 0, true);
                        let finalW = clamped.w;
                        let finalH = clamped.h;

                        let newX = cx - finalW / 2.0;
                        let newY = cy - finalH / 2.0;

                        let mX = Math.max(0, redactorMode.safeWidth - finalW);
                        let mY = Math.max(0, redactorMode.safeHeight - finalH);
                        newX = Math.max(0, Math.min(mX, newX));
                        newY = Math.max(0, Math.min(mY, newY));

                        if (redactorMode.gridEnabled) {
                            let snapped = redactorMode.snapBoxToGrid(preview.item, newX, newY, finalW, finalH);
                            newX = snapped.x;
                            newY = snapped.y;
                            finalW = snapped.w;
                            finalH = snapped.h;
                        }

                        model.wOpacity = 1.0;
                        model.wRotation = 0;
                        model.wWidth = finalW;
                        model.wHeight = finalH;
                        model.wX = newX;
                        model.wY = newY;

                        WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), 0);
                        redactorWindow.sendIpc("rotate", [String(widgetProxy.wId), "0"]);
                        finalizeSync();
                    }

                    Timer {
                        id: syncTimer
                        interval: 100
                        running: false
                        repeat: true
                        onTriggered: {
                            if (!widgetProxy.hasUnsyncedChanges) {
                                running = false;
                                return;
                            }
                            widgetProxy.hasUnsyncedChanges = false;
                            let curOp = widgetProxy.wOpacity;
                            let curRot = widgetProxy.wRotation;
                            WidgetSync.setGeometry(redactorWindow.safeMonitorName, String(widgetProxy.wId), model.wX, model.wY, model.wWidth, model.wHeight, curOp, curRot);
                        }
                    }

                    function triggerSync() {
                        if (redactorMode.isInitializing) return;
                        redactorMode.queueUpdateToolbarObscured();
                        widgetProxy.hasUnsyncedChanges = true;
                        if (!syncTimer.running) {
                            syncTimer.restart();
                        }
                    }

                    function finalizeSync() {
                        toolbarCheckTimer.stop();
                        syncTimer.stop();
                        widgetProxy.hasUnsyncedChanges = false;
                        let curOp = widgetProxy.wOpacity;
                        let curRot = widgetProxy.wRotation;
                        WidgetSync.setGeometry(redactorWindow.safeMonitorName, String(widgetProxy.wId), model.wX, model.wY, model.wWidth, model.wHeight, curOp, curRot);
                        WidgetSync.setOpacity(redactorWindow.safeMonitorName, String(widgetProxy.wId), curOp);
                        WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), curRot);
                        WidgetSync.bringToFront(redactorWindow.safeMonitorName, String(widgetProxy.wId));
                        redactorWindow.sendIpc("geometry", [String(widgetProxy.wId), model.wX.toString(), model.wY.toString(), model.wWidth.toString(), model.wHeight.toString(), curOp.toString(), curRot.toString()]);
                        redactorWindow.sendIpc("opacity", [String(widgetProxy.wId), curOp.toString()]);
                        redactorWindow.sendIpc("rotate", [String(widgetProxy.wId), curRot.toString()]);
                        redactorWindow.sendIpc("bringToFront", [String(widgetProxy.wId)]);
                        redactorMode.updateToolbarObscured();
                    }

                    MouseArea {
                        id: baseSelectMa
                        z: 0
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        property real startDragX
                        property real startDragY
                        property real startWidgetX
                        property real startWidgetY

                        onPressed: (mouse) => {
                            redactorMode.selectedId = widgetProxy.wId;
                            widgetProxy.bringToFront();
                            let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                            startDragX = localPos.x;
                            startDragY = localPos.y;
                            startWidgetX = widgetProxy.x;
                            startWidgetY = widgetProxy.y;
                        }

                        onPositionChanged: (mouse) => {
                            if (pressed) {
                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                let dx = localPos.x - startDragX;
                                let dy = localPos.y - startDragY;

                                let rawX = startWidgetX + dx;
                                let rawY = startWidgetY + dy;

                                let snapInfo = redactorMode.calculateSnap(widgetProxy, rawX, rawY);

                                model.wX = snapInfo.x;
                                model.wY = snapInfo.y;

                                redactorMode.activeGuideX = snapInfo.guideX;
                                redactorMode.activeGuideY = snapInfo.guideY;

                                widgetProxy.triggerSync();
                            }
                        }

                        onReleased: {
                            redactorMode.activeGuideX = -1;
                            redactorMode.activeGuideY = -1;
                            widgetProxy.finalizeSync();
                        }

                        onCanceled: {
                            redactorMode.activeGuideX = -1;
                            redactorMode.activeGuideY = -1;
                            widgetProxy.finalizeSync();
                        }
                    }

                    Item {
                        id: rotatableContainer
                        z: 1
                        width: model.wWidth
                        height: model.wHeight
                        anchors.centerIn: parent
                        rotation: widgetProxy.wRotation

                        Loader {
                            id: preview
                            property string wImagePath: widgetProxy.wImagePath
                            property string imagePath: widgetProxy.wImagePath
                            property string path: widgetProxy.wImagePath
                            anchors.fill: parent
                            opacity: widgetProxy.isSelected ? Math.max(0.35, widgetProxy.wOpacity) : widgetProxy.wOpacity
                            source: WidgetRegistry.faceFile(widgetProxy.wType, widgetProxy.wVariant)
                            onLoaded: {
                                if (item) {
                                    if (item.imagePath !== undefined) {
                                        item.imagePath = Qt.binding(() => widgetProxy.wImagePath);
                                    }
                                    if (item.wImagePath !== undefined) {
                                        item.wImagePath = Qt.binding(() => widgetProxy.wImagePath);
                                    }
                                    if (item.path !== undefined) {
                                        item.path = Qt.binding(() => widgetProxy.wImagePath);
                                    }
                                    if (item.source !== undefined && typeof item.source === "string") {
                                        item.source = Qt.binding(() => widgetProxy.wImagePath);
                                    }
                                    let res = redactorMode.gridEnabled
                                        ? redactorMode.snapBoxToGrid(item, model.wX, model.wY, model.wWidth, model.wHeight)
                                        : redactorMode.clampResize(item, model.wWidth, model.wHeight, 0, 0, true);

                                    let changed = false;
                                    if (res.x !== undefined && (model.wX !== res.x || model.wY !== res.y)) {
                                        model.wX = res.x;
                                        model.wY = res.y;
                                        changed = true;
                                    }
                                    if (res.w !== model.wWidth || res.h !== model.wHeight) {
                                        model.wWidth = res.w;
                                        model.wHeight = res.h;
                                        changed = true;
                                    }
                                    if (changed && !redactorMode.isInitializing) {
                                        widgetProxy.triggerSync();
                                    }
                                }
                            }
                        }

                        Item {
                            id: selectionUI
                            z: 30
                            anchors.fill: parent
                            anchors.margins: -widgetProxy.selectionGap
                            opacity: widgetProxy.isSelected ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            property bool isAspectLocked: preview.item && preview.item.minAspect !== undefined && preview.item.maxAspect !== undefined && preview.item.minAspect === preview.item.maxAspect && preview.item.minAspect > 0
                            readonly property bool isRotated90: Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 !== 0

                            Rectangle {
                                id: selectionBox
                                anchors.fill: parent
                                color: "transparent"
                                border.width: s(2)
                                border.color: ThemeBackend.mauve
                                radius: 0
                            }

                            Item {
                                id: cornerBrackets
                                anchors.fill: parent

                                property real cornerSize: s(16)
                                property real lineWidth: s(2)
                                property color cornerColor: ThemeBackend.mauve

                                Rectangle { x: 0; y: 0; width: cornerBrackets.cornerSize; height: cornerBrackets.lineWidth; color: cornerBrackets.cornerColor; radius: 0 }
                                Rectangle { x: 0; y: 0; width: cornerBrackets.lineWidth; height: cornerBrackets.cornerSize; color: cornerBrackets.cornerColor; radius: 0 }

                                Rectangle { x: parent.width - cornerBrackets.cornerSize; y: 0; width: cornerBrackets.cornerSize; height: cornerBrackets.lineWidth; color: cornerBrackets.cornerColor; radius: 0 }
                                Rectangle { x: parent.width - cornerBrackets.lineWidth; y: 0; width: cornerBrackets.lineWidth; height: cornerBrackets.cornerSize; color: cornerBrackets.cornerColor; radius: 0 }

                                Rectangle { x: 0; y: parent.height - cornerBrackets.lineWidth; width: cornerBrackets.cornerSize; height: cornerBrackets.lineWidth; color: cornerBrackets.cornerColor; radius: 0 }
                                Rectangle { x: 0; y: parent.height - cornerBrackets.cornerSize; width: cornerBrackets.lineWidth; height: cornerBrackets.cornerSize; color: cornerBrackets.cornerColor; radius: 0 }

                                Rectangle { x: parent.width - cornerBrackets.cornerSize; y: parent.height - cornerBrackets.lineWidth; width: cornerBrackets.cornerSize; height: cornerBrackets.lineWidth; color: cornerBrackets.cornerColor; radius: 0 }
                                Rectangle { x: parent.width - cornerBrackets.lineWidth; y: parent.height - cornerBrackets.cornerSize; width: cornerBrackets.lineWidth; height: cornerBrackets.cornerSize; color: cornerBrackets.cornerColor; radius: 0 }
                            }

                            MouseArea {
                                id: resizeTl
                                z: 20
                                width: s(24); height: s(24)
                                anchors.left: parent.left; anchors.top: parent.top
                                anchors.margins: -s(6)
                                enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTl, {left: true, top: true, right: false, bottom: false}, true);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeTr
                                z: 20
                                width: s(24); height: s(24)
                                anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: -s(6)
                                enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTr, {left: false, top: true, right: true, bottom: false}, true);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeBl
                                z: 20
                                width: s(24); height: s(24)
                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                anchors.margins: -s(6)
                                enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBl, {left: true, top: false, right: false, bottom: true}, true);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeBr
                                z: 20
                                width: s(24); height: s(24)
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: -s(6)
                                enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBr, {left: false, top: false, right: true, bottom: true}, true);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeTop
                                z: 20
                                height: s(16)
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.leftMargin: s(18); anchors.rightMargin: s(18); anchors.topMargin: -s(8)
                                visible: !selectionUI.isAspectLocked
                                enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeHorCursor : Qt.SizeVerCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTop, {left: false, top: true, right: false, bottom: false}, false);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeBottom
                                z: 20
                                height: s(16)
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.leftMargin: s(18); anchors.rightMargin: s(18); anchors.bottomMargin: -s(8)
                                visible: !selectionUI.isAspectLocked
                                enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeHorCursor : Qt.SizeVerCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBottom, {left: false, top: false, right: false, bottom: true}, false);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeLeft
                                z: 20
                                width: s(16)
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                anchors.topMargin: s(18); anchors.bottomMargin: s(18); anchors.leftMargin: -s(8)
                                visible: !selectionUI.isAspectLocked
                                enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeVerCursor : Qt.SizeHorCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeLeft, {left: true, top: false, right: false, bottom: false}, false);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }

                            MouseArea {
                                id: resizeRight
                                z: 20
                                width: s(16)
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                                anchors.topMargin: s(18); anchors.bottomMargin: s(18); anchors.rightMargin: -s(8)
                                visible: !selectionUI.isAspectLocked
                                enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: selectionUI.isRotated90 ? Qt.SizeVerCursor : Qt.SizeHorCursor

                                property real startMouseX
                                property real startMouseY
                                property real startWidth
                                property real startHeight
                                property real startWidgetX
                                property real startWidgetY

                                onPressed: (mouse) => {
                                    widgetProxy.bringToFront();
                                    let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                    startMouseX = localPos.x;
                                    startMouseY = localPos.y;
                                    startWidth = model.wWidth;
                                    startHeight = model.wHeight;
                                    startWidgetX = model.wX;
                                    startWidgetY = model.wY;
                                }

                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeRight, {left: false, top: false, right: true, bottom: false}, false);
                                    }
                                }

                                onReleased: {
                                    widgetProxy.finalizeSync();
                                }

                                onCanceled: {
                                    widgetProxy.finalizeSync();
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: bottomChrome
                        z: 40
                        opacity: (widgetProxy.isSelected && !baseSelectMa.pressed) ? 1.0 : 0.0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        spacing: s(6)

                        readonly property real limitY: (toolbar.opacity > 0.1 && !redactorMode.toolbarObscured) ? toolbar.y : redactorMode.safeHeight

                        readonly property bool fitsBelow: (widgetProxy.y + widgetProxy.height + widgetProxy.selectionGap + implicitHeight + s(8)) <= limitY
                        readonly property bool fitsAbove: (widgetProxy.y - widgetProxy.selectionGap - implicitHeight - s(8)) >= 0

                        readonly property bool fitsRight: (widgetProxy.x + widgetProxy.width + widgetProxy.selectionGap + implicitWidth + s(8)) <= redactorMode.safeWidth
                        readonly property bool fitsLeft: (widgetProxy.x - widgetProxy.selectionGap - implicitWidth - s(8)) >= 0

                        readonly property int calculatedPosMode: {
                            if (fitsBelow) return 0;
                            if (fitsAbove) return 1;
                            if (fitsRight) return 2;
                            if (fitsLeft) return 3;
                            return 4;
                        }

                        property int posMode: 0

                        onCalculatedPosModeChanged: {
                            if (!baseSelectMa.pressed) {
                                posMode = calculatedPosMode;
                            }
                        }

                        Component.onCompleted: {
                            posMode = calculatedPosMode;
                        }

                        x: {
                            if (posMode === 2) {
                                return widgetProxy.width + widgetProxy.selectionGap + s(8);
                            } else if (posMode === 3) {
                                return -widgetProxy.selectionGap - implicitWidth - s(8);
                            } else {
                                let idealX = (widgetProxy.width - implicitWidth) / 2;
                                let screenX = widgetProxy.x + idealX;
                                let clampedScreenX = Math.max(s(8), Math.min(redactorMode.safeWidth - implicitWidth - s(8), screenX));
                                return clampedScreenX - widgetProxy.x;
                            }
                        }

                        y: {
                            if (posMode === 0) {
                                return widgetProxy.height + widgetProxy.selectionGap + s(8);
                            } else if (posMode === 1) {
                                return -widgetProxy.selectionGap - implicitHeight - s(8);
                            } else if (posMode === 2 || posMode === 3) {
                                let idealY = (widgetProxy.height - implicitHeight) / 2;
                                let screenY = widgetProxy.y + idealY;
                                let clampedScreenY = Math.max(s(8), Math.min(limitY - implicitHeight - s(8), screenY));
                                return clampedScreenY - widgetProxy.y;
                            } else {
                                let screenY = Math.min(limitY - implicitHeight - s(15), Math.max(s(15), widgetProxy.y + widgetProxy.height - implicitHeight - s(15)));
                                return screenY - widgetProxy.y;
                            }
                        }

                        property var variantsList: WidgetRegistry.variantList(widgetProxy.wType)
                        property bool hasVariants: variantsList.length > 1

                        RowLayout {
                            spacing: s(4)
                            Layout.alignment: Qt.AlignHCenter

                            Rectangle {
                                id: pxReadoutPill
                                implicitWidth: pxReadoutText.implicitWidth + s(16)
                                implicitHeight: s(34)
                                color: ThemeBackend.surface0
                                radius: ThemeBackend.borderRadius

                                Text {
                                    id: pxReadoutText
                                    anchors.centerIn: parent
                                    text: Math.round(model.wWidth) + "x" + Math.round(model.wHeight)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(12)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }
                            }

                            Rectangle {
                                id: arReadoutPill
                                implicitWidth: arReadoutText.implicitWidth + s(16)
                                implicitHeight: s(34)
                                color: ThemeBackend.surface0
                                radius: ThemeBackend.borderRadius

                                Text {
                                    id: arReadoutText
                                    anchors.centerIn: parent
                                    text: (model.wWidth / model.wHeight).toFixed(2) + ":1"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(12)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }
                            }

                            Rectangle {
                                id: pctReadoutPill
                                implicitWidth: pctReadoutText.implicitWidth + s(16)
                                implicitHeight: s(34)
                                color: ThemeBackend.surface0
                                radius: ThemeBackend.borderRadius

                                Text {
                                    id: pctReadoutText
                                    anchors.centerIn: parent
                                    text: {
                                        let def = widgetProxy.getDefaultSize(preview.item);
                                        return Math.round((model.wWidth / def.w) * 100) + "%";
                                    }
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(12)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }
                            }

                            Repeater {
                                model: WidgetRegistry.additionalSettings(widgetProxy.wType, "top")
                                delegate: IconButton {
                                    size: s(34)
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonIcon: modelData.icon || ""
                                    iconFontSize: s(modelData.iconFontSize || 16)
                                    accentColor: redactorMode.resolveThemeColor(modelData.accentColor || "surface0")
                                    textColor: redactorMode.resolveThemeColor(modelData.textColor || "mauve")
                                    onClicked: redactorMode.handleAdditionalAction(modelData.action, widgetProxy.wIndex, widgetProxy.wId, widgetProxy)
                                }
                            }

                            IconButton {
                                id: rotateBtn
                                size: s(34)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰑖"
                                iconFontSize: s(16)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                onClicked: widgetProxy.rotateWidget()
                            }

                            IconButton {
                                id: resetBtn
                                size: s(34)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰑐"
                                iconFontSize: s(15)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                onClicked: widgetProxy.resetWidgetSize()
                            }

                            DeleteButton {
                                id: closeBtn
                                size: s(34)
                                cornerRadius: ThemeBackend.borderRadius
                                iconFontSize: s(18)

                                onClicked: {
                                    let rmId = String(widgetProxy.wId);
                                    if (redactorMode.selectedId === rmId) {
                                        redactorMode.selectedId = "";
                                    }
                                    WidgetSync.removeWidget(redactorWindow.safeMonitorName, rmId);
                                    redactorWindow.sendIpc("remove", [rmId]);
                                    activeWidgetsModel.remove(widgetProxy.wIndex, 1);
                                    if (activeWidgetsModel.count === 0) {
                                        redactorMode.selectedId = "";
                                    }
                                    redactorMode.updateToolbarObscured();
                                }
                            }
                        }

                        RowLayout {
                            spacing: s(6)
                            Layout.alignment: Qt.AlignHCenter

                            Repeater {
                                model: WidgetRegistry.additionalSettings(widgetProxy.wType, "bottom")
                                delegate: IconButton {
                                    size: s(34)
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonIcon: modelData.icon || ""
                                    iconFontSize: s(modelData.iconFontSize || 16)
                                    accentColor: redactorMode.resolveThemeColor(modelData.accentColor || "surface0")
                                    textColor: redactorMode.resolveThemeColor(modelData.textColor || "mauve")
                                    onClicked: redactorMode.handleAdditionalAction(modelData.action, widgetProxy.wIndex, widgetProxy.wId, widgetProxy)
                                }
                            }

                            Switch {
                                id: variantSwitch
                                property var variantsList: bottomChrome.variantsList
                                visible: bottomChrome.hasVariants
                                implicitHeight: s(34)
                                implicitWidth: Math.max(s(120), options.length * s(70))
                                accentColor: ThemeBackend.mauve
                                baseColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                activeTextColor: ThemeBackend.crust
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: s(11)
                                options: variantsList.map(v => v.label || v.id)

                                function updateCurrentIndex() {
                                    let curVar = widgetProxy.wVariant;
                                    for (let i = 0; i < variantsList.length; i++) {
                                        if (variantsList[i].id === curVar) {
                                            currentIndex = i;
                                            break;
                                        }
                                    }
                                }

                                Component.onCompleted: updateCurrentIndex()

                                Connections {
                                    target: widgetProxy
                                    function onWVariantChanged() {
                                        variantSwitch.updateCurrentIndex();
                                    }
                                }

                                onToggled: (idx) => {
                                    if (idx >= 0 && idx < variantsList.length) {
                                        widgetProxy.applyVariant(variantsList[idx].id);
                                    }
                                }
                            }

                            Rectangle {
                                id: opacityPill
                                implicitWidth: bottomChrome.hasVariants ? s(200) : s(280)
                                implicitHeight: s(34)
                                color: ThemeBackend.surface0
                                radius: ThemeBackend.borderRadius

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: s(10)
                                    anchors.rightMargin: s(10)
                                    spacing: s(8)

                                    Text {
                                        id: opReadoutText
                                        text: Math.round(widgetProxy.wOpacity * 100) + "%"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: s(11)
                                        font.bold: true
                                        color: ThemeBackend.text
                                        Layout.preferredWidth: s(32)
                                    }

                                    Draggable {
                                        id: opacitySlider
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: s(16)
                                        Layout.alignment: Qt.AlignVCenter
                                        from: 0.0
                                        to: 100.0
                                        value: Math.round(widgetProxy.wOpacity * 100)
                                        backgroundColor: ThemeBackend.surface1
                                        accentColor: ThemeBackend.mauve
                                        gradColor1: ThemeBackend.mauve
                                        gradColor2: Qt.lighter(ThemeBackend.mauve, 1.05)
                                        gradColor3: Qt.lighter(ThemeBackend.mauve, 1.10)
                                        cornerRadius: s(8)
                                        handleSize: s(16)
                                        handleColor: Qt.lighter(ThemeBackend.mauve, 1.15)
                                        handleHoverColor: Qt.lighter(ThemeBackend.mauve, 1.3)
                                        handleDragColor: Qt.lighter(ThemeBackend.mauve, 1.45)
                                        handleBorderColor: Qt.rgba(0, 0, 0, 0.2)
                                        showValueBubble: false

                                        Connections {
                                            target: widgetProxy
                                            function onWOpacityChanged() {
                                                opacitySlider.value = Math.round(widgetProxy.wOpacity * 100);
                                            }
                                        }

                                        onMoved: val => {
                                            model.wOpacity = val / 100.0;
                                            widgetProxy.triggerSync();
                                        }

                                        onDragFinished: {
                                            widgetProxy.finalizeSync();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            anchors.centerIn: workspaceArea
            visible: redactorMode.isReady && activeWidgetsModel.count === 0
            width: s(400)
            height: s(100)

            ColumnLayout {
                anchors.centerIn: parent
                spacing: s(8)

                Text {
                    text: I18n.t("widgets.redactor.no_widgets_active")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(20)
                    font.bold: true
                    color: ThemeBackend.text
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: I18n.t("widgets.redactor.click_to_add")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(14)
                    color: ThemeBackend.subtext0
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        FileView {
            id: layoutFile
            path: (Caching.getStateDir && redactorWindow.safeMonitorName) ? (Caching.getStateDir("widgets/" + redactorWindow.safeMonitorName) + "/layout.json") : ""
            watchChanges: false
            onLoaded: redactorMode.loadLayoutFromText(text())
        }

        function loadLayoutFromText(content) {
            let trimmed = (content || "").trim();
            activeWidgetsModel.clear();
            redactorMode.isInitializing = true;
            if (trimmed !== "" && trimmed !== "[]") {
                try {
                    let data = JSON.parse(trimmed);
                    redactorMode.topZ = data.length + 10;
                    for (let i = 0; i < data.length; i++) {
                        let item = data[i];
                        let type = item.wType || item.type || "time";
                        let variant = item.wVariant || item.variant || WidgetRegistry.defaultVariant(type);
                        let sVal = item.wScale !== undefined ? parseFloat(item.wScale) : 1.0;
                        let defSize = WidgetRegistry.defaultSize(type);
                        let defW = defSize.w;
                        let defH = defSize.h;
                        let w = item.wWidth !== undefined ? parseFloat(item.wWidth) : defW * sVal;
                        let h = item.wHeight !== undefined ? parseFloat(item.wHeight) : defH * sVal;
                        let op = item.wOpacity !== undefined ? parseFloat(item.wOpacity) : 1.0;
                        let rot = (item.wRotation !== undefined) ? parseFloat(item.wRotation) : (item.rotation !== undefined ? parseFloat(item.rotation) : 0);
                        if (isNaN(rot)) rot = 0;
                        rot = ((Math.round(rot) % 360) + 360) % 360;
                        let imgPath = item.wImagePath || item.imagePath || item.path || "";

                        activeWidgetsModel.append({
                            wType: type,
                            wVariant: variant,
                            wX: item.wX !== undefined ? parseFloat(item.wX) : 100,
                            wY: item.wY !== undefined ? parseFloat(item.wY) : 100,
                            wWidth: w,
                            wHeight: h,
                            wOpacity: op,
                            wRotation: rot,
                            wImagePath: imgPath,
                            wId: String(item.wId || item.id || ("w_" + Date.now() + "_" + i))
                        });
                    }
                } catch (e) {}
            }
            redactorMode.isReady = true;
            redactorMode.updateToolbarObscured();
            Qt.callLater(() => {
                WidgetSync.setRedactMode(redactorWindow.safeMonitorName, true);
                redactorWindow.sendIpc("setRedactMode", ["true"]);
                redactorWindow.sendBarIpc("setRedactMode", ["true"]);
            });
            initTimer.restart();
        }

        Timer {
            id: initTimer
            interval: 200
            repeat: false
            onTriggered: redactorMode.isInitializing = false
        }

        function reloadLayout() {
            layoutFile.reload();
        }

        Connections {
            target: redactorWindow
            function onSafeMonitorNameChanged() {
                redactorMode.reloadLayout();
            }
        }

        Component.onCompleted: {
            let envData = Quickshell.env("QS_WIDGET_DATA") || Quickshell.env("QS_LAYOUT_DATA") || Quickshell.env("QS_LAYOUT_JSON");
            if (envData && envData.trim() !== "") {
                redactorMode.loadLayoutFromText(envData);
            }
        }

        Item {
            id: toolbar
            implicitWidth: toolbarLayout.implicitWidth + s(32)
            width: implicitWidth
            height: s(100)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: s(24)
            anchors.horizontalCenter: parent.horizontalCenter
            z: 200000

            opacity: (activeWidgetsModel.count === 0 || redactorMode.selectedId === "" || !redactorMode.toolbarObscured) ? 1.0 : 0.0
            visible: opacity > 0
            enabled: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Rectangle {
                anchors.fill: parent
                color: ThemeBackend.base
                radius: ThemeBackend.borderRadius
            }

            RowLayout {
                id: toolbarLayout
                anchors.fill: parent
                anchors.margins: s(16)
                spacing: s(20)

                Repeater {
                    model: WidgetRegistry.typeList()
                    delegate: Loader {
                        Layout.alignment: Qt.AlignVCenter
                        sourceComponent: WidgetRegistry.toolbarComponent(modelData.id)
                        onLoaded: {
                            if (item) {
                                item.typeData = modelData;
                                item.redactor = redactorMode;
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: s(32)
                }

                RowLayout {
                    spacing: s(10)
                    Layout.alignment: Qt.AlignVCenter

                    IconButton {
                        size: s(40)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "󰕰"
                        iconOffsetX: -2
                        iconFontSize: s(20)
                        accentColor: redactorMode.gridEnabled ? ThemeBackend.mauve : ThemeBackend.surface0
                        textColor: redactorMode.gridEnabled ? ThemeBackend.crust : ThemeBackend.text
                        Layout.alignment: Qt.AlignVCenter

                        onClicked: {
                            let turningOn = !redactorMode.gridEnabled;
                            redactorMode.gridEnabled = turningOn;
                            if (turningOn) {
                                redactorMode.snapAllWidgetsToGrid();
                            }
                        }
                    }

                    IconButton {
                        size: s(40)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "󰑐"
                        iconFontSize: s(20)
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.text
                        Layout.alignment: Qt.AlignVCenter
                        visible: activeWidgetsModel.count > 0
                        iconOffsetX: -1
                        onClicked: redactorMode.removeAllWidgets()
                    }

                    ClickButton {
                        Layout.alignment: Qt.AlignVCenter
                        maxWidth: s(100)
                        implicitHeight: s(40)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: I18n.t("widgets.redactor.done")
                        textFontSize: s(14)
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        onClicked: redactorWindow.exitRedactor()
                    }
                }
            }
        }

        Loader {
            id: imagePickerLoader
            anchors.fill: parent
            z: 300000
            active: false
            sourceComponent: ImagePicker {
                rootObj: redactorMode
                property int targetWidgetIndex: -1
                property string targetWidgetId: ""

                onImageSelected: (filePath, fileName) => {
                    if (targetWidgetIndex >= 0 && targetWidgetId !== "") {
                        activeWidgetsModel.setProperty(targetWidgetIndex, "wImagePath", filePath);
                        WidgetSync.setImagePath(redactorWindow.safeMonitorName, targetWidgetId, filePath);
                        redactorWindow.sendIpc("imagePath", [targetWidgetId, filePath]);
                        targetWidgetIndex = -1;
                        targetWidgetId = "";
                    } else if (filePath !== "") {
                        let def = WidgetRegistry.defaultSize("image");
                        let defW = def.w;
                        let defH = def.h;
                        let spawnX = Math.max(0, (redactorMode.safeWidth - s(defW)) / 2);
                        let spawnY = Math.max(0, (redactorMode.safeHeight - s(defH)) / 2);
                        let newId = "w_" + Date.now() + "_" + Math.floor(Math.random() * 1000);

                        if (redactorMode.gridEnabled) {
                            let snapped = redactorMode.snapBoxToGrid(null, spawnX, spawnY, defW, defH);
                            spawnX = snapped.x;
                            spawnY = snapped.y;
                            defW = snapped.w;
                            defH = snapped.h;
                        }

                        activeWidgetsModel.append({
                            "wType": "image",
                            "wVariant": WidgetRegistry.defaultVariant("image"),
                            "wX": spawnX,
                            "wY": spawnY,
                            "wWidth": defW,
                            "wHeight": defH,
                            "wOpacity": 1.0,
                            "wRotation": 0,
                            "wImagePath": filePath,
                            "wId": newId
                        });

                        redactorMode.topZ += 1;
                        redactorMode.selectedId = newId;
                        WidgetSync.addWidget(redactorWindow.safeMonitorName, newId, "image", spawnX, spawnY, defW, defH, 1.0, filePath, 0);
                        WidgetSync.bringToFront(redactorWindow.safeMonitorName, newId);
                        redactorWindow.sendIpc("add", [newId, "image", spawnX.toString(), spawnY.toString(), defW.toString(), defH.toString(), "1.0", filePath, "0"]);
                        redactorWindow.sendIpc("bringToFront", [newId]);
                        redactorMode.updateToolbarObscured();
                    }
                }
            }
        }
    }
}
