import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Rectangle {
    id: visWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property real targetX: 0
    property bool showLayout: !barWindow || barWindow.isStartupReady
    property int barCount: 16
    property bool isVisVisible: moduleActive && showLayout
    property bool isSubscribed: false
    readonly property bool shouldSubscribe: isVisVisible && MprisController.isPlaying

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
                visWidgetRoot.showLayout = true;
            }
        }
    }

    Component.onCompleted: {
        if (!barWindow || barWindow.isStartupReady) {
            visWidgetRoot.showLayout = true;
        }
        updateSubscription();
    }

    Component.onDestruction: {
        if (isSubscribed) {
            isSubscribed = false;
            Cava.unregisterConsumer();
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

            if (val < 0.04) {
                val = 0.0;
            } else {
                val = Math.pow((val - 0.04) / 0.96, 1.25);
            }
            out.push(val);
        }
        return out;
    }

    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 600; easing.type: Easing.OutQuint }
    }

    height: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    y: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - height) / 2 : 0
    radius: ThemeBackend.borderRadius
    border.width: 0
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    clip: true

    property real targetWidth: (moduleActive && innerLayout.implicitWidth > 0) ? (innerLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 20 : 24) : (isCompact ? 20 : 24))) : 0
    width: targetWidth
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

    opacity: (moduleActive && showLayout) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Timer {
        running: visWidgetRoot.moduleActive && barWindow && !visWidgetRoot.showLayout
        interval: 100
        onTriggered: {
            if (barWindow && barWindow.isStartupReady) {
                visWidgetRoot.showLayout = true;
            }
        }
    }

    Row {
        id: innerLayout
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(visWidgetRoot.isCompact ? 3 : 4) : (visWidgetRoot.isCompact ? 3 : 4)

        Repeater {
            model: visWidgetRoot.barCount
            delegate: Rectangle {
                width: barWindow ? barWindow.s(visWidgetRoot.isCompact ? 4 : 5) : (visWidgetRoot.isCompact ? 4 : 5)
                property real level: (visWidgetRoot.barLevels && index < visWidgetRoot.barLevels.length) ? visWidgetRoot.barLevels[index] : 0.0
                property real minH: barWindow ? barWindow.s(visWidgetRoot.isCompact ? 3 : 4) : (visWidgetRoot.isCompact ? 3 : 4)
                property real maxH: visWidgetRoot.height * 0.65
                height: Math.max(minH, level * maxH)
                radius: width * 0.5
                color: visWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve
                opacity: 0.45 + (level * 0.55)
                anchors.verticalCenter: parent.verticalCenter

                Behavior on height {
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
