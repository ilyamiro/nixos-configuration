import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../reusables"
import "../../"

Rectangle {
    id: sideTimeDateRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    readonly property bool isRightBar: barWindow ? (barWindow.barPosition === "right") : false

    readonly property string timeHourStr: DateTime.hour
    readonly property string timeMinStr: DateTime.minute
    readonly property string timeSecStr: DateTime.second
    readonly property string timeAmPmStr: DateTime.amPm
    readonly property string dayStr: DateTime.day
    readonly property string monthStr: DateTime.monthShort

    property int animDuration: 600
    property real targetY: 0
    y: targetY

    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging
        NumberAnimation { duration: sideTimeDateRoot.animDuration; easing.type: Easing.OutQuint }
    }

    property real verticalPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    property real baseHeight: timeCol.implicitHeight + (verticalPadding * 2)
    property real baseWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))

    property real targetWidth: moduleActive ? baseWidth : 0
    property real targetHeight: moduleActive ? baseHeight : 0

    MouseArea {
        id: bgMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (Caching.serpantinumDir) {
                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "calendar"]);
            }
        }
    }

    property bool isHovered: bgMouse.containsMouse
    property bool showLayout: false

    property real targetX: isRightBar ? (parent ? (parent.width - targetWidth) : 0) : 0
    x: targetX

    Behavior on x {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideTimeDateRoot.animDuration; easing.type: Easing.OutQuint }
    }

    width: targetWidth
    height: targetHeight

    color: "transparent"
    border.width: 0
    clip: true
    visible: (height > 0 || opacity > 0) && (!barWindow || !barWindow.positionChanging)
    opacity: (showLayout && moduleActive && (!barWindow || !barWindow.positionChanging)) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0

    Rectangle {
        id: bgRect
        z: -1
        width: parent.width
        height: parent.height
        radius: ThemeBackend.borderRadius
        color: sideTimeDateRoot.isGrouped ? "transparent" : (sideTimeDateRoot.isSolid ? (sideTimeDateRoot.distinctPills ? (sideTimeDateRoot.isHovered ? ThemeBackend.surface0 : Qt.darker(ThemeBackend.surface0, 1.15)) : "transparent") : (sideTimeDateRoot.isHovered ? ThemeBackend.surface0 : ThemeBackend.base))
        border.width: 0
        visible: height > 0

        Behavior on color { enabled: barWindow ? !barWindow.positionChanging : true; ColorAnimation { duration: 250 } }
    }

    Behavior on width {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideTimeDateRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideTimeDateRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
    }

    transform: Translate {
        x: sideTimeDateRoot.showLayout ? 0 : (barWindow ? (sideTimeDateRoot.isRightBar ? barWindow.s(20) : barWindow.s(-20)) : (sideTimeDateRoot.isRightBar ? 20 : -20))
        Behavior on x {
            enabled: barWindow ? !barWindow.positionChanging : true
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Timer {
        running: barWindow && barWindow.isStartupReady
        interval: 120
        onTriggered: sideTimeDateRoot.showLayout = true
    }

    Item {
        id: topArea
        width: parent.width
        height: parent.height
        anchors.centerIn: parent

        Column {
            id: timeCol
            anchors.centerIn: parent
            spacing: barWindow ? barWindow.s(1) : 1

            Text {
                text: timeHourStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 13 : 14) : (sideTimeDateRoot.isCompact ? 13 : 14)
                font.weight: Font.Black
                color: sideTimeDateRoot.isCompact ? Qt.lighter(ThemeBackend.blue, 1.1) : ThemeBackend.blue
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: timeMinStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 13 : 14) : (sideTimeDateRoot.isCompact ? 13 : 14)
                font.weight: Font.Black
                color: sideTimeDateRoot.isCompact ? Qt.lighter(ThemeBackend.sapphire, 1.1) : ThemeBackend.sapphire
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                visible: timeSecStr !== ""
                text: timeSecStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 13 : 14) : (sideTimeDateRoot.isCompact ? 13 : 14)
                font.weight: Font.Bold
                color: sideTimeDateRoot.isCompact ? Qt.lighter(ThemeBackend.teal, 1.1) : ThemeBackend.teal
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                visible: timeAmPmStr !== ""
                text: timeAmPmStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 13 : 14) : (sideTimeDateRoot.isCompact ? 13 : 14)
                font.weight: Font.Bold
                color: sideTimeDateRoot.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.1) : ThemeBackend.mauve
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Item {
                width: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 14 : 16) : (sideTimeDateRoot.isCompact ? 14 : 16)
                height: barWindow ? barWindow.s(12) : 12
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 2
                    color: ThemeBackend.surface1
                }
            }

            Text {
                text: dayStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 11 : 12) : (sideTimeDateRoot.isCompact ? 11 : 12)
                font.weight: Font.Bold
                color: ThemeBackend.text
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: monthStr
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideTimeDateRoot.isCompact ? 9 : 10) : (sideTimeDateRoot.isCompact ? 9 : 10)
                font.weight: Font.Bold
                color: sideTimeDateRoot.isCompact ? Qt.lighter(ThemeBackend.subtext0, 1.08) : ThemeBackend.subtext0
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
