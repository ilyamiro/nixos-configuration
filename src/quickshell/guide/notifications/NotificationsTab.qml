import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"

Item {
    id: notificationsTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property var defaultNotificationSettings: ({
        "dnd": false,
        "position": "top right",
        "sound": true,
        "soundFile": "",
        "showEmptyGraphic": true
    })

    property var notifSettings: Config.getSetting("notifications", defaultNotificationSettings)
    property bool dnd: notifSettings.dnd !== undefined ? notifSettings.dnd : false
    property string position: notifSettings.position !== undefined ? notifSettings.position : "top right"
    property bool soundEnabled: notifSettings.sound !== undefined ? notifSettings.sound : true
    property string selectedSound: notifSettings.soundFile !== undefined ? notifSettings.soundFile : ""
    property bool showEmptyGraphic: notifSettings.showEmptyGraphic !== undefined ? notifSettings.showEmptyGraphic : true

    property var soundList: []
    property var availableSounds: {
        let names = [];
        for (let i = 0; i < soundList.length; i++) {
            names.push(soundList[i].name);
        }
        return names;
    }

    function updateNotifSetting(key, val) {
        let current = Config.getSetting("notifications", defaultNotificationSettings);
        current[key] = val;
        Config.setSetting("notifications", current);
        notificationsTabRoot.notifSettings = current;
    }

    function syncSettings() {
        let s = Config.getSetting("notifications", defaultNotificationSettings);
        notificationsTabRoot.dnd = s.dnd !== undefined ? s.dnd : false;
        notificationsTabRoot.position = s.position !== undefined ? s.position : "top right";
        notificationsTabRoot.soundEnabled = s.sound !== undefined ? s.sound : true;
        notificationsTabRoot.selectedSound = s.soundFile !== undefined ? s.soundFile : "";
        notificationsTabRoot.showEmptyGraphic = s.showEmptyGraphic !== undefined ? s.showEmptyGraphic : true;
        notificationsTabRoot.notifSettings = s;
    }

    function reloadSounds() {
        soundsLoader.running = false;
        soundsLoader.running = true;
    }

    Process {
        id: soundsLoader
        running: false
        command: {
            let assetsPath = Caching.serpantinumDir ? (Caching.serpantinumDir + "/assets/sounds/notifications") : (Caching.qsDir ? (Caching.qsDir + "/../assets/sounds/notifications") : "");
            let userPath = Caching.stateDir ? (Caching.stateDir + "/sounds/notifications") : (Caching.home + "/.local/state/serpantinum/sounds/notifications");
            let script =
                "mkdir -p \"" + userPath + "\"; " +
                "python3 -c '\n" +
                "import os, json, sys\n" +
                "assets = sys.argv[1]\n" +
                "user = sys.argv[2]\n" +
                "exts = (\".wav\", \".ogg\", \".mp3\", \".flac\", \".opus\", \".oga\", \".m4a\", \".aac\")\n" +
                "res = {}\n" +
                "for p in [assets, user]:\n" +
                "    if os.path.exists(p):\n" +
                "        for f in os.listdir(p):\n" +
                "            if f.lower().endswith(exts):\n" +
                "                name = os.path.splitext(f)[0]\n" +
                "                res[name] = os.path.join(p, f)\n" +
                "out = [{\"name\": k, \"path\": v} for k, v in sorted(res.items(), key=lambda x: x[0].lower())]\n" +
                "print(json.dumps(out))\n" +
                "' \"" + assetsPath + "\" \"" + userPath + "\"";
            return ["bash", "-c", script];
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let txt = this.text.trim();
                    if (txt !== "") {
                        let list = JSON.parse(txt);
                        if (Array.isArray(list)) {
                            notificationsTabRoot.soundList = list;
                            let found = false;
                            for (let i = 0; i < list.length; i++) {
                                if (list[i].path === notificationsTabRoot.selectedSound || list[i].name === notificationsTabRoot.selectedSound) {
                                    notificationsTabRoot.selectedSound = list[i].path;
                                    notificationsTabRoot.updateNotifSetting("soundFile", list[i].path);
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                if (list.length > 0) {
                                    notificationsTabRoot.selectedSound = list[0].path;
                                    notificationsTabRoot.updateNotifSetting("soundFile", list[0].path);
                                } else {
                                    notificationsTabRoot.selectedSound = "";
                                    notificationsTabRoot.updateNotifSetting("soundFile", "");
                                }
                            }
                        }
                    } else {
                        notificationsTabRoot.soundList = [];
                        notificationsTabRoot.selectedSound = "";
                        notificationsTabRoot.updateNotifSetting("soundFile", "");
                    }
                } catch (e) {}
            }
        }
    }

    function installSound(filePath, fileName) {
        if (!filePath || filePath.trim() === "" || !fileName || fileName.trim() === "") return;
        let userSoundsPath = Caching.stateDir ? (Caching.stateDir + "/sounds/notifications") : (Caching.home + "/.local/state/serpantinum/sounds/notifications");
        let escapeBash = function(str) { return String(str).replace(/(["\\$`])/g, '\\$1'); };

        let script =
            "D=\"" + escapeBash(userSoundsPath) + "\"; " +
            "B=\"" + escapeBash(fileName) + "\"; " +
            "S=\"" + escapeBash(filePath) + "\"; " +
            "mkdir -p \"$D\"; " +
            "if [ ! -f \"$D/$B\" ]; then cp \"$S\" \"$D/$B\"; fi; " +
            "NAME=$(basename \"$B\" | sed 's/\\.[^.]*$//'); " +
            "echo \"$NAME|$D/$B\";";

        soundInstallProcess.command = ["bash", "-c", script];
        soundInstallProcess.running = true;
    }

    Process {
        id: soundInstallProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                if (out !== "") {
                    let idx = out.indexOf('|');
                    let sPath = idx !== -1 ? out.substring(idx + 1).trim() : "";
                    if (sPath !== "") {
                        notificationsTabRoot.selectedSound = sPath;
                        notificationsTabRoot.updateNotifSetting("soundFile", sPath);
                        notificationsTabRoot.reloadSounds();
                        if (typeof Sounds !== "undefined" && typeof Sounds.play === "function") {
                            Sounds.play(sPath);
                        }
                    }
                }
                soundPickerPopup.close();
            }
        }
    }

    SoundPicker {
        id: soundPickerPopup
        rootObj: notificationsTabRoot.rootObj
        onSoundSelected: function(filePath, fileName) {
            if (filePath && filePath.trim() !== "" && fileName && fileName.trim() !== "") {
                notificationsTabRoot.installSound(filePath, fileName);
            }
        }
    }

    Component.onCompleted: {
        syncSettings();
        reloadSounds();
    }

    onVisibleChanged: {
        if (visible) {
            reloadSounds();
        } else {
            soundPickerPopup.close();
            if (posDropdown.isOpen) posDropdown.closePopup();
            if (soundDropdown.isOpen) soundDropdown.closePopup();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            syncSettings();
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: settingsCol.implicitHeight
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rowDndLayout.implicitHeight + rootObj.s(18)
                color: "transparent"

                RowLayout {
                    id: rowDndLayout
                    anchors.left: parent.left
                    anchors.leftMargin: rootObj.s(12)
                    anchors.right: parent.right
                    anchors.rightMargin: rootObj.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rootObj.s(16)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)
                        Text {
                            text: I18n.t("guide.notifications.dnd.title")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: I18n.t("guide.notifications.dnd.desc")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: notificationsTabRoot.dnd
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) {
                            notificationsTabRoot.dnd = c;
                            notificationsTabRoot.updateNotifSetting("dnd", c);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(ThemeBackend.surface1, 0.2)
                Layout.topMargin: rootObj.s(5)
                Layout.bottomMargin: rootObj.s(5)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rowGraphicLayout.implicitHeight + rootObj.s(18)
                color: "transparent"

                RowLayout {
                    id: rowGraphicLayout
                    anchors.left: parent.left
                    anchors.leftMargin: rootObj.s(12)
                    anchors.right: parent.right
                    anchors.rightMargin: rootObj.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rootObj.s(16)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)
                        Text {
                            text: I18n.t("guide.notifications.empty_graphic.title")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: I18n.t("guide.notifications.empty_graphic.desc")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: notificationsTabRoot.showEmptyGraphic
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) {
                            notificationsTabRoot.showEmptyGraphic = c;
                            notificationsTabRoot.updateNotifSetting("showEmptyGraphic", c);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(ThemeBackend.surface1, 0.2)
                Layout.topMargin: rootObj.s(5)
                Layout.bottomMargin: rootObj.s(5)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rowPosLayout.implicitHeight + rootObj.s(18)
                color: "transparent"

                RowLayout {
                    id: rowPosLayout
                    anchors.left: parent.left
                    anchors.leftMargin: rootObj.s(12)
                    anchors.right: parent.right
                    anchors.rightMargin: rootObj.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rootObj.s(16)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)
                        Text {
                            text: I18n.t("guide.notifications.position.title")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: I18n.t("guide.notifications.position.desc")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Dropdown {
                        id: posDropdown
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredWidth: rootObj.s(180)
                        Layout.preferredHeight: rootObj.s(32)
                        options: [
                            I18n.t("guide.notifications.position.top_right"),
                            I18n.t("guide.notifications.position.top_center"),
                            I18n.t("guide.notifications.position.top_left"),
                            I18n.t("guide.notifications.position.bottom_right"),
                            I18n.t("guide.notifications.position.bottom_center"),
                            I18n.t("guide.notifications.position.bottom_left")
                        ]
                        currentIndex: {
                            if (notificationsTabRoot.position === "top center") return 1;
                            if (notificationsTabRoot.position === "top left") return 2;
                            if (notificationsTabRoot.position === "bottom right") return 3;
                            if (notificationsTabRoot.position === "bottom center") return 4;
                            if (notificationsTabRoot.position === "bottom left") return 5;
                            return 0;
                        }
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface0
                        hoverColor: ThemeBackend.surface1
                        dropdownColor: ThemeBackend.surface0
                        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                        textColor: ThemeBackend.text
                        activeTextColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        fontPixelSize: rootObj.s(11)
                        onValueChanged: function(index, value) {
                            if (index === 0) notificationsTabRoot.position = "top right";
                            else if (index === 1) notificationsTabRoot.position = "top center";
                            else if (index === 2) notificationsTabRoot.position = "top left";
                            else if (index === 3) notificationsTabRoot.position = "bottom right";
                            else if (index === 4) notificationsTabRoot.position = "bottom center";
                            else if (index === 5) notificationsTabRoot.position = "bottom left";
                            notificationsTabRoot.updateNotifSetting("position", notificationsTabRoot.position);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(ThemeBackend.surface1, 0.2)
                Layout.topMargin: rootObj.s(5)
                Layout.bottomMargin: rootObj.s(5)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rowSoundToggleLayout.implicitHeight + rootObj.s(18)
                color: "transparent"

                RowLayout {
                    id: rowSoundToggleLayout
                    anchors.left: parent.left
                    anchors.leftMargin: rootObj.s(12)
                    anchors.right: parent.right
                    anchors.rightMargin: rootObj.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rootObj.s(16)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)
                        Text {
                            text: I18n.t("guide.notifications.sound.title")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: I18n.t("guide.notifications.sound.desc")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: notificationsTabRoot.soundEnabled
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) {
                            notificationsTabRoot.soundEnabled = c;
                            notificationsTabRoot.updateNotifSetting("sound", c);
                        }
                    }
                }
            }

            Item {
                id: soundSectionWrapper
                Layout.fillWidth: true
                property bool isOpen: notificationsTabRoot.soundEnabled
                clip: true
                visible: implicitHeight > 0
                opacity: isOpen ? 1.0 : 0.0
                implicitHeight: isOpen ? soundInnerCol.implicitHeight : 0

                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: soundInnerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.alpha(ThemeBackend.surface1, 0.2)
                        Layout.topMargin: rootObj.s(5)
                        Layout.bottomMargin: rootObj.s(5)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowSoundSelectLayout.implicitHeight + rootObj.s(18)
                        color: "transparent"

                        RowLayout {
                            id: rowSoundSelectLayout
                            anchors.left: parent.left
                            anchors.leftMargin: rootObj.s(12)
                            anchors.right: parent.right
                            anchors.rightMargin: rootObj.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: rootObj.s(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text {
                                    text: I18n.t("guide.notifications.sound_file.title")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(13)
                                    color: ThemeBackend.text
                                }
                                Text {
                                    text: I18n.t("guide.notifications.sound_file.desc")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.subtext0
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                spacing: rootObj.s(8)

                                IconButton {
                                    Layout.preferredWidth: rootObj.s(32)
                                    Layout.preferredHeight: rootObj.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    cornerRadius: rootObj.s(6)
	    			    buttonIcon: "󰉋"
				    iconOffsetX: -2
                                    iconFontSize: rootObj.s(14)
                                    accentColor: ThemeBackend.surface0
                                    textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                                    onClicked: {
                                        let userSoundsPath = Caching.stateDir ? (Caching.stateDir + "/sounds/notifications") : (Caching.home + "/.local/state/serpantinum/sounds/notifications");
                                        let escapeBash = function(str) { return String(str).replace(/(["\\$`])/g, '\\$1'); };
                                        Quickshell.execDetached(["bash", "-c", "mkdir -p \"" + escapeBash(userSoundsPath) + "\" && xdg-open \"" + escapeBash(userSoundsPath) + "\""]);
                                    }
                                }

                                IconButton {
                                    Layout.preferredWidth: rootObj.s(32)
                                    Layout.preferredHeight: rootObj.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    cornerRadius: rootObj.s(6)
                                    buttonIcon: "󰐕"
                                    iconFontSize: rootObj.s(14)
                                    accentColor: ThemeBackend.surface0
                                    textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                                    onClicked: soundPickerPopup.openPicker()
                                }

                                Dropdown {
                                    id: soundDropdown
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: rootObj.s(180)
                                    Layout.preferredHeight: rootObj.s(32)
                                    options: notificationsTabRoot.availableSounds
                                    currentIndex: {
                                        for (let i = 0; i < notificationsTabRoot.soundList.length; i++) {
                                            if (notificationsTabRoot.soundList[i].path === notificationsTabRoot.selectedSound) {
                                                return i;
                                            }
                                        }
                                        return 0;
                                    }
                                    accentColor: ThemeBackend.mauve
                                    baseColor: ThemeBackend.surface0
                                    hoverColor: ThemeBackend.surface1
                                    dropdownColor: ThemeBackend.surface0
                                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                    textColor: ThemeBackend.text
                                    activeTextColor: ThemeBackend.crust
                                    cornerRadius: ThemeBackend.borderRadius
                                    fontPixelSize: rootObj.s(11)
                                    onSelected: function(index, value) {
                                        if (index >= 0 && index < notificationsTabRoot.soundList.length) {
                                            let targetPath = notificationsTabRoot.soundList[index].path;
                                            notificationsTabRoot.selectedSound = targetPath;
                                            notificationsTabRoot.updateNotifSetting("soundFile", targetPath);
                                            if (typeof Sounds !== "undefined" && typeof Sounds.play === "function") {
                                                Sounds.play(targetPath);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
