import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../reusables"
import "../../"

Rectangle {
    id: leftWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)

    property alias helpButton: helpButton

    property real targetX: 0
    property bool showLayout: barWindow ? Boolean(barWindow.isStartupReady) : true

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

    property real targetWidth: moduleActive ? (leftLayout.width + (barWindow ? barWindow.s(isCompact ? 6 : 8) : (isCompact ? 6 : 8))) : 0
    width: targetWidth
    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }

    opacity: (showLayout && moduleActive) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    enabled: moduleActive

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    transform: Translate {
        x: leftWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(-60) : -60)
        Behavior on x { NumberAnimation { duration: 750; easing.type: Easing.OutQuint } }
    }

    Row {
        id: leftLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: barWindow ? barWindow.s(leftWidgetRoot.isCompact ? 3 : 4) : (leftWidgetRoot.isCompact ? 3 : 4)
        spacing: barWindow ? barWindow.s(leftWidgetRoot.isCompact ? 5 : 6) : (leftWidgetRoot.isCompact ? 5 : 6)

        property int pillHeight: barWindow ? barWindow.s(leftWidgetRoot.isCompact ? 28 : 30) : (leftWidgetRoot.isCompact ? 28 : 30)

        IconButton {
            id: helpButton
            height: leftLayout.pillHeight
            width: barWindow ? barWindow.s(leftWidgetRoot.isCompact ? 30 : 32) : (leftWidgetRoot.isCompact ? 30 : 32)
            visible: true
            iconOffsetX: -2

            cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            buttonIcon: "󰒓"
            iconFontSize: barWindow ? barWindow.s(leftWidgetRoot.isCompact ? 14 : 15) : (leftWidgetRoot.isCompact ? 14 : 15)
            accentColor: leftWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (leftWidgetRoot.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)

            opacity: leftWidgetRoot.showLayout ? 1.0 : 0.0
            transform: Translate {
                y: leftWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(15) : 15)
                Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
            }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle guide"])
        }
    }
}
