import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: root
    focus: true

    property int activationCounter: 0
    property var appPaths: Caching
    property int currentTab: 0
    property int currentSubTab: 0
    property int expandedTab: -1

    property real colorBlend: 0.0
    property color ambientPurple: Qt.tint(ThemeBackend.mauve, Qt.rgba(ThemeBackend.pink.r, ThemeBackend.pink.g, ThemeBackend.pink.b, colorBlend))
    property color ambientBlue: Qt.tint(ThemeBackend.blue, Qt.rgba(ThemeBackend.sapphire.r, ThemeBackend.sapphire.g, ThemeBackend.sapphire.b, colorBlend))
    property int chargingSoundHandle: -1

    property real introBase: 0.0
    property real introSidebar: 0.0
    property real introContent: 0.0
    property var tutorialSections: []

    property var tabsModel: [
        { id: "Welcome", key: "welcome", name: "Welcome", icon: "󰋜", file: "WelcomeTab.qml" },
        { id: "General", key: "general", name: "General", icon: "󰒓", file: "general/GeneralTab.qml" },
        { 
            id: "Display", 
            key: "display", 
            name: "Display", 
            icon: "󰃠", 
            file: "display/DisplayMainTab.qml",
            subtabs: [
                { id: "DisplayGeneral", key: "display_general", name: "Display", icon: "󰃠", file: "display/DisplayMainTab.qml" },
                { id: "DisplayWidgets", key: "display_widgets", name: "Widgets", icon: "󰕰", file: "display/DisplayWidgetsTab.qml" }
            ]
        },
        { id: "Bar", key: "bar", name: "Bar", icon: "󰹑", file: "BarTab.qml" },
        { id: "Launcher", key: "launcher", name: "Launcher", icon: "󰵆", file: "LauncherTab.qml" },
        { id: "Theme", key: "theme", name: "Theme", icon: "✦", file: "theme/ThemeTab.qml" },
        { id: "Notifications", key: "notifications", name: "Notifications", icon: "󰂚", file: "notifications/NotificationsTab.qml" },
        { id: "Idle", key: "idle", name: "Idle", icon: "󰒲", file: "IdleTab.qml" },
        { id: "Vpn", key: "vpn", name: "VPN", icon: "󰦝", file: "VpnTab.qml" },
        { id: "Wellbeing", key: "wellbeing", name: "Wellbeing", icon: "󰄉", file: "wellbeing/DigitalWellbeingTab.qml" },
        { id: "About", key: "about", name: "About", icon: "", file: "AboutTab.qml" }
    ]

    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active) {
            activationCounter++;
        }
    }

    function closePopup() { closeSequence.start() }

    function s(val) {
        return Scaler.s(val);
    }

    function gotoTab(tabName, subTabName) {
        if (tabName === undefined || tabName === null || tabName === "") return;
        let num = parseInt(tabName);
        if (!isNaN(num) && num >= 0 && num < tabsModel.length) {
            currentTab = num;
            expandedTab = (tabsModel[num].subtabs && tabsModel[num].subtabs.length > 0) ? num : -1;
            if (subTabName !== undefined && subTabName !== null && subTabName !== "") {
                let sNum = parseInt(subTabName);
                currentSubTab = !isNaN(sNum) ? sNum : 0;
            } else {
                currentSubTab = 0;
            }
            return;
        }
        let lower = String(tabName).toLowerCase();
        for (let i = 0; i < tabsModel.length; i++) {
            let t = tabsModel[i];
            if ((t.id && t.id.toLowerCase() === lower) || 
                (t.name && t.name.toLowerCase() === lower) || 
                (t.key && t.key.toLowerCase() === lower)) {
                currentTab = i;
                expandedTab = (t.subtabs && t.subtabs.length > 0) ? i : -1;
                if (subTabName !== undefined && subTabName !== null && subTabName !== "") {
                    let sLower = String(subTabName).toLowerCase();
                    let sNum = parseInt(subTabName);
                    if (!isNaN(sNum) && t.subtabs && sNum >= 0 && sNum < t.subtabs.length) {
                        currentSubTab = sNum;
                    } else if (t.subtabs) {
                        let sIdx = t.subtabs.findIndex(st => 
                            (st.id && st.id.toLowerCase() === sLower) || 
                            (st.name && st.name.toLowerCase() === sLower) || 
                            (st.key && st.key.toLowerCase() === sLower)
                        );
                        currentSubTab = sIdx !== -1 ? sIdx : 0;
                    } else {
                        currentSubTab = 0;
                    }
                } else {
                    currentSubTab = 0;
                }
                return;
            }

            if (t.subtabs && Array.isArray(t.subtabs)) {
                let sIdx = t.subtabs.findIndex(st => 
                    (st.id && st.id.toLowerCase() === lower) || 
                    (st.name && st.name.toLowerCase() === lower) || 
                    (st.key && st.key.toLowerCase() === lower)
                );
                if (sIdx !== -1) {
                    currentTab = i;
                    expandedTab = i;
                    currentSubTab = sIdx;
                    return;
                }
            }
        }
    }

    function resetAndPlayIntro() {
        introBase = 0.0;
        introSidebar = 0.0;
        introContent = 0.0;
        startupSequence.restart();
        Updater.checkUpdate();
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: root.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
        } else {
            startupSequence.stop();
            closeSequence.stop();
            introBase = 0.0;
            introSidebar = 0.0;
            introContent = 0.0;
            if (root.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                Sounds.stopSfx(root.chargingSoundHandle);
                root.chargingSoundHandle = -1;
            }
        }
    }

    Component.onCompleted: {
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            resetAndPlayIntro();
        }
    }

    function nextTab() {
        let parentTab = tabsModel[currentTab];
        if (parentTab && parentTab.subtabs && parentTab.subtabs.length > 0 && expandedTab === currentTab) {
            if (currentSubTab < parentTab.subtabs.length - 1) {
                currentSubTab++;
                return;
            }
        }
        currentTab = (currentTab + 1) % tabsModel.length;
        let nextParent = tabsModel[currentTab];
        if (nextParent && nextParent.subtabs && nextParent.subtabs.length > 0) {
            expandedTab = currentTab;
            currentSubTab = 0;
        } else {
            expandedTab = -1;
            currentSubTab = 0;
        }
    }

    function prevTab() {
        let parentTab = tabsModel[currentTab];
        if (parentTab && parentTab.subtabs && parentTab.subtabs.length > 0 && expandedTab === currentTab) {
            if (currentSubTab > 0) {
                currentSubTab--;
                return;
            }
        }
        currentTab = (currentTab - 1 + tabsModel.length) % tabsModel.length;
        let prevParent = tabsModel[currentTab];
        if (prevParent && prevParent.subtabs && prevParent.subtabs.length > 0) {
            expandedTab = currentTab;
            currentSubTab = prevParent.subtabs.length - 1;
        } else {
            expandedTab = -1;
            currentSubTab = 0;
        }
    }

    Keys.onEscapePressed: (event) => {
        closeSequence.start();
        event.accepted = true;
    }
    Keys.onTabPressed: (event) => {
        nextTab();
        event.accepted = true;
    }
    Keys.onBacktabPressed: (event) => {
        prevTab();
        event.accepted = true;
    }

    SequentialAnimation on colorBlend {
        loops: Animation.Infinite
        running: root.visible
        NumberAnimation { to: 1.0; duration: 15000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 15000; easing.type: Easing.InOutSine }
    }

    function saveLastTab() {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentTab + ":" + currentSubTab + "' > '" + Caching.getCacheDir("guide") + "/last_tab.txt'"]);
    }

    onCurrentTabChanged: saveLastTab()
    onCurrentSubTabChanged: saveLastTab()

    FileView {
        id: lastTabWatcher
        path: Caching.getCacheDir("guide") + "/last_tab.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                let val = text().trim();
                if (val !== "") {
                    if (val.indexOf(":") !== -1) {
                        let parts = val.split(":");
                        root.gotoTab(parts[0], parts[1]);
                    } else {
                        root.gotoTab(val);
                    }
                }
            } catch(e) {}
        }
    }

    FileView {
        id: tutorialWatcher
        path: Caching.serpantinumDir ? (Caching.serpantinumDir + "/assets/tutorial.json") : ""
        onLoaded: {
            try {
                let data = JSON.parse(text().trim());
                if (Array.isArray(data)) {
                    root.tutorialSections = data;
                }
            } catch(e) {}
        }
    }

    ParallelAnimation {
        id: startupSequence
        running: false
        NumberAnimation {
            target: root
            property: "introBase"
            from: 0.0
            to: 1.0
            duration: 900
            easing.type: Easing.OutExpo
        }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation {
                target: root
                property: "introSidebar"
                from: 0.0
                to: 1.0
                duration: 1800
                easing.type: Easing.OutBack
                easing.overshoot: 1.05
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation {
                target: root
                property: "introContent"
                from: 0.0
                to: 1.0
                duration: 1100
                easing.type: Easing.OutBack
                easing.overshoot: 1.02
            }
        }
    }

    SequentialAnimation {
        id: closeSequence
        ScriptAction {
            script: {
                if (root.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                    Sounds.stopSfx(root.chargingSoundHandle);
                    root.chargingSoundHandle = -1;
                }
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "introContent"
                to: 0.0
                duration: 150
                easing.type: Easing.InExpo
            }
            NumberAnimation {
                target: root
                property: "introSidebar"
                to: 0.0
                duration: 150
                easing.type: Easing.InExpo
            }
        }
        NumberAnimation {
            target: root
            property: "introBase"
            to: 0.0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction {
            script: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"])
        }
    }

    Item {
        anchors.fill: parent
        opacity: introBase
        scale: 0.95 + (0.05 * introBase)

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.clampedBorderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface0

            property real time: 0
            NumberAnimation on time {
                from: 0
                to: Math.PI * 2
                duration: 20000
                loops: Animation.Infinite
                running: root.visible
            }

            Rectangle {
                id: sidebar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.s(260)
                
                topLeftRadius: ThemeBackend.clampedBorderRadius
                bottomLeftRadius: ThemeBackend.clampedBorderRadius
                topRightRadius: 8
                bottomRightRadius: 8
                
                color: Qt.alpha(ThemeBackend.surface0, 0.4)
                border.color: ThemeBackend.surface1
                border.width: 1
                opacity: introSidebar
                transform: Translate { x: root.s(-30) * (1.0 - introSidebar) }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(15)
                    spacing: root.s(10)

                    Flickable {
                        id: tabsFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: tabsCol.implicitHeight + root.s(20)
                        contentWidth: width
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            active: tabsFlickable.moving || tabsFlickable.movingVertically
                            width: root.s(4)
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: root.s(4)
                                radius: root.s(2)
                                color: ThemeBackend.surface2
                            }
                        }

                        Rectangle {
                            id: activeHighlight
                            z: 0
                            radius: ThemeBackend.borderRadius
                            color: ThemeBackend.mauve

                            property var activeGroupItem: tabsRepeater.count > root.currentTab ? tabsRepeater.itemAt(root.currentTab) : null
                            property bool isSubActive: {
                                let curData = root.tabsModel[root.currentTab];
                                return Boolean(curData && curData.subtabs && curData.subtabs.length > 0 && root.expandedTab === root.currentTab);
                            }

                            property real targetX: isSubActive ? root.s(26) : 0
                            property real targetY: {
                                let baseY = activeGroupItem ? activeGroupItem.y : (root.currentTab * (root.s(44) + root.s(4)));
                                if (isSubActive) {
                                    return baseY + root.s(44) + root.s(4) + root.currentSubTab * (root.s(36) + root.s(4));
                                }
                                return baseY;
                            }
                            property real targetW: isSubActive ? (tabsCol.width - root.s(26)) : tabsCol.width
                            property real targetH: isSubActive ? root.s(36) : root.s(44)

                            x: targetX
                            y: targetY
                            width: targetW
                            height: targetH

                            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        }

                        ColumnLayout {
                            id: tabsCol
                            width: tabsFlickable.width - (tabsFlickable.contentHeight > tabsFlickable.height ? root.s(6) : 0)
                            spacing: root.s(4)

                            Repeater {
                                id: tabsRepeater
                                model: root.tabsModel

                                delegate: ColumnLayout {
                                    id: tabGroupItem
                                    Layout.fillWidth: true
                                    spacing: 0

                                    property int tabIndex: index
                                    property var tabData: modelData
                                    property bool hasSubtabs: Boolean(tabData.subtabs && tabData.subtabs.length > 0)
                                    property bool isCurrentTab: root.currentTab === tabIndex
                                    property bool isExpanded: hasSubtabs && (root.expandedTab === tabIndex)

                                    property real fullSubtabsHeight: hasSubtabs ? (tabData.subtabs.length * root.s(36) + (tabData.subtabs.length - 1) * root.s(4) + root.s(8)) : 0

                                    property real expandProgress: isExpanded ? 1.0 : 0.0
                                    Behavior on expandProgress {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }

                                    Rectangle {
                                        id: tabHeaderItem
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(44)
                                        implicitHeight: root.s(44)
                                        radius: ThemeBackend.borderRadius
                                        z: 1

                                        property bool isDirectActive: (tabGroupItem.isCurrentTab && (!tabGroupItem.hasSubtabs || !tabGroupItem.isExpanded))

                                        color: tabHeaderMa.containsMouse && !isDirectActive ? Qt.alpha(ThemeBackend.surface1, 0.5) : "transparent"

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        
                                        scale: tabHeaderMa.pressed ? 0.98 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: root.s(15) + (tabHeaderItem.isDirectActive ? root.s(6) : 0)
                                            anchors.rightMargin: root.s(15)
                                            spacing: root.s(10)

                                            Behavior on anchors.leftMargin { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                                            Item {
                                                Layout.preferredWidth: root.s(24)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: tabData.icon
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: root.s(18)
                                                    color: tabHeaderItem.isDirectActive 
                                                        ? ThemeBackend.crust 
                                                        : (tabHeaderMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }

                                            Text {
                                                text: I18n.t("guide.tabs." + tabData.key, tabData.name || "")
                                                font.family: ThemeBackend.fontFamily
                                                font.weight: tabHeaderItem.isDirectActive ? Font.Bold : Font.Medium
                                                font.pixelSize: root.s(13)
                                                color: tabHeaderItem.isDirectActive 
                                                    ? ThemeBackend.crust 
                                                    : (tabHeaderMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                elide: Text.ElideRight
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            Text {
                                                visible: tabGroupItem.hasSubtabs
                                                text: "󰅀"
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: root.s(14)
                                                color: tabHeaderItem.isDirectActive 
                                                    ? ThemeBackend.crust 
                                                    : (tabHeaderMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                                Layout.alignment: Qt.AlignVCenter
                                                rotation: tabGroupItem.expandProgress * 180 - 180
                                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                        }

                                        MouseArea {
                                            id: tabHeaderMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (tabGroupItem.hasSubtabs) {
                                                    if (root.expandedTab === tabIndex) {
                                                        root.expandedTab = -1;
                                                    } else {
                                                        root.expandedTab = tabIndex;
                                                        if (root.currentTab !== tabIndex) {
                                                            root.currentTab = tabIndex;
                                                            root.currentSubTab = 0;
                                                        }
                                                    }
                                                } else {
                                                    root.expandedTab = -1;
                                                    root.currentTab = tabIndex;
                                                    root.currentSubTab = 0;
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        id: subtabsWrapper
                                        visible: tabGroupItem.hasSubtabs && tabGroupItem.expandProgress > 0.001
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: tabGroupItem.fullSubtabsHeight * tabGroupItem.expandProgress
                                        implicitHeight: tabGroupItem.fullSubtabsHeight * tabGroupItem.expandProgress
                                        opacity: Math.max(0.0, (tabGroupItem.expandProgress - 0.15) / 0.85)
                                        clip: true

                                        RowLayout {
                                            id: subtabsRowLayout
                                            anchors.fill: parent
                                            anchors.topMargin: root.s(4)
                                            anchors.bottomMargin: root.s(4)
                                            spacing: root.s(6)

                                            Item {
                                                Layout.preferredWidth: root.s(20)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.topMargin: root.s(2)
                                                    anchors.bottomMargin: root.s(2)
                                                    width: Math.max(1, root.s(2))
                                                    radius: root.s(1)
                                                    color: Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.7)
                                                }
                                            }

                                            ColumnLayout {
                                                id: subtabsCol
                                                Layout.fillWidth: true
                                                spacing: root.s(4)

                                                Repeater {
                                                    model: tabGroupItem.hasSubtabs ? tabData.subtabs : []

                                                    delegate: Rectangle {
                                                        id: subtabItem
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: root.s(36)
                                                        implicitHeight: root.s(36)
                                                        radius: ThemeBackend.borderRadius
                                                        z: 1

                                                        property int subIndex: index
                                                        property var subData: modelData
                                                        property bool isSubActive: (tabGroupItem.isCurrentTab && tabGroupItem.isExpanded && root.currentSubTab === subIndex)

                                                        color: (subtabMa.containsMouse && !isSubActive ? Qt.alpha(ThemeBackend.surface1, 0.5) : "transparent")

                                                        Behavior on color { ColorAnimation { duration: 150 } }

                                                        scale: subtabMa.pressed ? 0.98 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: root.s(10) + (subtabItem.isSubActive ? root.s(4) : 0)
                                                            anchors.rightMargin: root.s(10)
                                                            spacing: root.s(8)

                                                            Behavior on anchors.leftMargin { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                                                            Item {
                                                                Layout.preferredWidth: root.s(20)
                                                                Layout.alignment: Qt.AlignVCenter
                                                                visible: Boolean(subData.icon && subData.icon !== "")

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: subData.icon || ""
                                                                    font.family: ThemeBackend.fontFamily
                                                                    font.pixelSize: root.s(15)
                                                                    color: subtabItem.isSubActive ? ThemeBackend.crust : ThemeBackend.subtext0
                                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                                }
                                                            }

                                                            Text {
                                                                text: subData.key ? I18n.t("guide.tabs." + subData.key, subData.name || "") : (subData.name || "")
                                                                font.family: ThemeBackend.fontFamily
                                                                font.weight: subtabItem.isSubActive ? Font.Bold : Font.Medium
                                                                font.pixelSize: root.s(12)
                                                                color: subtabItem.isSubActive ? ThemeBackend.crust : ThemeBackend.subtext0
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                                elide: Text.ElideRight
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: subtabMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                root.currentTab = tabGroupItem.tabIndex;
                                                                root.expandedTab = tabGroupItem.tabIndex;
                                                                root.currentSubTab = subIndex;
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

                    ClickButton {
                        visible: Updater.updateAvailable
                        Layout.fillWidth: true
                        implicitHeight: root.s(38)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: I18n.t("guide.update_available")
                        buttonIcon: "󰚰"
                        iconFontSize: root.s(16)
                        textFontSize: root.s(13)
                        accentColor: ThemeBackend.green
                        textColor: ThemeBackend.crust
                        onClicked: {
                            root.gotoTab("about");
                        }
                    }
                }
            }

            Item {
                id: contentArea
                anchors.left: sidebar.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: root.s(10)

                opacity: introContent
                scale: 0.95 + (0.05 * introContent)
                transform: Translate { y: root.s(20) * (1.0 - introContent) }

                Repeater {
                    id: contentRepeater
                    model: root.tabsModel
                    delegate: Item {
                        id: tabContentWrapper
                        anchors.fill: parent
                        visible: root.currentTab === parentTabIndex

                        property int parentTabIndex: index
                        property var tabData: modelData
                        property bool hasSubtabs: Boolean(tabData.subtabs && tabData.subtabs.length > 0)

                        Loader {
                            id: singleTabLoader
                            anchors.fill: parent
                            asynchronous: false
                            active: !tabContentWrapper.hasSubtabs
                            visible: !tabContentWrapper.hasSubtabs && root.currentTab === tabContentWrapper.parentTabIndex

                            function ensureLoaded() {
                                if (status === Loader.Null && tabData.file) {
                                    setSource(tabData.file, {
                                        "rootObj": root,
                                        "tabIndex": tabContentWrapper.parentTabIndex
                                    });
                                }
                            }

                            Component.onCompleted: {
                                if (root.currentTab === tabContentWrapper.parentTabIndex && !tabContentWrapper.hasSubtabs) ensureLoaded();
                            }

                            Connections {
                                target: root
                                function onCurrentTabChanged() {
                                    if (root.currentTab === tabContentWrapper.parentTabIndex && !tabContentWrapper.hasSubtabs) singleTabLoader.ensureLoaded();
                                }
                            }
                        }

                        Repeater {
                            model: tabContentWrapper.hasSubtabs ? tabData.subtabs : []

                            delegate: Loader {
                                id: subTabLoader
                                anchors.fill: parent
                                asynchronous: false
                                property int subIndex: index
                                property var subData: modelData
                                visible: root.currentTab === tabContentWrapper.parentTabIndex && root.currentSubTab === subIndex

                                function ensureLoaded() {
                                    if (status === Loader.Null && subData.file) {
                                        setSource(subData.file, {
                                            "rootObj": root,
                                            "tabIndex": tabContentWrapper.parentTabIndex,
                                            "subTabIndex": subIndex
                                        });
                                    }
                                }

                                Component.onCompleted: {
                                    if (root.currentTab === tabContentWrapper.parentTabIndex && root.currentSubTab === subIndex) ensureLoaded();
                                }

                                Connections {
                                    target: root
                                    function onCurrentTabChanged() {
                                        if (root.currentTab === tabContentWrapper.parentTabIndex && root.currentSubTab === subIndex) subTabLoader.ensureLoaded();
                                    }
                                    function onCurrentSubTabChanged() {
                                        if (root.currentTab === tabContentWrapper.parentTabIndex && root.currentSubTab === subIndex) subTabLoader.ensureLoaded();
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
