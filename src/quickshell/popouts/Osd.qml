import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../reusables"
import "../"

PanelWindow {
    id: osdWindow

    screen: OsdController.screen

    WlrLayershell.namespace: "osd"
    WlrLayershell.layer: WlrLayer.Top
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region {
        item: (osdWindow.isVisible || osdContainer.animProgress > 0.001) ? osdContainer : null
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function s(val) { return (typeof Scaler !== "undefined") ? Scaler.s(val) : val; }

    readonly property color briColor: Qt.lighter(ThemeBackend.mauve, 1.1)
    readonly property color volColor: Qt.lighter(ThemeBackend.sapphire, 1.5)

    property bool isVisible: OsdController.isVisible
    property string kind: OsdController.kind
    property int briVal: OsdController.briVal

    readonly property int volVal: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    readonly property bool isMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false
    readonly property int currentVal: kind === "volume" ? volVal : briVal

    property int configRevision: 0

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            OsdController.hide();
            osdWindow.configRevision++;
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

    onBarStyleChanged: {
        OsdController.hide();
    }

    property string barPosition: {
        let dummy = configRevision;
        if (typeof Config === "undefined" || !Config.rawSettings || !Config.rawSettings.bar) return "top";
        return Config.rawSettings.bar.position || "top";
    }

    property real barOpacity: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.opacity !== undefined) ? (Config.rawSettings.bar.opacity / 100.0) : 1.0;
    }

    property bool isFullscreen: OsdController.isFullscreen
    property bool isSideBar: barPosition === "left" || barPosition === "right"
    property bool isRightBar: barPosition === "right"
    property bool isBottomBar: barPosition === "bottom"
    property bool isFill: barStyle === "fill"
    property bool isSolid: (barStyle === "solid" || barStyle === "fill") && !isFullscreen && Math.round(barOpacity * 100) >= 100

    property real barHeight: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.height) ? s(Config.rawSettings.bar.height) : s(40);
    }

    property real cornerRadius: ThemeBackend.borderRadius || s(12)
    property real menuMargin: isSolid ? 0 : s(20)

    property real osdWidth: (isSolid && isSideBar) ? s(58) : s(296)
    property real osdHeight: (isSolid && isSideBar) ? s(296) : s(58)
    property real collapsedWidth: s(58)

    visible: isVisible || osdContainer.animProgress > 0.001

    property real clampedX: {
        if (isSolid) {
            if (isSideBar) {
                if (isRightBar) {
                    return osdWindow.width - barHeight - osdWidth;
                } else {
                    return barHeight;
                }
            } else {
                return (osdWindow.width - osdWidth) / 2;
            }
        } else {
            return (osdWindow.width - osdWidth) / 2;
        }
    }

    property real clampedY: {
        if (isSolid) {
            if (isSideBar) {
                return (osdWindow.height - osdHeight) / 2;
            } else {
                if (isBottomBar) {
                    return osdWindow.height - barHeight - osdHeight;
                } else {
                    return barHeight;
                }
            }
        } else {
            return (osdWindow.height * 0.9) - (osdHeight / 2);
        }
    }

    Timer {
        id: cmdThrottle
        interval: 50
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                if (targetPct > 0 && osdWindow.isMuted) {
                    if (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) {
                        Audio.toggleMute(Audio.defaultSink);
                    }
                }
                if (Audio.defaultSink) {
                    Audio.setVolume(Audio.defaultSink, targetPct);
                }
                targetPct = -1;
            }
        }
    }

    Timer {
        id: briCmdThrottle
        interval: 400
        property int targetPct: -1
        onTriggered: {
            if (targetPct >= 0) {
                Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", targetPct.toString()]);
                targetPct = -1;
            }
        }
    }

    Item {
        id: osdContainer

        property real animProgress: osdWindow.isVisible ? 1.0 : 0.0
        Behavior on animProgress {
            NumberAnimation {
                duration: osdWindow.isVisible ? 450 : 300
                easing.type: osdWindow.isVisible ? Easing.OutQuint : Easing.InCubic
            }
        }

        property real dynamicCornerRadius: osdWindow.isSolid ? Math.max(0, Math.min(osdWindow.cornerRadius, (osdWindow.isSideBar ? width : height))) : 0

        x: {
            if (osdWindow.isSolid) {
                if (osdWindow.isSideBar && osdWindow.isRightBar) {
                    return (osdWindow.clampedX + osdWindow.osdWidth) - width;
                }
                return osdWindow.clampedX;
            }
            return (osdWindow.width - width) / 2;
        }
        y: {
            if (osdWindow.isSolid && !osdWindow.isSideBar && osdWindow.isBottomBar) {
                return (osdWindow.clampedY + osdWindow.osdHeight) - height;
            }
            return osdWindow.clampedY;
        }
        width: {
            if (osdWindow.isSolid) {
                if (osdWindow.isSideBar) {
                    return osdWindow.osdWidth * animProgress;
                }
                return osdWindow.osdWidth;
            }
            return osdWindow.collapsedWidth + (osdWindow.osdWidth - osdWindow.collapsedWidth) * animProgress;
        }
        height: {
            if (osdWindow.isSolid && !osdWindow.isSideBar) {
                return osdWindow.osdHeight * animProgress;
            }
            return osdWindow.osdHeight;
        }
        opacity: osdWindow.isSolid ? ((osdWindow.isVisible || animProgress > 0.001) ? 1.0 : 0.0) : Math.max(0.0, Math.min(1.0, animProgress * 1.5))

        transformOrigin: {
            if (osdWindow.isSolid) {
                if (osdWindow.isSideBar) {
                    return osdWindow.isRightBar ? Item.Right : Item.Left;
                }
                return osdWindow.isBottomBar ? Item.Bottom : Item.Top;
            }
            return Item.Center;
        }

        Shape {
            visible: osdWindow.isSolid && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
            x: -osdContainer.dynamicCornerRadius
            y: 0
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: osdContainer.dynamicCornerRadius; y: 0 }
                PathLine { x: osdContainer.dynamicCornerRadius; y: osdContainer.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
            x: parent.width
            y: 0
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: osdContainer.dynamicCornerRadius
                startY: 0
                PathLine { x: 0; y: 0 }
                PathLine { x: 0; y: osdContainer.dynamicCornerRadius }
                PathArc {
                    x: osdContainer.dynamicCornerRadius
                    y: 0
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
            x: -osdContainer.dynamicCornerRadius
            y: parent.height - osdContainer.dynamicCornerRadius
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: osdContainer.dynamicCornerRadius
                PathLine { x: osdContainer.dynamicCornerRadius; y: osdContainer.dynamicCornerRadius }
                PathLine { x: osdContainer.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: osdContainer.dynamicCornerRadius
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
            x: parent.width
            y: parent.height - osdContainer.dynamicCornerRadius
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: osdContainer.dynamicCornerRadius
                startY: osdContainer.dynamicCornerRadius
                PathLine { x: 0; y: osdContainer.dynamicCornerRadius }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: osdContainer.dynamicCornerRadius
                    y: osdContainer.dynamicCornerRadius
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
            x: 0
            y: -osdContainer.dynamicCornerRadius
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: 0; y: osdContainer.dynamicCornerRadius }
                PathLine { x: osdContainer.dynamicCornerRadius; y: osdContainer.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
            x: 0
            y: parent.height
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: osdContainer.dynamicCornerRadius
                PathLine { x: 0; y: 0 }
                PathLine { x: osdContainer.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: osdContainer.dynamicCornerRadius
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
            x: parent.width - osdContainer.dynamicCornerRadius
            y: -osdContainer.dynamicCornerRadius
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: osdContainer.dynamicCornerRadius
                startY: 0
                PathLine { x: osdContainer.dynamicCornerRadius; y: osdContainer.dynamicCornerRadius }
                PathLine { x: 0; y: osdContainer.dynamicCornerRadius }
                PathArc {
                    x: osdContainer.dynamicCornerRadius
                    y: 0
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: osdWindow.isSolid && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
            x: parent.width - osdContainer.dynamicCornerRadius
            y: parent.height
            width: osdContainer.dynamicCornerRadius
            height: osdContainer.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: osdContainer.dynamicCornerRadius
                startY: osdContainer.dynamicCornerRadius
                PathLine { x: osdContainer.dynamicCornerRadius; y: 0 }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: osdContainer.dynamicCornerRadius
                    y: osdContainer.dynamicCornerRadius
                    radiusX: osdContainer.dynamicCornerRadius
                    radiusY: osdContainer.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Rectangle {
            id: osdBox
            anchors.fill: parent
            color: ThemeBackend.base
            radius: osdWindow.cornerRadius
            border.width: osdWindow.isSolid ? 0 : 1
            border.color: osdWindow.isSolid ? "transparent" : ThemeBackend.surface0
            clip: true

            Rectangle {
                visible: osdWindow.isSolid && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && !osdWindow.isSideBar && !osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && !osdWindow.isSideBar && osdWindow.isBottomBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && osdWindow.isSideBar && !osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: 0
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: osdWindow.isSolid && osdWindow.isSideBar && osdWindow.isRightBar && osdContainer.dynamicCornerRadius > 0.5
                x: parent.width - osdContainer.dynamicCornerRadius
                y: parent.height - osdContainer.dynamicCornerRadius
                width: osdContainer.dynamicCornerRadius
                height: osdContainer.dynamicCornerRadius
                color: ThemeBackend.base
            }

            HoverHandler {
                id: osdHoverHandler
                onHoveredChanged: {
                    OsdController.isHovered = hovered;
                    if (hovered) {
                        OsdController.cancelHide();
                    } else {
                        OsdController.requestHide();
                    }
                }
            }

            ColumnLayout {
                visible: osdWindow.isSideBar && osdWindow.isSolid
                anchors.fill: parent
                anchors.topMargin: osdWindow.s(14)
                anchors.bottomMargin: osdWindow.s(14)
                anchors.leftMargin: osdWindow.s(10)
                anchors.rightMargin: osdWindow.s(10)
                spacing: osdWindow.s(10)

                IconButton {
                    Layout.alignment: Qt.AlignHCenter
                    size: osdWindow.s(26)
                    iconOffsetX: osdWindow.kind === "volume" ? -1 : -3
                    cornerRadius: osdWindow.s(8)
                    buttonIcon: {
                        if (osdWindow.kind === "volume") {
                            return osdWindow.isMuted || osdWindow.volVal === 0 ? "󰖁" : (osdWindow.volVal > 50 ? "󰕾" : "󰖀");
                        } else {
                            return osdWindow.briVal > 66 ? "󰃠" : (osdWindow.briVal > 33 ? "󰃟" : "󰃞");
                        }
                    }
                    iconFontSize: osdWindow.s(15)
                    accentColor: ThemeBackend.surface1
                    textColor: {
                        if (isHoveredOrHighlighted) return ThemeBackend.text;
                        if (osdWindow.kind === "volume") {
                            return osdWindow.isMuted ? ThemeBackend.overlay0 : osdWindow.volColor;
                        } else {
                            return osdWindow.briColor;
                        }
                    }
                    onClicked: {
                        OsdController.restartTimer();
                        if (osdWindow.kind === "volume") {
                            if (Audio.defaultSink) {
                                Audio.toggleMute(Audio.defaultSink);
                            }
                        } else {
                            briCmdThrottle.stop();
                            briCmdThrottle.targetPct = -1;
                            let target = osdWindow.briVal > 0 ? 0 : 100;
                            OsdController.briVal = target;
                            Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", target.toString()]);
                        }
                    }
                }

                Draggable {
                    id: verticalSlider
                    vertical: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdWindow.s(16)
                    Layout.alignment: Qt.AlignHCenter
                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: ThemeBackend.surface1

                    readonly property color activeColor: osdWindow.kind === "volume" ? (osdWindow.isMuted ? ThemeBackend.surface2 : osdWindow.volColor) : osdWindow.briColor

                    accentColor: activeColor
                    gradColor1: activeColor
                    gradColor2: Qt.lighter(activeColor, 1.05)
                    gradColor3: Qt.lighter(activeColor, 1.10)
                    cornerRadius: osdWindow.s(5)
                    handleSize: osdWindow.s(16)

                    handleColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.overlay0 : Qt.lighter(activeColor, 1.15)
                    handleHoverColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.subtext0 : Qt.lighter(activeColor, 1.5)
                    handleDragColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.text : Qt.lighter(activeColor, 1.45)
                    handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                    onDragStarted: OsdController.cancelHide()
                    onDragFinished: {
                        OsdController.restartTimer();
                        if (osdWindow.kind !== "volume" && briCmdThrottle.targetPct >= 0) {
                            briCmdThrottle.stop();
                            Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", briCmdThrottle.targetPct.toString()]);
                            briCmdThrottle.targetPct = -1;
                        }
                    }
                    onMoved: val => {
                        OsdController.restartTimer();
                        let pct = Math.max(0, Math.min(100, Math.round(val)));
                        if (osdWindow.kind !== "volume") {
                            OsdController.briVal = pct;
                        }
                        if (osdWindow.kind === "volume") {
                            cmdThrottle.targetPct = pct;
                            if (!cmdThrottle.running) cmdThrottle.start();
                        } else {
                            briCmdThrottle.targetPct = pct;
                            if (!verticalSlider.isDragging) briCmdThrottle.restart();
                        }
                    }
                }
            }

            Item {
                visible: !(osdWindow.isSideBar && osdWindow.isSolid)
                anchors.fill: parent

                Item {
                    width: osdWindow.s(58)
                    height: parent.height
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    IconButton {
                        anchors.centerIn: parent
                        size: osdWindow.s(30)
                        cornerRadius: osdWindow.s(8)
                        iconOffsetX: osdWindow.kind === "volume" ? -1 : -3
                        buttonIcon: {
                            if (osdWindow.kind === "volume") {
                                return osdWindow.isMuted || osdWindow.volVal === 0 ? "󰖁" : (osdWindow.volVal > 50 ? "󰕾" : "󰖀");
                            } else {
                                return osdWindow.briVal > 66 ? "󰃠" : (osdWindow.briVal > 33 ? "󰃟" : "󰃞");
                            }
                        }
                        iconFontSize: osdWindow.s(15)
                        accentColor: ThemeBackend.surface1
                        textColor: {
                            if (isHoveredOrHighlighted) return ThemeBackend.text;
                            if (osdWindow.kind === "volume") {
                                return osdWindow.isMuted ? ThemeBackend.overlay0 : osdWindow.volColor;
                            } else {
                                return osdWindow.briColor;
                            }
                        }
                        onClicked: {
                            OsdController.restartTimer();
                            if (osdWindow.kind === "volume") {
                                if (Audio.defaultSink) {
                                    Audio.toggleMute(Audio.defaultSink);
                                }
                            } else {
                                briCmdThrottle.stop();
                                briCmdThrottle.targetPct = -1;
                                let target = osdWindow.briVal > 0 ? 0 : 100;
                                OsdController.briVal = target;
                                Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", target.toString()]);
                            }
                        }
                    }
                }

                Draggable {
                    id: horizontalSlider
                    width: Math.max(0, osdContainer.width - osdWindow.s(80))
                    height: osdWindow.s(18)
                    anchors.left: parent.left
                    anchors.leftMargin: osdWindow.s(58)
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0.0, Math.min(1.0, (osdContainer.animProgress - 0.2) / 0.8))
                    visible: opacity > 0.01

                    from: 0.0
                    to: 100.0
                    value: osdWindow.currentVal
                    backgroundColor: ThemeBackend.surface1

                    readonly property color activeColor: osdWindow.kind === "volume" ? (osdWindow.isMuted ? ThemeBackend.surface2 : osdWindow.volColor) : osdWindow.briColor

                    accentColor: activeColor
                    gradColor1: activeColor
                    gradColor2: Qt.lighter(activeColor, 1.05)
                    gradColor3: Qt.lighter(activeColor, 1.10)
                    cornerRadius: osdWindow.s(5)
                    handleSize: osdWindow.s(16)

                    handleColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.overlay0 : Qt.lighter(activeColor, 1.15)
                    handleHoverColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.subtext0 : Qt.lighter(activeColor, 1.5)
                    handleDragColor: (osdWindow.kind === "volume" && osdWindow.isMuted) ? ThemeBackend.text : Qt.lighter(activeColor, 1.45)
                    handleBorderColor: Qt.rgba(0, 0, 0, 0.2)

                    onDragStarted: OsdController.cancelHide()
                    onDragFinished: {
                        OsdController.restartTimer();
                        if (osdWindow.kind !== "volume" && briCmdThrottle.targetPct >= 0) {
                            briCmdThrottle.stop();
                            Quickshell.execDetached(["bash", Caching.qsDir + "/../scripts/brightness.sh", "set", briCmdThrottle.targetPct.toString()]);
                            briCmdThrottle.targetPct = -1;
                        }
                    }
                    onMoved: val => {
                        OsdController.restartTimer();
                        let pct = Math.max(0, Math.min(100, Math.round(val)));
                        if (osdWindow.kind !== "volume") {
                            OsdController.briVal = pct;
                        }
                        if (osdWindow.kind === "volume") {
                            cmdThrottle.targetPct = pct;
                            if (!cmdThrottle.running) cmdThrottle.start();
                        } else {
                            briCmdThrottle.targetPct = pct;
                            if (!horizontalSlider.isDragging) briCmdThrottle.restart();
                        }
                    }
                }
            }
        }
    }
}
