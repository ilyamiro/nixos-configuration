import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent

    property real minWidth: 50
    property real minHeight: 50
    property real maxWidth: 99999
    property real maxHeight: 99999
    property real minAspect: 0
    property real maxAspect: 99999

    property bool isVisVisible: visible

    onIsVisVisibleChanged: {
        if (isVisVisible) Cava.registerConsumer();
        else Cava.unregisterConsumer();
    }

    Component.onCompleted: {
        if (isVisVisible) Cava.registerConsumer();
    }

    Component.onDestruction: {
        if (isVisVisible) Cava.unregisterConsumer();
    }

    property real barSpacing: Scaler.s(4)
    property real minBarWidth: Scaler.s(6)
    property int activeBars: Math.max(4, Math.min(128, Math.floor((width + barSpacing) / (minBarWidth + barSpacing))))
    property real actualBarWidth: (width - (activeBars - 1) * barSpacing) / activeBars

    property var rawBarLevels: Cava.barLevels
    property var processedBars: {
        let source = rawBarLevels;
        let count = activeBars;
        let out = [];

        if (!source || source.length === 0) {
            for (let i = 0; i < count; i++) out.push(0.0);
            return out;
        }

        let srcLen = source.length;
        let half = (count - 1) / 2;

        for (let i = 0; i < count; i++) {
            let distFromCenter = Math.abs(i - half);
            let norm = half > 0 ? (distFromCenter / half) : 0;
            let pos = Math.pow(norm, 1.25) * (srcLen - 1);
            let idx0 = Math.floor(pos);
            let idx1 = Math.min(srcLen - 1, idx0 + 1);
            let frac = pos - idx0;

            let v0 = source[idx0] || 0.0;
            let v1 = source[idx1] || 0.0;
            let rawVal = v0 + (v1 - v0) * frac;

            let val = rawVal < 0.03 ? 0.0 : Math.pow((rawVal - 0.03) / 0.97, 1.15);
            val = Math.max(0.0, Math.min(1.0, val));

            let edgeNorm = Math.sin((i / Math.max(1, count - 1)) * Math.PI);
            let edgeFactor = Math.min(1.0, edgeNorm * 2.0);
            edgeFactor = edgeFactor * edgeFactor * (3.0 - 2.0 * edgeFactor);
            val *= edgeFactor;

            out.push(val);
        }

        return out;
    }

    property var barLevels: processedBars

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height
        spacing: root.barSpacing

        Repeater {
            model: root.activeBars
            delegate: Rectangle {
                width: root.actualBarWidth
                height: Math.max(Scaler.s(3), level * parent.height * 0.96)
                topLeftRadius: width * 0.35
                topRightRadius: width * 0.35
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: ThemeBackend.mauve
                opacity: (0.3 + (level * 0.7)) * edgeFactor
                anchors.bottom: parent.bottom

                property real level: (root.barLevels && index < root.barLevels.length) ? root.barLevels[index] : 0.0
                property real edgeNorm: Math.sin((index / Math.max(1, root.activeBars - 1)) * Math.PI)
                property real rawEdgeFactor: Math.min(1.0, edgeNorm * 2.0)
                property real edgeFactor: rawEdgeFactor * rawEdgeFactor * (3.0 - 2.0 * rawEdgeFactor)

                Behavior on height {
                    NumberAnimation {
                        duration: 75
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 75
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
