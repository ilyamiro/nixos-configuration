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
    id: sideTrayWidgetRoot
    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property bool suppressAnimation: false

    property real targetY: 0
    property bool showLayout: false

    property bool isRightBar: barWindow ? (barWindow.barPosition === "right") : false
    property bool isBottomAligned: true

    readonly property real iconSize: barWindow ? barWindow.s(isCompact ? 15 : 16) : (isCompact ? 15 : 16)
    readonly property real itemSpacing: barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10)
    readonly property real iconPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    readonly property real totalPadding: iconPadding * 2
    readonly property int itemCount: (moduleActive && trayRepeater.count > 0) ? trayRepeater.count : 0

    property real baseWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real targetWidth: baseWidth
    width: targetWidth
    Behavior on width {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    property real baseHeight: itemCount > 0 ? (itemCount * iconSize + (itemCount - 1) * itemSpacing + totalPadding) : 0
    property real targetHeight: baseHeight
    height: targetHeight
    Behavior on height {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    property real targetX: isRightBar ? (parent ? (parent.width - targetWidth) : 0) : 0
    x: targetX
    Behavior on x {
        enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation) : !suppressAnimation
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    y: targetY
    Behavior on y {
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
        color: sideTrayWidgetRoot.isGrouped ? "transparent" : (sideTrayWidgetRoot.isSolid ? (sideTrayWidgetRoot.distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
        visible: height > 0
    }

    opacity: (showLayout && targetHeight > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0
    Behavior on opacity {
        enabled: barWindow ? (!barWindow.positionChanging && !suppressAnimation) : true
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Timer {
        running: sideTrayWidgetRoot.moduleActive && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: sideTrayWidgetRoot.showLayout = true
    }

    transform: Translate {
        y: sideTrayWidgetRoot.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on y {
            enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging && !suppressAnimation
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Column {
        id: trayLayout
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: sideTrayWidgetRoot.isBottomAligned ? undefined : parent.top
        anchors.topMargin: sideTrayWidgetRoot.isBottomAligned ? 0 : sideTrayWidgetRoot.iconPadding
        anchors.bottom: sideTrayWidgetRoot.isBottomAligned ? parent.bottom : undefined
        anchors.bottomMargin: sideTrayWidgetRoot.isBottomAligned ? sideTrayWidgetRoot.iconPadding : 0
        spacing: sideTrayWidgetRoot.itemSpacing

        Repeater {
            id: trayRepeater
            model: sideTrayWidgetRoot.moduleActive ? SystemTray.items : null

            onCountChanged: {
                if (count === 0) {
                    TrayMenuController.hide();
                }
            }

            delegate: Image {
                id: trayIcon
                source: modelData.icon || ""
                fillMode: Image.PreserveAspectFit

                sourceSize: Qt.size(sideTrayWidgetRoot.iconSize, sideTrayWidgetRoot.iconSize)
                width: sideTrayWidgetRoot.iconSize
                height: sideTrayWidgetRoot.iconSize
                anchors.horizontalCenter: parent.horizontalCenter

                property bool isHovered: trayMouse.containsMouse
                property bool initAnimTrigger: false
                opacity: initAnimTrigger ? (isHovered ? 1.0 : (sideTrayWidgetRoot.isCompact ? 0.9 : 0.8)) : 0.0
                scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                Component.onCompleted: {
                    if (barWindow && !barWindow.startupCascadeFinished) {
                        trayAnimTimer.interval = index * 45 + 180
                        if (sideTrayWidgetRoot.moduleActive) trayAnimTimer.start()
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
                    let globX = isRightBar ? pt.x : (pt.x + width);
                    let globY = pt.y + (height / 2);
                    let idStr = (modelData && modelData.id !== undefined && modelData.id !== null && String(modelData.id).length > 0) ? String(modelData.id) : String(index);

                    if (action === "toggle") {
                        TrayMenuController.toggle(idStr, scr, globX, globY, isRightBar, false, true);
                    } else {
                        TrayMenuController.itemEntered(idStr, scr, globX, globY, isRightBar, false, true);
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
