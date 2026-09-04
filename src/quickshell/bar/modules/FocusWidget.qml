import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../reusables"
import "../../singletons"
import "../../"

Rectangle {
    id: focusWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property real targetX: 0

    readonly property string displayText: CurrentFocus.displayText
    readonly property bool isFocused: CurrentFocus.isFocused

    property real leftPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(6) : 6)
    property real rightPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(12) : 12)
    property real targetWidth: (moduleActive && isFocused) ? (leftPadding + focusIconButton.width + innerLayout.spacing + titleTextMain.implicitWidth + rightPadding) : 0

    x: targetX
    Behavior on x {
        enabled: barWindow && barWindow.startupCascadeFinished
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    height: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    y: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - height) / 2 : 0
    radius: ThemeBackend.borderRadius
    color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
    border.width: 0
    clip: true

    width: targetWidth
    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    opacity: (moduleActive && isFocused) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: innerLayout
        anchors.left: parent.left
        anchors.leftMargin: focusWidgetRoot.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 5 : 6) : (focusWidgetRoot.isCompact ? 5 : 6)

        property bool initAnimTrigger: !barWindow || barWindow.startupCascadeFinished

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            y: innerLayout.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        IconButton {
            id: focusIconButton
            width: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 28 : 30) : (focusWidgetRoot.isCompact ? 28 : 30)
            height: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 28 : 30) : (focusWidgetRoot.isCompact ? 28 : 30)
            cornerRadius: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 9 : 10) : (focusWidgetRoot.isCompact ? 9 : 10)
            buttonIcon: "✦"
            iconFontSize: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 14 : 15) : (focusWidgetRoot.isCompact ? 14 : 15)
            accentColor: focusWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (focusWidgetRoot.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
                if (Caching.serpantinumDir) {
                    Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
                }
            }
        }

        Item {
            id: titleClipRect
            width: titleTextMain.implicitWidth
            height: titleTextMain.implicitHeight
            clip: true
            anchors.verticalCenter: parent.verticalCenter

            property int marqueeSpacing: barWindow ? barWindow.s(30) : 30

            Item {
                id: marqueeContainer
                height: parent.height

                Row {
                    spacing: titleClipRect.marqueeSpacing
                    Text {
                        id: titleTextMain
                        text: focusWidgetRoot.displayText
                        color: ThemeBackend.text
                        font.pixelSize: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 11 : 12) : (focusWidgetRoot.isCompact ? 11 : 12)

                        onTextChanged: {
                            titleAnim.stop();
                            marqueeContainer.x = 0;
                            if (titleTextMain.implicitWidth > titleClipRect.width) {
                                titleAnim.start();
                            }
                        }
                    }

                    Text {
                        id: titleTextClone
                        text: titleTextMain.text
                        color: ThemeBackend.text
                        font.pixelSize: barWindow ? barWindow.s(focusWidgetRoot.isCompact ? 11 : 12) : (focusWidgetRoot.isCompact ? 11 : 12)
                        visible: titleTextMain.implicitWidth > titleClipRect.width
                    }
                }

                SequentialAnimation {
                    id: titleAnim
                    loops: Animation.Infinite
                    running: titleTextMain.implicitWidth > titleClipRect.width

                    PauseAnimation { duration: 3000 }

                    NumberAnimation {
                        target: marqueeContainer
                        property: "x"
                        from: 0
                        to: -(titleTextMain.implicitWidth + titleClipRect.marqueeSpacing)
                        duration: Math.max(1, (titleTextMain.implicitWidth + titleClipRect.marqueeSpacing) * 25)
                    }

                    PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: {
            if (Caching.serpantinumDir) {
                Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
            }
        }
    }
}
