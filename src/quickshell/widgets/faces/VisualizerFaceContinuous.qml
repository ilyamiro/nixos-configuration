import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
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

    property int sampleCount: 64
    property var rawBarLevels: Cava.barLevels
    property var processedBars: {
        let source = rawBarLevels;
        let count = sampleCount;
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
            out.push(val);
        }

        let smoothed = [];
        for (let i = 0; i < count; i++) {
            let prev = i > 0 ? out[i - 1] : out[i];
            let curr = out[i];
            let next = i < count - 1 ? out[i + 1] : out[i];
            smoothed.push(prev * 0.25 + curr * 0.5 + next * 0.25);
        }

        return smoothed;
    }

    property var smoothLevels: []
    property real totalEnergy: 0.0

    Timer {
        interval: 16
        running: root.isVisVisible
        repeat: true
        onTriggered: {
            let targets = root.processedBars;
            let current = root.smoothLevels;
            let updated = [];
            let sum = 0.0;

            for (let i = 0; i < root.sampleCount; i++) {
                let target = (targets && i < targets.length) ? targets[i] : 0.0;
                let cur = (current && i < current.length) ? current[i] : 0.0;
                let factor = target > cur ? 0.25 : 0.12;
                let next = cur + (target - cur) * factor;
                updated.push(next);
                sum += next;
            }

            root.smoothLevels = updated;
            root.totalEnergy = sum / root.sampleCount;
            waveCanvas.requestPaint();
        }
    }

    Rectangle {
        id: bgMask
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bgMask
        }

        Canvas {
            id: waveCanvas
            anchors.fill: parent

            onPaint: {
                let ctx = getContext("2d");
                let w = width;
                let h = height;

                ctx.reset();
                ctx.clearRect(0, 0, w, h);

                let levels = root.smoothLevels;
                if (!levels || levels.length === 0) return;

                let count = levels.length;
                let pts = [];
                for (let i = 0; i < count; i++) {
                    let px = (i / (count - 1)) * w;
                    let py = h - (levels[i] * h * 0.92) - Scaler.s(2);
                    pts.push({ x: px, y: py });
                }

                ctx.beginPath();
                ctx.moveTo(0, h);
                ctx.lineTo(pts[0].x, pts[0].y);

                for (let i = 0; i < pts.length - 1; i++) {
                    let p0 = pts[i];
                    let p1 = pts[i + 1];
                    let mx = (p0.x + p1.x) / 2;
                    let my = (p0.y + p1.y) / 2;
                    ctx.quadraticCurveTo(p0.x, p0.y, mx, my);
                }

                let last = pts[pts.length - 1];
                ctx.lineTo(last.x, last.y);
                ctx.lineTo(w, h);
                ctx.closePath();

                let c = ThemeBackend.mauve;
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 1.0);
                ctx.fill();
            }
        }
    }
}
