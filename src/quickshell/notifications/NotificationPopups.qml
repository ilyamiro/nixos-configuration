import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../"
import "../reusables"

PanelWindow {
    id: popupWindow

    readonly property real sf: Scaler.baseScale

    function s(val) {
        return Math.round(val * popupWindow.sf);
    }

    property bool hasCriticalPopup: {
        for (let i = 0; i < NotificationManager.activePopupsModel.count; i++) {
            let p = NotificationManager.activePopupsModel.get(i);
            if (p && p.urgency === 2) return true;
        }
        return false;
    }

    visible: (!popupWindow.dndEnabled || popupWindow.hasCriticalPopup) && !NotificationManager.sysPanelOpen && NotificationManager.activePopupsModel.count > 0

    function storeNotif(uid, notif) {
        NotificationManager.liveNotifs[uid] = notif;
    }

    function getNotif(uid) {
        return NotificationManager.liveNotifs[uid] || null;
    }

    function removeNotif(uid) {
        delete NotificationManager.liveNotifs[uid];
        NotificationManager.removePopup(uid);
    }

    property var rawBarSettings: Config.getSetting("bar", {})
    property string barPosition: (rawBarSettings && rawBarSettings.position !== undefined) ? rawBarSettings.position : "top"
    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false

    readonly property bool isFullscreenActive: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive

    property string barStyle: {
        if (!rawBarSettings || rawBarSettings.style === undefined) return "modular";
        let st = rawBarSettings.style;
        if (typeof st === "string") return st;
        if (typeof st === "object") {
            if (st.fill || st.mode === "fill") return "fill";
            if (st.solid || st.mode === "solid") return "solid";
        }
        return "modular";
    }
    property bool isBarFill: barStyle === "fill"
    property int barThickness: s(40) + (isBarFill || isBarEffectivelyHidden ? 0 : s(4))

    property var notifSettings: Config.getSetting("notifications", { "dnd": false, "position": "top right" })
    property string position: notifSettings.position !== undefined ? notifSettings.position : "top right"
    property bool isTop: position.indexOf("top") !== -1
    property bool isBottom: position.indexOf("bottom") !== -1
    property bool isCenter: position.indexOf("center") !== -1
    property bool isLeft: position.indexOf("left") !== -1
    property bool isRight: position.indexOf("right") !== -1 || (!isLeft && !isCenter)

    WlrLayershell.namespace: "qs-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: true
        bottom: true
        left: popupWindow.isLeft
        right: popupWindow.isRight
    }

    margins {
        top: (popupWindow.barPosition === "top" && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + popupWindow.s(12)
        bottom: (popupWindow.barPosition === "bottom" && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + popupWindow.s(12)
        left: (popupWindow.barPosition === "left" && popupWindow.isLeft && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + (popupWindow.isLeft ? popupWindow.s(16) : 0)
        right: (popupWindow.barPosition === "right" && popupWindow.isRight && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + (popupWindow.isRight ? popupWindow.s(16) : 0)
    }

    exclusionMode: ExclusionMode.Ignore
    focusable: false
    color: "transparent"

    implicitWidth: s(350)

    mask: Region {
        item: popupList
    }

    property bool dndEnabled: {
        let n = Config.getSetting("notifications", { "dnd": false, "position": "top right" });
        return Boolean(n && n.dnd);
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            let n = Config.getSetting("notifications", { "dnd": false, "position": "top right" });
            popupWindow.dndEnabled = Boolean(n && n.dnd);
            popupWindow.position = (n && n.position !== undefined) ? n.position : "top right";
            popupWindow.rawBarSettings = Config.getSetting("bar", {});
            popupWindow.barPosition = (popupWindow.rawBarSettings && popupWindow.rawBarSettings.position !== undefined) ? popupWindow.rawBarSettings.position : "top";
            popupWindow.barAutohide = (popupWindow.rawBarSettings && popupWindow.rawBarSettings.autohide !== undefined) ? Boolean(popupWindow.rawBarSettings.autohide) : false;
        }
    }

    Item {
        id: popupRoot
        anchors.fill: parent

        function s(val) {
            return popupWindow.s(val);
        }

        ListView {
            id: popupList
            anchors.top: popupWindow.isTop ? parent.top : undefined
            anchors.bottom: popupWindow.isBottom ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: parent.right
            verticalLayoutDirection: popupWindow.isBottom ? ListView.BottomToTop : ListView.TopToBottom
            height: Math.min(parent.height, contentHeight)
            model: NotificationManager.activePopupsModel
            spacing: popupWindow.s(12)
            interactive: false
            clip: false
            boundsBehavior: Flickable.StopAtBounds

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation {
                        property: "x"
                        from: popupWindow.isCenter ? 0 : (popupWindow.isLeft ? -1 : 1) * popupWindow.width * 0.35
                        to: 0
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "y"
                        from: popupWindow.isCenter ? (popupWindow.isBottom ? popupWindow.s(24) : -popupWindow.s(24)) : 0
                        to: 0
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
            }

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation {
                        property: "x"
                        to: popupWindow.isCenter ? 0 : (popupWindow.isLeft ? -1 : 1) * popupWindow.width * 0.35
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "y"
                        to: popupWindow.isCenter ? (popupWindow.isBottom ? popupWindow.s(24) : -popupWindow.s(24)) : 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            displaced: Transition {
                NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
            }

            removeDisplaced: Transition {
                NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: delegateWrapper
                width: ListView.view.width

                property bool isSuppressedByDnd: popupWindow.dndEnabled && model.urgency !== 2

                implicitHeight: isSuppressedByDnd ? 0 : (typeLoader.item ? typeLoader.item.implicitHeight : popupWindow.s(70))
                height: implicitHeight
                visible: !isSuppressedByDnd

                property int popupUid: model.uid || model.latestUid
                property var realNotif: popupWindow.getNotif(popupUid) || (model.notif ? model.notif : null)
                property bool isPopupContext: true
                property var msgModel: model
                property bool isExpanded: typeLoader.item && typeLoader.item.expanded ? true : false
                property bool isHovered: typeLoader.item && typeLoader.item.isHovered ? true : false
                property bool isDragging: typeLoader.item && typeLoader.item.isDragging ? true : false

                property var actionArray: {
                    try {
                        return model.actionsJson ? JSON.parse(model.actionsJson) : []
                    } catch (e) {
                        return []
                    }
                }

                property int effectiveTimeout: {
                    if (model.urgency === 2) return 0;
                    var n = delegateWrapper.realNotif;
                    if (!n) return 5000;
                    var t = typeof n.expireTimeout === "number" ? n.expireTimeout : (typeof n.timeout === "number" ? n.timeout : -1);
                    if (t === 0) return 0;
                    if (t > 0) return t;
                    return 5000;
                }

                Connections {
                    target: delegateWrapper.realNotif || null
                    function onClosed() {
                        popupWindow.removeNotif(delegateWrapper.popupUid);
                    }
                }

                Timer {
                    id: dismissTimer
                    interval: delegateWrapper.effectiveTimeout > 0 ? delegateWrapper.effectiveTimeout : 5000
                    running: delegateWrapper.effectiveTimeout > 0 && !delegateWrapper.isHovered && !delegateWrapper.isExpanded && !delegateWrapper.isDragging
                    repeat: false
                    onTriggered: popupWindow.removeNotif(delegateWrapper.popupUid)
                }

                function removeThisNotif() {
                    popupWindow.removeNotif(delegateWrapper.popupUid);
                }

                Loader {
                    id: typeLoader
                    width: parent.width
                    source: {
                        let app = (model.appName || "").toLowerCase();
                        if (app === "weather") return "types/Weather.qml";
                        if (app === "screenshot" || app === "screen recorder") return "types/Screenshot.qml";
                        if (app === "battery" || app === "bat" || app === "power") return "types/Battery.qml";
                        return "types/Default.qml";
                    }
                    onLoaded: {
                        if (item) {
                            item.model = delegateWrapper.msgModel;
                            item.root = popupRoot;
                            item.delegateWrapper = delegateWrapper;
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: NotificationManager
        function onPopupAdded(uid, notif) {
            popupWindow.storeNotif(uid, notif);
        }
    }
}
