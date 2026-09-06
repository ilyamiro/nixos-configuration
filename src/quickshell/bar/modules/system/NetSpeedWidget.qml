import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../reusables"
import "../../../"

Rectangle {
    id: root

    property var barWindow
    property bool isSolid: false
    property bool moduleActive: true
    property bool isGrouped: false
    property real targetX: 0

    x: targetX
    y: barWindow ? barWindow.baseOffsetY : 0

    height: barWindow ? barWindow.barHeight : 40
    width: barWindow ? barWindow.s(180) : 180

    radius: Math.min(
        ThemeBackend.borderRadius,
        height / 2
    )

    color: (isGrouped || isSolid)
        ? "transparent"
        : ThemeBackend.base

    border.color: (isGrouped || isSolid)
        ? "transparent"
        : ThemeBackend.surface0

    border.width: (isGrouped || isSolid) ? 0 : 1

    visible: moduleActive

    opacity: moduleActive
        ? ((barWindow && barWindow.barOpacity !== undefined)
            ? barWindow.barOpacity
            : 1.0)
        : 0.0

    function updateSubscription() {
        if (moduleActive) {
            SysData.subscribe()
        } else {
            SysData.unsubscribe()
        }
    }

    Component.onCompleted: updateSubscription()
    Component.onDestruction: SysData.unsubscribe()
    onModuleActiveChanged: updateSubscription()

    function formatSpeed(value) {
        if (value <= 0 || isNaN(value))
            return "0 B/s"

        let k = 1024
        let sizes = ["B/s", "KB/s", "MB/s", "GB/s"]
        let i = Math.floor(Math.log(value) / Math.log(k))

        return parseFloat(
            (value / Math.pow(k, i)).toFixed(1)
        ) + " " + sizes[i]
    }

    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished

        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        id: netLayout

        anchors.centerIn: parent

        spacing: barWindow ? barWindow.s(6) : 6

        Text {
            text: "\uF063"

            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow
                ? barWindow.s(11.55)
                : 11.55

            color: ThemeBackend.subtext0

            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root.formatSpeed(SysData.netRx)

            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow
                ? barWindow.s(12.6)
                : 12.6

            font.bold: true
            color: ThemeBackend.text

            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: "\uF062"

            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow
                ? barWindow.s(11.55)
                : 11.55

            color: ThemeBackend.subtext0

            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root.formatSpeed(SysData.netTx)

            font.family: ThemeBackend.fontFamily
            font.pixelSize: barWindow
                ? barWindow.s(12.6)
                : 12.6

            font.bold: true
            color: ThemeBackend.text

            Layout.alignment: Qt.AlignVCenter
        }
    }
}
