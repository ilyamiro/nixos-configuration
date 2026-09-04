import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: root
    color: "transparent"

    property string wId: Quickshell.env("QS_WIDGET_ID") || "preview"
    property string wType: "time"
    property string wVariant: ""
    property string wImagePath: ""
    property real wX: 0
    property real wY: 0
    property real wWidth: 250
    property real wHeight: 120
    property real wOpacity: 1.0
    property real wRotation: 0

    property real animX: wX
    property real animY: wY
    Behavior on animX { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
    Behavior on animY { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    property real effectiveWidth: wWidth
    property real effectiveHeight: wHeight

    onWWidthChanged: updateEffectiveSize()
    onWHeightChanged: updateEffectiveSize()
    onWVariantChanged: updateEffectiveSize()
    onWTypeChanged: updateEffectiveSize()

    WlrLayershell.namespace: "qs-widget-" + wType + "-" + wId
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    focusable: false

    anchors.top: true
    anchors.left: true
    margins.left: animX
    margins.top: animY

    implicitWidth: (Math.round(wRotation || 0) % 180 === 0) ? effectiveWidth : effectiveHeight
    implicitHeight: (Math.round(wRotation || 0) % 180 === 0) ? effectiveHeight : effectiveWidth

    Component.onDestruction: visible = false

    function updateEffectiveSize() {
        if (!faceLoader.item) {
            root.effectiveWidth = root.wWidth;
            root.effectiveHeight = root.wHeight;
            return;
        }
        let item = faceLoader.item;
        let c = {
            minW: item.minWidth !== undefined ? item.minWidth : 10,
            minH: item.minHeight !== undefined ? item.minHeight : 10,
            maxW: item.maxWidth !== undefined ? item.maxWidth : 9999,
            maxH: item.maxHeight !== undefined ? item.maxHeight : 9999,
            minA: item.minAspect !== undefined ? item.minAspect : 0,
            maxA: item.maxAspect !== undefined ? item.maxAspect : 9999
        };
        let w = Math.max(c.minW, Math.min(c.maxW, root.wWidth));
        let h = Math.max(c.minH, Math.min(c.maxH, root.wHeight));

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

        root.effectiveWidth = w;
        root.effectiveHeight = h;
    }

    Loader {
        id: faceLoader
        property string wImagePath: root.wImagePath
        property string imagePath: root.wImagePath
        property string path: root.wImagePath
        source: WidgetRegistry.faceFile(root.wType, root.wVariant)
        width: root.effectiveWidth
        height: root.effectiveHeight
        anchors.centerIn: parent
        rotation: root.wRotation || 0
        opacity: root.wOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        onLoaded: {
            if (item) {
                if (item.imagePath !== undefined) {
                    item.imagePath = Qt.binding(() => root.wImagePath);
                }
                if (item.wImagePath !== undefined) {
                    item.wImagePath = Qt.binding(() => root.wImagePath);
                }
                if (item.path !== undefined) {
                    item.path = Qt.binding(() => root.wImagePath);
                }
                if (item.source !== undefined && typeof item.source === "string") {
                    item.source = Qt.binding(() => root.wImagePath);
                }
            }
            root.updateEffectiveSize();
        }
    }
}
