import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"

Item {
    id: root

    property int requestedLayoutTemplate: 2

    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true

    property string iconFont: "Font Awesome 6 Free Solid"
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(val) {
        return typeof scaleFunc !== "undefined" ? scaleFunc(val) : val;
    }

    property real baseW: s(600)
    property real baseL: s(500)

    property real preferredWidth: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseL : baseW
    property real preferredExtraLength: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (root.safeActiveEdge === "right") return 180;
        if (root.safeActiveEdge === "bottom") return 90;
        if (root.safeActiveEdge === "top") return -90;
        return 0;
    }

    property string currentTool: "pen"
    property var toolKeys: ["pen", "brush", "fill", "eraser"]
    property int currentToolIndex: Math.max(0, toolKeys.indexOf(currentTool))

    property bool showSizeConfig: false
    property bool showColorPicker: false

    property var primaryHSV: ({ h: 0.74, s: 0.33, v: 0.97 })
    property var secondaryHSV: ({ h: 0.0, s: 0.0, v: 0.10 })
    property int activeColorSlot: 0
    
    property color primaryColor: Qt.hsva(primaryHSV.h, primaryHSV.s, primaryHSV.v, 1.0)
    property color secondaryColor: Qt.hsva(secondaryHSV.h, secondaryHSV.s, secondaryHSV.v, 1.0)
    property color currentColor: activeColorSlot === 0 ? primaryColor : secondaryColor

    property real penSizeRatio: 0.3
    property real brushSizeRatio: 0.4
    property real eraserSizeRatio: 0.6

    property real currentSizeRatio: {
        if (currentTool === "eraser") return eraserSizeRatio;
        if (currentTool === "brush") return brushSizeRatio;
        return penSizeRatio;
    }

    property real actualToolSize: {
        if (currentTool === "eraser") return s(8) + (currentSizeRatio * s(60));
        if (currentTool === "brush") return s(4) + (currentSizeRatio * s(40));
        return s(2) + (currentSizeRatio * s(30));
    }

    property color baseTextColor: ThemeBackend.text
    property color solidBgColor: ThemeBackend.mantle
    property color themeBaseColor: ThemeBackend.base
    
    property color panelBgColor: Qt.rgba(themeBaseColor.r, themeBaseColor.g, themeBaseColor.b, 0.85)
    property color panelBorderColor: Qt.rgba(baseTextColor.r, baseTextColor.g, baseTextColor.b, 0.15)

    property real minZoom: 0.1
    property real maxZoom: 5.0
    property real worldSize: 2048

    property var actionHistory: []
    property int historyStep: -1
    property int maxHistory: 50
    property var currentAction: null

    property var colorPalettes: [
        { 
            name: "Default", 
            colors: [
                ThemeBackend.red.toString(),
                ThemeBackend.peach.toString(),
                ThemeBackend.yellow.toString(),
                ThemeBackend.green.toString(),
                ThemeBackend.sapphire.toString(),
                ThemeBackend.blue.toString(),
                ThemeBackend.mauve.toString(),
                ThemeBackend.text.toString()
            ] 
        }
    ]
    property int activePaletteIndex: 0
    property string picturesDir: ""

    Process {
        id: getPicturesDir
        command: ["xdg-user-dir", "PICTURES"]
        running: true
        stdout: SplitParser {
            onRead: data => { root.picturesDir = data.trim() }
        }
    }

    FileView {
        id: palettesFile
        path: Caching.getStateDir("quickactions") + "/palettes.json"
        onDataChanged: {
            if (data) {
                try {
                    let parsed = JSON.parse(data);
                    if (parsed && parsed.length > 0) {
                        root.colorPalettes = parsed;
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: paletteSaveTimer
        interval: 500
        onTriggered: {
            let jsonStr = JSON.stringify(root.colorPalettes);
            Quickshell.exec(["sh", "-c", "echo '" + jsonStr + "' > " + palettesFile.path]);
        }
    }

    function addColorToPalette(colorStr) {
        let p = root.colorPalettes;
        if (!p[root.activePaletteIndex]) return;
        p[root.activePaletteIndex].colors.push(colorStr);
        root.colorPalettes = p;
        paletteSaveTimer.restart();
    }

    function commitAction(action) {
        var newHistory = root.actionHistory.slice(0, root.historyStep + 1);
        newHistory.push(action);
        
        if (newHistory.length > root.maxHistory) {
            newHistory.shift();
        }
        
        root.actionHistory = newHistory;
        root.historyStep = root.actionHistory.length - 1;
    }

    function undo() {
        if (root.historyStep >= 0) {
            root.historyStep--;
            triggerReplay();
        }
    }

    function redo() {
        if (root.historyStep < root.actionHistory.length - 1) {
            root.historyStep++;
            triggerReplay();
        }
    }

    function triggerReplay() {
        if (orientedRoot.children.length > 0) {
            drawCanvas._replayPending = true;
            drawCanvas.requestPaint();
        }
    }

    Shortcut { enabled: root.visible && root.isActiveTab; sequence: "Ctrl+Z"; onActivated: root.undo() }
    Shortcut { enabled: root.visible && root.isActiveTab; sequence: "Ctrl+Shift+Z"; onActivated: root.redo() }

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: root.solidBgColor
            z: -1
        }

        Item {
            id: cameraRig
            anchors.fill: parent
            clip: true

            function zoomBy(factor) {
                zoomContainer.scale = Math.max(root.minZoom, Math.min(zoomContainer.scale * factor, root.maxZoom));
            }

            PinchHandler {
                target: zoomContainer
                enabled: root.isActiveTab
                minimumScale: root.minZoom
                maximumScale: root.maxZoom
            }

            Item {
                id: zoomContainer
                width: root.worldSize
                height: root.worldSize
                
                x: (cameraRig.width - width) / 2
                y: (cameraRig.height - height) / 2
                
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                DragHandler {
                    target: zoomContainer
                    enabled: root.isActiveTab
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }

                Image {
                    anchors.fill: parent
                    fillMode: Image.Tile
                    
                    property real dotRadius: s(1.2)
                    property real dotSpacing: s(12)
                    property color dotC: root.baseTextColor
                    
                    source: `data:image/svg+xml;utf8,<svg width='${dotSpacing}' height='${dotSpacing}' xmlns='http://www.w3.org/2000/svg'><circle cx='${dotSpacing/2}' cy='${dotSpacing/2}' r='${dotRadius}' fill='rgb(${dotC.r*255},${dotC.g*255},${dotC.b*255})' fill-opacity='0.15'/></svg>`
                }

                Canvas {
                    id: drawCanvas
                    anchors.fill: parent
                    z: 1
                    
                    renderTarget: Canvas.FramebufferObject
                    
                    property real lastX: -1
                    property real lastY: -1
                    
                    property var _queue: []
                    property bool _clearPending: false
                    property bool _replayPending: false

                    function renderBrushLine(ctx, s, isLive) {
                        var bSize = s.penSize || root.s(18);
                        var segments = isLive ? [{x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2}] : s.segments;
                        
                        var bristleCount = Math.max(6, Math.floor(bSize * 0.6));
                        
                        ctx.globalCompositeOperation = "source-over";
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        var col = s.color;
                        
                        for (var b = 0; b < bristleCount; b++) {
                            var t = b / bristleCount;
                            var angle = t * Math.PI * 2;
                            var radius = (0.3 + (((b * 7 + 3) % 11) / 11) * 0.7) * (bSize / 2);
                            var offX = Math.cos(angle) * radius * 0.5;
                            var offY = Math.sin(angle) * radius * 0.5;
                            var alpha = 0.25 + (((b * 13 + 5) % 17) / 17) * 0.45;
                            var width = root.s(0.8) + (((b * 3 + 1) % 5) / 5) * root.s(1.6);
                            
                            ctx.globalAlpha = alpha;
                            ctx.lineWidth = width;
                            ctx.strokeStyle = col;
                            
                            ctx.beginPath();
                            ctx.moveTo(segments[0].x1 + offX, segments[0].y1 + offY);
                            for (var j = 0; j < segments.length; j++) {
                                ctx.lineTo(segments[j].x2 + offX, segments[j].y2 + offY);
                            }
                            ctx.stroke();
                        }
                        
                        ctx.globalAlpha = 1.0;
                    }

                    function applyToolStyle(ctx, tool, color, customSize) {
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        if (tool === "eraser") {
                            ctx.globalCompositeOperation = "destination-out";
                            ctx.lineWidth = customSize || root.actualToolSize;
                            ctx.strokeStyle = "rgba(0,0,0,1)";
                            ctx.globalAlpha = 1.0;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                        } else {
                            ctx.globalCompositeOperation = "source-over";
                            ctx.strokeStyle = color;
                            ctx.lineWidth = customSize || root.actualToolSize;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                            ctx.globalAlpha = 1.0;
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        
                        if (_replayPending) {
                            ctx.clearRect(0, 0, width, height);
                            for (var h = 0; h <= root.historyStep; h++) {
                                var action = root.actionHistory[h];
                                if (!action) continue;

                                if (action.type === "clear") {
                                    ctx.clearRect(0, 0, width, height);
                                } else if (action.type === "fill_bg") {
                                    ctx.globalCompositeOperation = "destination-over";
                                    ctx.fillStyle = action.color;
                                    ctx.fillRect(0, 0, width, height);
                                    ctx.globalCompositeOperation = "source-over";
                                } else if (action.type === "stroke") {
                                    if (action.tool === "brush") {
                                        renderBrushLine(ctx, action, false);
                                    } else {
                                        ctx.beginPath();
                                        applyToolStyle(ctx, action.tool, action.color, action.penSize);
                                        
                                        if (action.segments && action.segments.length > 0) {
                                            ctx.moveTo(action.segments[0].x1, action.segments[0].y1);
                                            for (var k = 0; k < action.segments.length; k++) {
                                                ctx.lineTo(action.segments[k].x2, action.segments[k].y2);
                                            }
                                            ctx.stroke();
                                        }
                                    }
                                }
                            }
                            _replayPending = false;
                            _queue = [];
                            return;
                        }

                        if (_clearPending) {
                            ctx.clearRect(0, 0, width, height);
                            _clearPending = false;
                        }
                        
                        for (var i = 0; i < _queue.length; i++) {
                            var q = _queue[i];
                            
                            if (q.type === "fill_bg") {
                                ctx.globalCompositeOperation = "destination-over";
                                ctx.fillStyle = q.color;
                                ctx.fillRect(0, 0, width, height);
                                ctx.globalCompositeOperation = "source-over";
                            } else if (q.tool === "brush") {
                                renderBrushLine(ctx, q, true);
                            } else {
                                ctx.beginPath();
                                applyToolStyle(ctx, q.tool, q.color, q.penSize);
                                ctx.moveTo(q.x1, q.y1);
                                ctx.lineTo(q.x2, q.y2);
                                ctx.stroke();
                            }
                        }
                        
                        _queue = [];
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.isActiveTab
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        
                        onWheel: (wheel) => {
                            let deltaY = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : (wheel.pixelDelta ? wheel.pixelDelta.y : 0);
                            let deltaX = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : (wheel.pixelDelta ? wheel.pixelDelta.x : 0);
                            
                            if (deltaY === 0 && deltaX === 0) {
                                wheel.accepted = false;
                                return;
                            }
                            
                            wheel.accepted = true;
                            
                            if (wheel.modifiers & Qt.ControlModifier) {
                                let delta = deltaY !== 0 ? deltaY : deltaX;
                                let zoomFactor = delta > 0 ? 1.15 : (1.0 / 1.15);
                                cameraRig.zoomBy(zoomFactor);
                            } else {
                                zoomContainer.x = Math.max(cameraRig.width - root.worldSize * zoomContainer.scale, Math.min(0, zoomContainer.x + deltaX));
                                zoomContainer.y = Math.max(cameraRig.height - root.worldSize * zoomContainer.scale, Math.min(0, zoomContainer.y + deltaY));
                            }
                        }

                        onPressed: (mouse) => {
                            root.showSizeConfig = false;
                            root.showColorPicker = false;
                            
                            let useColor = mouse.button === Qt.RightButton ? root.secondaryColor : root.primaryColor;
                            let freezeCol = useColor.toString();

                            if (root.currentTool === "fill") {
                                root.commitAction({ type: "fill_bg", color: freezeCol });
                                drawCanvas._queue.push({ type: "fill_bg", color: freezeCol });
                                
                                drawCanvas.markDirty(Qt.rect(0, 0, drawCanvas.width, drawCanvas.height));
                                drawCanvas.requestPaint();
                                return;
                            }

                            drawCanvas.lastX = mouse.x;
                            drawCanvas.lastY = mouse.y;
                            
                            root.currentAction = { 
                                type: "stroke", 
                                tool: root.currentTool, 
                                color: freezeCol, 
                                penSize: root.actualToolSize, 
                                segments: [] 
                            };
                            var initialSegment = { x1: mouse.x, y1: mouse.y, x2: mouse.x + 0.1, y2: mouse.y };
                            root.currentAction.segments.push(initialSegment);

                            drawCanvas._queue.push({
                                type: "stroke",
                                tool: root.currentTool,
                                color: freezeCol,
                                penSize: root.actualToolSize,
                                x1: initialSegment.x1, y1: initialSegment.y1, 
                                x2: initialSegment.x2, y2: initialSegment.y2
                            });
                            
                            var rad = s(20);
                            drawCanvas.markDirty(Qt.rect(mouse.x - rad, mouse.y - rad, rad*2, rad*2));
                            drawCanvas.requestPaint();
                        }

                        onPositionChanged: (mouse) => {
                            if (pressed && root.currentTool !== "fill") {
                                var segment = {
                                    x1: drawCanvas.lastX, y1: drawCanvas.lastY,
                                    x2: mouse.x, y2: mouse.y
                                };
                                
                                if (root.currentAction) {
                                    root.currentAction.segments.push(segment);
                                }

                                drawCanvas._queue.push({
                                    type: "stroke",
                                    tool: root.currentTool,
                                    color: root.currentAction.color,
                                    penSize: root.actualToolSize,
                                    x1: segment.x1, y1: segment.y1, 
                                    x2: segment.x2, y2: segment.y2
                                });
                                
                                var rad = s(20);
                                var minX = Math.min(drawCanvas.lastX, mouse.x) - rad;
                                var minY = Math.min(drawCanvas.lastY, mouse.y) - rad;
                                var w = Math.abs(mouse.x - drawCanvas.lastX) + rad*2;
                                var h = Math.abs(mouse.y - drawCanvas.lastY) + rad*2;
                                
                                drawCanvas.lastX = mouse.x;
                                drawCanvas.lastY = mouse.y;
                                
                                drawCanvas.markDirty(Qt.rect(minX, minY, w, h));
                                drawCanvas.requestPaint();
                            }
                        }

                        onReleased: (mouse) => {
                            if (root.currentAction) {
                                root.commitAction(root.currentAction);
                                root.currentAction = null;
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: topActionsLayout
            z: 10
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: s(20)
            anchors.rightMargin: s(20)
            spacing: s(12)

            Rectangle {
                width: zoomRow.width + s(24)
                height: s(44)
                radius: ThemeBackend.borderRadius
                color: root.panelBgColor
                border.width: 1
                border.color: root.panelBorderColor

                Row {
                    id: zoomRow
                    anchors.centerIn: parent
                    spacing: s(6)

                    IconButton {
                        width: root.s(32)
                        height: root.s(32)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "\uF068"
                        iconFontSize: root.s(14)
                        accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : "transparent"
                        textColor: root.baseTextColor
                        onClicked: cameraRig.zoomBy(1.0 / 1.25)
                    }

                    Item {
                        width: s(48); height: s(32)
                        Rectangle {
                            anchors.fill: parent; radius: ThemeBackend.borderRadius; z:-1
                            color: zoomResetMouse.containsMouse ? ThemeBackend.surface0 : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: Math.round(zoomContainer.scale * 100) + "%"; font.pixelSize: s(12); color: root.baseTextColor; font.bold: true
                        }
                        MouseArea {
                            id: zoomResetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                zoomContainer.scale = 1.0;
                                zoomContainer.x = (cameraRig.width - zoomContainer.width) / 2;
                                zoomContainer.y = (cameraRig.height - zoomContainer.height) / 2;
                            }
                        }
                    }

                    IconButton {
                        width: root.s(32)
                        height: root.s(32)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "\uF067"
                        iconFontSize: root.s(14)
                        accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : "transparent"
                        textColor: root.baseTextColor
                        onClicked: cameraRig.zoomBy(1.25)
                    }
                }
            }
            
            IconButton {
                width: root.s(44)
                height: root.s(44)
                cornerRadius: ThemeBackend.borderRadius
                buttonIcon: "\uF019"
                iconFontSize: root.s(14)
                accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : root.panelBgColor
                textColor: root.baseTextColor
                onClicked: {
                    var outDir = root.picturesDir !== "" ? root.picturesDir : "/tmp";
                    var outPath = outDir + "/drawing_" + Date.now() + ".png";
                    drawCanvas.save(outPath);
                    Quickshell.execDetached(["notify-send", "-a", "DrawAction", "Drawing saved", outPath]);
                }
            }

            IconButton {
                width: root.s(44)
                height: root.s(44)
                cornerRadius: ThemeBackend.borderRadius
                buttonIcon: "\uF0C5"
                iconFontSize: root.s(14)
                accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : root.panelBgColor
                textColor: root.baseTextColor
                onClicked: {
                    var tempPath = Caching.getRunDir("quickactions") + "/drawing_clip.png";
                    drawCanvas.save(tempPath);
                    Quickshell.execDetached(["sh", "-c", "wl-copy < " + tempPath]);
                }
            }
        }

        Rectangle {
            id: sizeConfigPopup
            z: 20
            width: s(260)
            height: s(64)
            radius: ThemeBackend.borderRadius
            color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.98)
            border.width: 1
            border.color: root.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: root.showSizeConfig
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: s(18)
                spacing: s(14)

                Text {
                    text: root.currentTool === "eraser" ? "\uF12D" : (root.currentTool === "brush" ? "\uF1FC" : "\uF040")
                    font.family: root.iconFont
                    color: root.baseTextColor
                    font.pixelSize: s(16)
                    opacity: 0.7
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: s(6)
                    radius: s(3)
                    color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.1)
                    
                    Rectangle {
                        width: parent.width * root.currentSizeRatio
                        height: parent.height
                        radius: parent.radius
                        color: ThemeBackend.mauve
                    }

                    Rectangle {
                        width: s(18); height: s(18)
                        radius: width/2
                        color: ThemeBackend.mauve
                        x: (parent.width * root.currentSizeRatio) - (width/2)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -s(16)
                        cursorShape: Qt.PointingHandCursor
                        
                        function updateSize(mouse) {
                            let val = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            if (root.currentTool === "eraser") root.eraserSizeRatio = val;
                            else if (root.currentTool === "brush") root.brushSizeRatio = val;
                            else root.penSizeRatio = val;
                        }

                        onPositionChanged: (mouse) => { if (pressed) updateSize(mouse) }
                        onPressed: (mouse) => updateSize(mouse)
                    }
                }

                Rectangle {
                    width: s(40)
                    height: s(28)
                    color: ThemeBackend.surface0
                    border.width: 1
                    border.color: ThemeBackend.surface1
                    radius: ThemeBackend.borderRadius
                    
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: s(2)
                        color: root.baseTextColor
                        text: Math.round(root.actualToolSize).toString()
                        font.pixelSize: s(13)
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        validator: IntValidator { bottom: 1; top: 999 }
                        
                        onEditingFinished: {
                            let px = parseFloat(text);
                            if (isNaN(px)) return;
                            if (root.currentTool === "eraser") {
                                root.eraserSizeRatio = Math.max(0, Math.min(1, (px - root.s(8)) / root.s(60)));
                            } else if (root.currentTool === "brush") {
                                root.brushSizeRatio = Math.max(0, Math.min(1, (px - root.s(4)) / root.s(40)));
                            } else {
                                root.penSizeRatio = Math.max(0, Math.min(1, (px - root.s(2)) / root.s(30)));
                            }
                        }
                    }
                }

                Item {
                    width: s(32)
                    height: s(32)
                    Rectangle {
                        anchors.centerIn: parent
                        
                        width: {
                            let toolMax = 0;
                            if (root.currentTool === "eraser") toolMax = s(8) + s(60);
                            else if (root.currentTool === "brush") toolMax = s(4) + s(40);
                            else toolMax = s(2) + s(30);

                            let visualLimit = s(32);
                            
                            if (toolMax <= visualLimit) {
                                return root.actualToolSize;
                            }
                            
                            let minVisual = s(4);
                            return minVisual + (root.currentSizeRatio * (visualLimit - minVisual));
                        }

                        height: width
                        radius: width / 2
                        color: root.currentTool === "eraser" ? "transparent" : root.currentColor
                        border.width: 1
                        border.color: Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.2)
                    }
                }
            }
        }

        Rectangle {
            id: colorPickerPopup
            z: 20
            width: s(320)
            height: s(400)
            radius: ThemeBackend.borderRadius
            color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.98)
            border.width: 1
            border.color: root.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: root.showColorPicker
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

            Column {
                anchors.centerIn: parent
                spacing: s(20)

                Row {
                    spacing: s(16)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        width: s(220); height: s(200)
                        radius: ThemeBackend.borderRadius
                        color: Qt.hsva(root.activeColorSlot === 0 ? root.primaryHSV.h : root.secondaryHSV.h, 1, 1, 1)
                        clip: true
                        border.width: 0

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            border.width: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            border.width: 0
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: "black" }
                            }
                        }

                        Rectangle {
                            width: s(14); height: s(14)
                            radius: width / 2
                            border.width: s(2); border.color: "white"
                            color: "transparent"
                            x: ((root.activeColorSlot === 0 ? root.primaryHSV.s : root.secondaryHSV.s) * parent.width) - (width/2)
                            y: ((1.0 - (root.activeColorSlot === 0 ? root.primaryHSV.v : root.secondaryHSV.v)) * parent.height) - (height/2)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.CrossCursor
                            function updateSV(mouse) {
                                let ns = Math.max(0, Math.min(1, mouse.x / width));
                                let nv = 1.0 - Math.max(0, Math.min(1, mouse.y / height));
                                if (root.activeColorSlot === 0) {
                                    root.primaryHSV = { h: root.primaryHSV.h, s: ns, v: nv };
                                } else {
                                    root.secondaryHSV = { h: root.secondaryHSV.h, s: ns, v: nv };
                                }
                            }
                            onPressed: (mouse) => updateSV(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateSV(mouse) }
                        }
                    }

                    Rectangle {
                        width: s(24); height: s(200)
                        radius: ThemeBackend.borderRadius
                        clip: true
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#ff0000" }
                            GradientStop { position: 0.166; color: "#ffff00" }
                            GradientStop { position: 0.333; color: "#00ff00" }
                            GradientStop { position: 0.5; color: "#00ffff" }
                            GradientStop { position: 0.666; color: "#0000ff" }
                            GradientStop { position: 0.833; color: "#ff00ff" }
                            GradientStop { position: 1.0; color: "#ff0000" }
                        }

                        Rectangle {
                            width: parent.width; height: s(8)
                            radius: s(4)
                            border.width: 1; border.color: "black"
                            color: "white"
                            y: ((root.activeColorSlot === 0 ? root.primaryHSV.h : root.secondaryHSV.h) * parent.height) - (height/2)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function updateH(mouse) {
                                let nh = Math.max(0, Math.min(1, mouse.y / height));
                                if (root.activeColorSlot === 0) {
                                    root.primaryHSV = { h: nh, s: root.primaryHSV.s, v: root.primaryHSV.v };
                                } else {
                                    root.secondaryHSV = { h: nh, s: root.secondaryHSV.s, v: root.secondaryHSV.v };
                                }
                            }
                            onPressed: (mouse) => updateH(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateH(mouse) }
                        }
                    }
                }
                
                RowLayout {
                    width: parent.width
                    spacing: s(10)

                    Text {
                        text: root.colorPalettes[root.activePaletteIndex] ? root.colorPalettes[root.activePaletteIndex].name : "Palette"
                        color: root.baseTextColor
                        font.pixelSize: s(14)
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    
                    IconButton {
                        width: root.s(24)
                        height: root.s(24)
                        buttonIcon: "\uF067"
                        iconFontSize: root.s(12)
                        accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : "transparent"
                        textColor: root.baseTextColor
                        onClicked: root.addColorToPalette(root.currentColor.toString())
                    }
                }

                Grid {
                    columns: 8
                    spacing: s(12)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: root.colorPalettes[root.activePaletteIndex] ? root.colorPalettes[root.activePaletteIndex].colors : []
                        
                        Rectangle {
                            width: s(20)
                            height: s(20)
                            radius: width / 2
                            color: modelData
                            
                            border.width: root.currentColor.toString() === color.toString() ? s(2) : 0
                            border.color: root.baseTextColor
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let c = parent.color;
                                    let hsv = { h: c.hsvHue, s: c.hsvSaturation, v: c.hsvValue };
                                    if (root.activeColorSlot === 0) root.primaryHSV = hsv;
                                    else root.secondaryHSV = hsv;
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: s(10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    Text { 
                        text: "Hex"
                        color: Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.6)
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: s(13)
                        font.bold: true
                    }
                    
                    Rectangle {
                        width: s(120)
                        height: s(28)
                        color: ThemeBackend.surface0
                        border.width: 1
                        border.color: ThemeBackend.surface1
                        radius: ThemeBackend.borderRadius
                        
                        TextInput {
                            id: hexInput
                            anchors.fill: parent
                            anchors.margins: s(4)
                            color: root.baseTextColor
                            text: root.currentColor.toString()
                            font.pixelSize: s(14)
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            onEditingFinished: {
                                let c = Qt.color(text);
                                let hsv = { h: c.hsvHue, s: c.hsvSaturation, v: c.hsvValue };
                                if (root.activeColorSlot === 0) root.primaryHSV = hsv;
                                else root.secondaryHSV = hsv;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: toolbar
            z: 10
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: s(20)
            
            width: toolRow.width + s(32)
            height: s(48)
            radius: ThemeBackend.borderRadius
            
            color: root.panelBgColor
            border.width: 1
            border.color: root.panelBorderColor

            Row {
                id: toolRow
                anchors.centerIn: parent
                spacing: s(16)

                IconButton {
                    width: root.s(32)
                    height: root.s(32)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: "\uF0E2"
                    iconFontSize: root.s(14)
                    enabled: root.historyStep >= 0
                    accentColor: isHoveredOrHighlighted && root.historyStep >= 0 ? ThemeBackend.surface0 : "transparent"
                    textColor: root.baseTextColor
                    onClicked: root.undo()
                }

                IconButton {
                    width: root.s(32)
                    height: root.s(32)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: "\uF01E"
                    iconFontSize: root.s(14)
                    enabled: root.historyStep < root.actionHistory.length - 1
                    accentColor: isHoveredOrHighlighted && root.historyStep < root.actionHistory.length - 1 ? ThemeBackend.surface0 : "transparent"
                    textColor: root.baseTextColor
                    onClicked: root.redo()
                }

                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                Item {
                    width: toolsListLayout.width
                    height: s(32)

                    Rectangle {
                        id: toolsActiveHighlight
                        y: 0
                        height: s(32)
                        radius: ThemeBackend.borderRadius
                        color: ThemeBackend.surface1
                        z: 0

                        property int prevIdx: 0
                        property int curIdx: root.currentToolIndex

                        onCurIdxChanged: {
                            if (curIdx > prevIdx) { rightAnim.duration = 200; leftAnim.duration = 350; }
                            else if (curIdx < prevIdx) { leftAnim.duration = 200; rightAnim.duration = 350; }
                            prevIdx = curIdx;
                        }

                        property real stepSize: s(32) + s(8)
                        property real targetLeft: toolsListLayout.x + (curIdx * stepSize)
                        property real targetRight: targetLeft + s(32)

                        property real actualLeft: targetLeft
                        property real actualRight: targetRight

                        Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }

                        x: actualLeft
                        width: actualRight - actualLeft
                    }

                    Row {
                        id: toolsListLayout
                        anchors.left: parent.left
                        anchors.top: parent.top
                        spacing: s(8)
                        z: 1

                        Repeater {
                            model: [
                                { id: "pen", icon: "\uF040" },
                                { id: "brush", icon: "\uF1FC" },
                                { id: "fill", icon: "\uF576" },
                                { id: "eraser", icon: "\uF12D" }
                            ]

                            IconButton {
                                width: root.s(32)
                                height: root.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: modelData.icon
                                iconFontSize: root.s(14)
                                accentColor: isHoveredOrHighlighted && root.currentTool !== modelData.id ? ThemeBackend.surface0 : "transparent"
                                textColor: root.currentTool === modelData.id ? ThemeBackend.mauve : root.baseTextColor
                                action_highlight: root.currentTool === modelData.id
                                onClicked: {
                                    if (modelData.id === "pen" || modelData.id === "brush" || modelData.id === "eraser") {
                                        if (root.currentTool === modelData.id) {
                                            root.showSizeConfig = !root.showSizeConfig;
                                        } else {
                                            root.currentTool = modelData.id;
                                            root.showSizeConfig = true;
                                        }
                                    } else {
                                        root.currentTool = modelData.id;
                                        root.showSizeConfig = false;
                                    }
                                    root.showColorPicker = false;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                Item {
                    width: s(92)
                    height: s(32)

                    Row {
                        anchors.centerIn: parent
                        spacing: s(6)

                        Rectangle {
                            width: s(26)
                            height: s(26)
                            radius: width / 2
                            color: root.primaryColor
                            border.width: root.activeColorSlot === 0 ? s(2) : 1
                            border.color: root.activeColorSlot === 0 ? root.baseTextColor : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.4)
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeColorSlot = 0;
                                    root.showColorPicker = !root.showColorPicker;
                                    root.showSizeConfig = false;
                                    if (root.currentTool === "eraser") {
                                        root.currentTool = "pen";
                                    }
                                }
                            }
                        }

                        IconButton {
                            width: root.s(26)
                            height: root.s(26)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: "\uF0EC"
                            iconFontSize: root.s(12)
                            accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : "transparent"
                            textColor: root.baseTextColor
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                let temp = root.primaryHSV;
                                root.primaryHSV = root.secondaryHSV;
                                root.secondaryHSV = temp;
                            }
                        }

                        Rectangle {
                            width: s(26)
                            height: s(26)
                            radius: width / 2
                            color: root.secondaryColor
                            border.width: root.activeColorSlot === 1 ? s(2) : 1
                            border.color: root.activeColorSlot === 1 ? root.baseTextColor : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.4)
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeColorSlot = 1;
                                    root.showColorPicker = !root.showColorPicker;
                                    root.showSizeConfig = false;
                                    if (root.currentTool === "eraser") {
                                        root.currentTool = "pen";
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                IconButton {
                    width: root.s(32)
                    height: root.s(32)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: "\uF1F8"
                    iconFontSize: root.s(14)
                    accentColor: isHoveredOrHighlighted ? ThemeBackend.surface0 : "transparent"
                    textColor: ThemeBackend.red
                    onClicked: {
                        root.commitAction({ type: "clear" });
                        drawCanvas._clearPending = true;
                        drawCanvas.requestPaint();
                        root.showColorPicker = false;
                        root.showSizeConfig = false;

                        zoomContainer.scale = 1.0;
                        zoomContainer.x = (cameraRig.width - zoomContainer.width) / 2;
                        zoomContainer.y = (cameraRig.height - zoomContainer.height) / 2;
                    }
                }
            }
        }
    }
}
