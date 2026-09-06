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
    id: trayWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property bool suppressAnimation: false

    property real targetX: 0
    property bool showLayout: false

    property bool isBottomBar: barWindow ? (barWindow.barPosition === "bottom") : false
    property bool isRightAligned: true

    readonly property real iconSize: barWindow ? barWindow.s(isCompact ? 15 : 16) : (isCompact ? 15 : 16)
    readonly property real itemSpacing: barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10)
    readonly property real iconPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    readonly property real totalPadding: iconPadding * 2
    readonly property int itemCount: (moduleActive && trayRepeater.count > 0) ? trayRepeater.count : 0

    property real baseHeight: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetHeight: baseHeight
    height: targetHeight
    property real targetY: barWindow ? barWindow.baseOffsetY + (barWindow.barHeight - targetHeight) / 2 : 0
    y: targetY

    Behavior on y {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    property real baseWidth: itemCount > 0 ? (itemCount * iconSize + (itemCount - 1) * itemSpacing + totalPadding) : 0
    property real targetWidth: baseWidth
    width: targetWidth
    Behavior on width {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    x: targetX
    Behavior on x {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    onVisibleChanged: {
        if (!visible) {
            TrayMenuController.hide();
        }
    }

    onModuleActiveChanged: {
        if (!moduleActive) {
            TrayMenuController.hide();
        }
    }

    Connections {
        target: barWindow || null
        function onPositionChangingChanged() {
            if (barWindow && barWindow.positionChanging) {
                TrayMenuController.hide();
            }
        }
        function onBarPositionChanged() {
            TrayMenuController.hide();
        }
        function onIsRevealedChanged() {
            if (barWindow && !barWindow.isRevealed && !TrayMenuController.menuHovered) {
                TrayMenuController.hide();
            }
        }
    }

    color: "transparent"
    border.width: 0
    border.color: "transparent"
    clip: false

    Rectangle {
        id: bgRect
        z: -1
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        border.width: 0
        color: trayWidgetRoot.isGrouped ? "transparent" : (trayWidgetRoot.isSolid ? (trayWidgetRoot.distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
        visible: width > 0
    }

    opacity: (showLayout && targetWidth > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity {
        enabled: barWindow ? (!barWindow.positionChanging && !suppressAnimation) : true
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Timer {
        running: trayWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: trayWidgetRoot.showLayout = true
    }

    transform: Translate {
        x: trayWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on x {
            enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Row {
        id: trayLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: trayWidgetRoot.isRightAligned ? undefined : parent.left
        anchors.leftMargin: trayWidgetRoot.isRightAligned ? 0 : trayWidgetRoot.iconPadding
        anchors.right: trayWidgetRoot.isRightAligned ? parent.right : undefined
        anchors.rightMargin: trayWidgetRoot.isRightAligned ? trayWidgetRoot.iconPadding : 0
        spacing: trayWidgetRoot.itemSpacing

        Repeater {
            id: trayRepeater
            model: trayWidgetRoot.moduleActive ? SystemTray.items : null

            onCountChanged: {
                if (count === 0) {
                    TrayMenuController.hide();
                }
            }

            delegate: Image {
                id: trayIcon
                source: modelData.icon || ""
                fillMode: Image.PreserveAspectFit

                sourceSize: Qt.size(trayWidgetRoot.iconSize, trayWidgetRoot.iconSize)
                width: trayWidgetRoot.iconSize
                height: trayWidgetRoot.iconSize
                anchors.verticalCenter: parent.verticalCenter

                property bool isHovered: trayMouse.containsMouse
                property bool initAnimTrigger: false
                opacity: initAnimTrigger ? (isHovered ? 1.0 : (trayWidgetRoot.isCompact ? 0.9 : 0.8)) : 0.0
                scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                Component.onCompleted: {
                    if (barWindow && !barWindow.startupCascadeFinished) {
                        trayAnimTimer.interval = index * 45 + 180
                        if (trayWidgetRoot.moduleActive) trayAnimTimer.start()
                    } else {
                        initAnimTrigger = true
                    }
                }

                Component.onDestruction: {
                    if (trayMouse.containsMouse) {
                        TrayMenuController.itemExited();
                    }
                    let idStr = (modelData && modelData.id !== undefined && modelData.id !== null && String(modelData.id).length > 0) ? String(modelData.id) : String(index);
                    if (TrayMenuController.activeItemId === idStr) {
                        TrayMenuController.hide();
                    }
                }

                Timer {
                    id: trayAnimTimer
                    running: false
                    repeat: false
                    onTriggered: trayIcon.initAnimTrigger = true
                }

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                function openMenu(action) {
                    TrayMenuController.cancelHide();
                    let pt = trayIcon.mapToItem(null, 0, 0);
                    let scr = (barWindow && barWindow.screen) ? barWindow.screen : null;
                    let globX = pt.x + (width / 2);
                    let globY = isBottomBar ? pt.y : (pt.y + height);
                    let idStr = (modelData && modelData.id !== undefined && modelData.id !== null && String(modelData.id).length > 0) ? String(modelData.id) : String(index);

                    if (action === "toggle") {
                        TrayMenuController.toggle(idStr, scr, globX, globY, false, isBottomBar, false);
                    } else {
                        TrayMenuController.itemEntered(idStr, scr, globX, globY, false, isBottomBar, false);
                    }
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    anchors.margins: -(barWindow ? barWindow.s(4) : 4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onEntered: {
                        trayIcon.openMenu("show");
                    }

                    onExited: {
                        TrayMenuController.itemExited();
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            if (modelData.isMenuOnly || modelData.onlyMenu) {
                                trayIcon.openMenu("toggle");
                            } else if (typeof modelData.activate === "function") {
                                modelData.activate();
                            }
                        } else if (mouse.button === Qt.MiddleButton) {
                            if (typeof modelData.secondaryActivate === "function") {
                                modelData.secondaryActivate();
                            }
                        } else if (mouse.button === Qt.RightButton) {
                            if (modelData.menu) {
                                trayIcon.openMenu("toggle");
                            } else if (typeof modelData.contextMenu === "function") {
                                modelData.contextMenu(mouse.x, mouse.y);
                            } else if (typeof modelData.activate === "function") {
                                modelData.activate();
                            }
                        }
                    }
                }
            }
        }
    }
}
