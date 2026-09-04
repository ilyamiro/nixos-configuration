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
    id: sideWeatherWidgetRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    readonly property bool isRightBar: barWindow ? (barWindow.barPosition === "right") : false

    property string weatherIcon: Weather.currentIcon
    property string weatherTemp: {
        let raw = Weather.currentTemp !== "" ? Weather.currentTemp : Weather.currentTempFormatted;
        if (!raw || raw === "") return "--°";
        let intPart = raw.split(".")[0].replace(/[^\d-]/g, "");
        return (intPart !== "" ? intPart : "--") + "°";
    }
    property string weatherHex: Weather.currentHex
    property bool isWeatherLoading: Weather.isLoading || !Weather.isReady

    property int animDuration: 600
    property real targetY: 0
    y: targetY

    Behavior on y {
        enabled: barWindow && barWindow.startupCascadeFinished && !barWindow.positionChanging
        NumberAnimation { duration: sideWeatherWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }

    property real verticalPadding: barWindow ? barWindow.s(isCompact ? 10 : 12) : (isCompact ? 10 : 12)
    property real baseHeight: weatherCol.implicitHeight + (verticalPadding * 2)
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
        NumberAnimation { duration: sideWeatherWidgetRoot.animDuration; easing.type: Easing.OutQuint }
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
        color: sideWeatherWidgetRoot.isGrouped ? "transparent" : (sideWeatherWidgetRoot.isSolid ? (sideWeatherWidgetRoot.distinctPills ? (sideWeatherWidgetRoot.isHovered ? ThemeBackend.surface0 : Qt.darker(ThemeBackend.surface0, 1.15)) : "transparent") : (sideWeatherWidgetRoot.isHovered ? ThemeBackend.surface0 : ThemeBackend.base))
        border.width: 0
        visible: height > 0

        Behavior on color { enabled: barWindow ? !barWindow.positionChanging : true; ColorAnimation { duration: 250 } }
    }

    Behavior on width {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideWeatherWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: sideWeatherWidgetRoot.animDuration; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        enabled: barWindow ? !barWindow.positionChanging : true
        NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
    }

    transform: Translate {
        x: sideWeatherWidgetRoot.showLayout ? 0 : (barWindow ? (sideWeatherWidgetRoot.isRightBar ? barWindow.s(20) : barWindow.s(-20)) : (sideWeatherWidgetRoot.isRightBar ? 20 : -20))
        Behavior on x {
            enabled: barWindow ? !barWindow.positionChanging : true
            NumberAnimation { duration: 800; easing.type: Easing.OutQuint }
        }
    }

    Timer {
        running: barWindow && barWindow.isStartupReady
        interval: 120
        onTriggered: sideWeatherWidgetRoot.showLayout = true
    }

    Item {
        id: topArea
        width: parent.width
        height: parent.height
        anchors.centerIn: parent

        Column {
            id: weatherCol
            anchors.centerIn: parent
            spacing: barWindow ? barWindow.s(sideWeatherWidgetRoot.isCompact ? 2 : 3) : (sideWeatherWidgetRoot.isCompact ? 2 : 3)

            LoaderIcon {
                id: weatherLoader
                anchors.horizontalCenter: parent.horizontalCenter
                width: barWindow ? barWindow.s(sideWeatherWidgetRoot.isCompact ? 18 : 20) : (sideWeatherWidgetRoot.isCompact ? 18 : 20)
                height: barWindow ? barWindow.s(sideWeatherWidgetRoot.isCompact ? 18 : 20) : (sideWeatherWidgetRoot.isCompact ? 18 : 20)
                accentColor: ThemeBackend.mauve
                running: sideWeatherWidgetRoot.isWeatherLoading
                visible: sideWeatherWidgetRoot.isWeatherLoading
            }

            Text {
                text: weatherIcon
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: "Iosevka Nerd Font"
                font.pixelSize: barWindow ? barWindow.s(sideWeatherWidgetRoot.isCompact ? 16 : 18) : (sideWeatherWidgetRoot.isCompact ? 16 : 18)
                color: Qt.tint(weatherHex, Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, sideWeatherWidgetRoot.isCompact ? 0.3 : 0.4))
                visible: !sideWeatherWidgetRoot.isWeatherLoading && weatherIcon !== ""
            }

            Text {
                text: weatherTemp
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideWeatherWidgetRoot.isCompact ? 11 : 12) : (sideWeatherWidgetRoot.isCompact ? 11 : 12)
                font.weight: Font.Black
                color: sideWeatherWidgetRoot.isCompact ? Qt.lighter(ThemeBackend.peach, 1.1) : ThemeBackend.peach
                visible: !sideWeatherWidgetRoot.isWeatherLoading
            }
        }
    }
}
