import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Rectangle {
    id: sideVisRoot

    property var barWindow
    property var paths
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property real targetY: 0
    property bool showLayout: !barWindow || barWindow.isStartupReady
    property int barCount: 12
    property bool isVisVisible: moduleActive && showLayout
    property bool isSubscribed: false
    readonly property bool shouldSubscribe: isVisVisible

    onShouldSubscribeChanged: updateSubscription()

    function updateSubscription() {
        if (shouldSubscribe && !isSubscribed) {
            isSubscribed = true;
            Cava.registerConsumer();
        } else if (!shouldSubscribe && isSubscribed) {
            isSubscribed = false;
            Cava.unregisterConsumer();
        }
    }

    Connections {
        target: barWindow ? barWindow : null
        function onIsStartupReadyChanged() {
            if (barWindow && barWindow.isStartupReady) {
                sideVisRoot.showLayout = true;
            }
        }
    }

    Component.onCompleted: {
        if (!barWindow || barWindow.isStartupReady) {
            sideVisRoot.showLayout = true;
        }
        updateSubscription();
    }

    Component.onDestruction: {
        if (isSubscribed) {
            isSubscribed = false;
            Cava.unregisterConsumer();
        }
    }

    y: targetY
    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    property real targetWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetHeight: (moduleActive && innerCol.implicitHeight > 0) ? (innerCol.implicitHeight + (barWindow ? barWindow.s(isCompact ? 18 : 22) : (isCompact ? 18 : 22))) : 0

    width: targetWidth
    height: targetHeight

    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

    radius: ThemeBackend.borderRadius
    border.width: 0
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    clip: true

    opacity: (moduleActive && showLayout) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: sideVisRoot.moduleActive && barWindow && !sideVisRoot.showLayout
        interval: 100
        onTriggered: {
            if (barWindow && barWindow.isStartupReady) {
                sideVisRoot.showLayout = true;
            }
        }
    }

    property var barLevels: {
        let source = Cava.barLevels;
        let count = barCount;
        let out = [];
        if (!source || source.length === 0) {
            for (let i = 0; i < count; i++) out.push(0.0);
            return out;
        }
        for (let i = 0; i < count; i++) {
            let norm = count > 1 ? (i / (count - 1)) : 0;
            let srcIdx = Math.min(source.length - 1, Math.floor(Math.pow(norm, 1.4) * (source.length - 1)));
            let val = source[srcIdx] || 0.0;
            out.push(val < 0.04 ? 0.0 : Math.pow((val - 0.04) / 0.96, 1.25));
        }
        return out;
    }

    Column {
        id: innerCol
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(sideVisRoot.isCompact ? 3 : 4) : (sideVisRoot.isCompact ? 3 : 4)

        Repeater {
            model: sideVisRoot.barCount
            delegate: Rectangle {
                height: barWindow ? barWindow.s(sideVisRoot.isCompact ? 3 : 4) : (sideVisRoot.isCompact ? 3 : 4)
                property real level: (sideVisRoot.barLevels && index < sideVisRoot.barLevels.length) ? sideVisRoot.barLevels[index] : 0.0
                property real minW: barWindow ? barWindow.s(sideVisRoot.isCompact ? 3 : 4) : (sideVisRoot.isCompact ? 3 : 4)
                property real maxW: sideVisRoot.width * 0.65
                width: Math.max(minW, level * maxW)
                radius: height * 0.5
                color: sideVisRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve
                opacity: 0.45 + (level * 0.55)
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on width {
                    NumberAnimation {
                        duration: 55
                        easing.type: Easing.OutQuad
                    }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 55 }
                }
            }
        }
    }
}
