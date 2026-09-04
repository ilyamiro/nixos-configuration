import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../reusables"
import "../../"

Rectangle {
    id: sideMediaRoot

    property var barWindow
    property bool isSolid: false
    property bool distinctPills: barWindow ? (barWindow.distinctPills !== undefined ? barWindow.distinctPills : false) : false
    property bool moduleActive: true
    property bool isGrouped: false
    property bool isCompact: isGrouped || (isSolid && distinctPills)
    property bool layoutAnimationsEnabled: true

    property var playerList: {
        if (!Mpris.players || !Mpris.players.values) return [];
        let list = [];
        let vals = Mpris.players.values;
        for (let i = 0; i < vals.length; i++) {
            if (vals[i]) list.push(vals[i]);
        }
        return list;
    }

    property var manualPlayer: null

    property var targetPlayer: {
        if (manualPlayer) {
            for (let i = 0; i < playerList.length; i++) {
                if (playerList[i] === manualPlayer) return manualPlayer;
            }
        }
        return MprisController.activePlayer;
    }

    property bool hasTargetPlayer: targetPlayer !== null
    property bool isMediaActive: targetPlayer !== null && targetPlayer.playbackState !== MprisPlaybackState.Stopped && targetPlayer.trackTitle !== ""
    property bool isPlaying: targetPlayer ? (targetPlayer.playbackState === MprisPlaybackState.Playing || targetPlayer.isPlaying) : false
    readonly property bool isRightBar: barWindow ? (barWindow.barPosition === "right") : false

    property string rawArtUrl: {
        if (!targetPlayer) return "";
        if (targetPlayer === MprisController.activePlayer) {
            return MprisController.artUrl;
        }
        return targetPlayer.trackArtUrl || "";
    }

    property string activeArtUrl: {
        if (!rawArtUrl) return "";
        if (rawArtUrl.startsWith("file://") || rawArtUrl.startsWith("http")) return rawArtUrl;
        return "file://" + rawArtUrl;
    }

    property real targetWidth: barWindow ? (isGrouped ? barWindow.barHeight - 8 : ((isSolid && distinctPills) ? barWindow.barHeight - 6 : barWindow.barHeight)) : (isGrouped ? 22 : ((isSolid && distinctPills) ? 24 : 30))
    property real baseWidth: targetWidth
    property real baseHeight: barWindow ? barWindow.s(isCompact ? 118 : 130) : (isCompact ? 118 : 130)
    property real targetHeight: baseHeight

    property real targetX: isRightBar ? (parent ? (parent.width - baseWidth) : 0) : 0
    property real targetY: 0

    x: targetX
    y: targetY
    width: targetWidth
    height: targetHeight
    z: 1
    clip: true

    color: "transparent"
    border.width: 0
    border.color: "transparent"

    opacity: moduleActive ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0
    visible: opacity > 0 && (!barWindow || !barWindow.positionChanging)

    Behavior on x {
        enabled: layoutAnimationsEnabled && (barWindow ? !barWindow.positionChanging : true)
        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
    }
    Behavior on width {
        enabled: layoutAnimationsEnabled && (barWindow ? !barWindow.positionChanging : true)
        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
    }
    Behavior on height {
        enabled: layoutAnimationsEnabled && (barWindow ? !barWindow.positionChanging : true)
        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        z: -1
        radius: ThemeBackend.borderRadius
        color: isGrouped ? "transparent" : (isSolid ? (distinctPills ? Qt.darker(ThemeBackend.surface0, 1.15) : "transparent") : ThemeBackend.base)
        border.width: 0
        clip: true
    }

    MouseArea {
        id: widgetMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            let pt = sideMediaRoot.mapToItem(null, 0, 0);
            let globX = isRightBar ? pt.x : (pt.x + width);
            let globY = pt.y + (height / 2);
            SideMusicController.itemEntered(barWindow ? barWindow.screen : null, globX, globY, isRightBar, false, true);
        }
        onExited: {
            SideMusicController.itemExited();
        }
        onClicked: {
            let pt = sideMediaRoot.mapToItem(null, 0, 0);
            let globX = isRightBar ? pt.x : (pt.x + width);
            let globY = pt.y + (height / 2);
            SideMusicController.toggle(barWindow ? barWindow.screen : null, globX, globY, isRightBar, false, true);
        }
    }

    Column {
        id: baseCol
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 4 : 5) : (sideMediaRoot.isCompact ? 4 : 5)

        Rectangle {
            id: thumbBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 26 : 28) : (sideMediaRoot.isCompact ? 26 : 28)
            height: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 26 : 28) : (sideMediaRoot.isCompact ? 26 : 28)
            radius: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 7 : 8) : (sideMediaRoot.isCompact ? 7 : 8)
            color: sideMediaRoot.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.1) : ThemeBackend.surface1
            border.width: 1
            border.color: (isMediaActive && isPlaying) ? ThemeBackend.mauve : (sideMediaRoot.isCompact ? ThemeBackend.surface2 : ThemeBackend.surface1)
            clip: true

            Text {
                anchors.centerIn: parent
                text: "󰎈"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 12 : 13) : (sideMediaRoot.isCompact ? 12 : 13)
                color: sideMediaRoot.isCompact ? ThemeBackend.text : ThemeBackend.subtext0
                visible: !isMediaActive || sideMediaRoot.activeArtUrl === ""
            }

            Image {
                id: sideArtImg
                anchors.fill: parent
                source: isMediaActive ? sideMediaRoot.activeArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            MultiEffect {
                anchors.fill: sideArtImg
                source: sideArtImg
                maskEnabled: true
                maskSource: sideArtMask
                visible: isMediaActive && sideMediaRoot.activeArtUrl !== "" && sideArtImg.status === Image.Ready
            }

            Item {
                id: sideArtMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: thumbBox.radius
                    color: "black"
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ThemeBackend.surface0
                opacity: 0.15
                visible: isMediaActive && sideMediaRoot.activeArtUrl !== "" && sideArtImg.status === Image.Ready
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Caching.serpantinumDir) {
                        Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle music"]);
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 3 : 4) : (sideMediaRoot.isCompact ? 3 : 4)

            IconButton {
                width: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 24 : 26) : (sideMediaRoot.isCompact ? 24 : 26)
                height: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 24 : 26) : (sideMediaRoot.isCompact ? 24 : 26)
                cornerRadius: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 7 : 8) : (sideMediaRoot.isCompact ? 7 : 8)
                buttonIcon: "󰒮"
                iconFontSize: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 12 : 13) : (sideMediaRoot.isCompact ? 12 : 13)
                accentColor: sideMediaRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.text : (sideMediaRoot.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: if (targetPlayer && targetPlayer.canGoPrevious) targetPlayer.previous()
            }

            IconButton {
                width: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 26 : 28) : (sideMediaRoot.isCompact ? 26 : 28)
                height: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 26 : 28) : (sideMediaRoot.isCompact ? 26 : 28)
                cornerRadius: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 7 : 8) : (sideMediaRoot.isCompact ? 7 : 8)
                buttonIcon: (isMediaActive && isPlaying) ? "󰏤" : "󰐊"
                iconFontSize: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 14 : 15) : (sideMediaRoot.isCompact ? 14 : 15)
                accentColor: sideMediaRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.green : (sideMediaRoot.isCompact ? Qt.lighter(ThemeBackend.text, 1.1) : ThemeBackend.text)
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: if (targetPlayer && targetPlayer.canTogglePlaying) targetPlayer.togglePlaying()
            }

            IconButton {
                width: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 24 : 26) : (sideMediaRoot.isCompact ? 24 : 26)
                height: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 24 : 26) : (sideMediaRoot.isCompact ? 24 : 26)
                cornerRadius: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 7 : 8) : (sideMediaRoot.isCompact ? 7 : 8)
                buttonIcon: "󰒭"
                iconFontSize: barWindow ? barWindow.s(sideMediaRoot.isCompact ? 12 : 13) : (sideMediaRoot.isCompact ? 12 : 13)
                accentColor: sideMediaRoot.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.text : (sideMediaRoot.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: if (targetPlayer && targetPlayer.canGoNext) targetPlayer.next()
            }
        }
    }
}
