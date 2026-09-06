import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import "../"

Popup {
    id: pickerRoot
    parent: {
        if (rootObj) {
            return rootObj.contentItem ? rootObj.contentItem : rootObj;
        }
        return Overlay.overlay ? Overlay.overlay : undefined;
    }
    x: parent && parent.width > 0 ? Math.max(0, Math.round((parent.width - width) / 2)) : 0
    y: parent && parent.height > 0 ? Math.max(0, Math.round((parent.height - height) / 2)) : 0
    modal: true
    dim: true
    z: 300000
    width: Scaler.s(960)
    height: Scaler.s(640)
    padding: Scaler.s(18)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    property var rootObj
    property var nameFilters: ["*"]
    property string titleText: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.title") : ""
    property var places: []
    property Component previewComponent: null
    property bool showPreview: false
    property real previewWidth: Scaler.s(360)

    property real crLarge: ThemeBackend.borderRadius
    property real crMedium: Math.max(0, ThemeBackend.borderRadius - 2)
    property real crSmall: Math.max(0, ThemeBackend.borderRadius - 4)

    property real toolbarHeight: Scaler.s(32)
    property real actionHeight: Scaler.s(42)

    signal fileSelected(string filePath, string fileName)

    property string selectedFilePath: ""
    property string selectedFileName: ""
    property string lastVisitedFolder: ""

    property int currentPlaceIndex: {
        let cur = folderModel.folder.toString();
        if (cur.endsWith("/")) cur = cur.slice(0, -1);
        for (let i = 0; i < pickerRoot.places.length; i++) {
            let p = pickerRoot.places[i].path.toString();
            if (p.endsWith("/")) p = p.slice(0, -1);
            if (cur === p) return i;
        }
        return -1;
    }

    Connections {
        target: pickerRoot.rootObj ? pickerRoot.rootObj : null
        function onVisibleChanged() {
            if (pickerRoot.rootObj && !pickerRoot.rootObj.visible) {
                pickerRoot.close();
            }
        }
    }

    Connections {
        target: pickerRoot.parent && pickerRoot.parent !== pickerRoot.rootObj ? pickerRoot.parent : null
        function onVisibleChanged() {
            if (pickerRoot.parent && !pickerRoot.parent.visible) {
                pickerRoot.close();
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: pickerRoot.opened
        onActivated: pickerRoot.close()
    }

    Shortcut {
        sequence: "Tab"
        enabled: pickerRoot.opened && pickerRoot.places && pickerRoot.places.length > 0
        onActivated: {
            let nextIdx = pickerRoot.currentPlaceIndex >= 0 ? (pickerRoot.currentPlaceIndex + 1) % pickerRoot.places.length : 0;
            pickerRoot.gotoFolder(pickerRoot.places[nextIdx].path);
        }
    }

    Shortcut {
        sequences: ["Backtab", "Shift+Tab"]
        enabled: pickerRoot.opened && pickerRoot.places && pickerRoot.places.length > 0
        onActivated: {
            let len = pickerRoot.places.length;
            let prevIdx = pickerRoot.currentPlaceIndex >= 0 ? (pickerRoot.currentPlaceIndex - 1 + len) % len : len - 1;
            pickerRoot.gotoFolder(pickerRoot.places[prevIdx].path);
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: pickerRoot.opened
        onActivated: {
            if (listView.activeFocus && listView.currentItem) {
                let obj = folderModel.get(listView.currentIndex, "fileIsDir");
                let fp = folderModel.get(listView.currentIndex, "filePath");
                let fn = folderModel.get(listView.currentIndex, "fileName");
                if (obj) {
                    pickerRoot.gotoFolder(fp);
                } else {
                    pickerRoot.selectedFilePath = pickerRoot.getAbsolutePath(fp);
                    try {
                        pickerRoot.selectedFileName = decodeURIComponent(fn);
                    } catch (e) {
                        pickerRoot.selectedFileName = fn;
                    }
                    pickerRoot.confirmSelection();
                }
            } else if (pickerRoot.selectedFilePath !== "") {
                pickerRoot.confirmSelection();
            }
        }
    }

    function confirmSelection() {
        if (pickerRoot.selectedFilePath !== "") {
            pickerRoot.fileSelected(pickerRoot.selectedFilePath, pickerRoot.selectedFileName);
            pickerRoot.close();
        }
    }

    function getAbsolutePath(pathStr) {
        if (!pathStr) return "";
        let str = pathStr.toString();
        if (str.startsWith("file://")) {
            str = str.substring(7);
        }
        try {
            return decodeURIComponent(str);
        } catch (e) {
            return str;
        }
    }

    function openWithOptionalPath(initialPath) {
        if (searchInput) {
            searchInput.clear();
        }

        let p = initialPath ? initialPath.toString() : "";
        if (p.startsWith("file://")) {
            p = p.substring(7);
        }
        try {
            p = decodeURIComponent(p);
        } catch (e) {}

        if (p !== "") {
            selectedFilePath = p;
            let parts = p.split("/");
            try {
                selectedFileName = decodeURIComponent(parts[parts.length - 1]);
            } catch (e) {
                selectedFileName = parts[parts.length - 1];
            }

            let dir = parts.slice(0, -1).join("/");
            if (dir !== "") {
                lastVisitedFolder = "file://" + dir;
            }
        } else {
            selectedFilePath = "";
            selectedFileName = "";
            if (lastVisitedFolder === "") {
                let home = Quickshell.env("HOME") || "";
                if (home !== "") {
                    lastVisitedFolder = "file://" + home;
                }
            }
        }

        folderModel.folder = lastVisitedFolder || "file:///";
        updateNameFilters();
        open();

        Qt.callLater(() => {
            if (breadcrumbFlickable.contentWidth > breadcrumbFlickable.width) {
                breadcrumbFlickable.contentX = breadcrumbFlickable.contentWidth - breadcrumbFlickable.width;
            }
        });
    }

    function gotoFolder(path) {
        let normalizedPath = path.toString();
        if (!normalizedPath.startsWith("file://")) {
            normalizedPath = "file://" + normalizedPath;
        }
        folderModel.folder = normalizedPath;
        lastVisitedFolder = normalizedPath;
        selectedFilePath = "";
        selectedFileName = "";
    }

    function updateNameFilters() {
        let st = searchInput.text ? searchInput.text.trim() : "";
        if (st.length > 0) {
            let filters = [];
            for (let i = 0; i < pickerRoot.nameFilters.length; i++) {
                filters.push("*" + st + "*" + pickerRoot.nameFilters[i].replace("*", ""));
            }
            filters.push("*" + st + "*");
            folderModel.nameFilters = filters;
        } else {
            folderModel.nameFilters = pickerRoot.nameFilters;
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 150
        repeat: false
        onTriggered: pickerRoot.updateNameFilters()
    }

    background: Rectangle {
        color: ThemeBackend.base
        radius: pickerRoot.crLarge
        border.color: ThemeBackend.surface0
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.4)
            shadowVerticalOffset: Scaler.s(4)
            shadowBlur: 0.5
        }
    }

    contentItem: ColumnLayout {
        spacing: Scaler.s(14)

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: pickerRoot.titleText
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(16)
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            IconButton {
                Layout.preferredWidth: pickerRoot.toolbarHeight
                Layout.preferredHeight: pickerRoot.toolbarHeight
                cornerRadius: pickerRoot.crSmall
                buttonIcon: "󰅖"
                iconFontSize: Scaler.s(14)
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.text
                onClicked: pickerRoot.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(14)

            Rectangle {
                Layout.preferredWidth: Scaler.s(180)
                Layout.fillHeight: true
                color: "transparent"
                visible: pickerRoot.places.length > 0

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Scaler.s(2)

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: pickerRoot.places.length * Scaler.s(34)

                        Rectangle {
                            id: activeHighlight
                            width: parent.width
                            height: Scaler.s(34)
                            radius: pickerRoot.crSmall
                            color: ThemeBackend.mauve
                            z: 0
                            visible: pickerRoot.currentPlaceIndex !== -1
                            opacity: pickerRoot.currentPlaceIndex !== -1 ? 1.0 : 0.0

                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }

                            property int curIdx: pickerRoot.currentPlaceIndex
                            property real targetY: curIdx >= 0 ? curIdx * Scaler.s(34) : 0
                            y: targetY

                            Behavior on y {
                                NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 0

                            Repeater {
                                model: pickerRoot.places

                                Rectangle {
                                    width: parent.width
                                    height: Scaler.s(34)
                                    radius: pickerRoot.crSmall
                                    z: 1

                                    property bool isActive: pickerRoot.currentPlaceIndex === index
                                    color: isActive ? "transparent" : (placeMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.5) : "transparent")

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    scale: placeMa.pressed ? 0.98 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Scaler.s(10) + (parent.isActive ? Scaler.s(2) : 0)
                                        anchors.rightMargin: Scaler.s(10)
                                        spacing: Scaler.s(8)

                                        Behavior on anchors.leftMargin {
                                            NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                                        }

                                        Item {
                                            Layout.preferredWidth: Scaler.s(20)
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.icon
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: Scaler.s(16)
                                                color: parent.parent.parent.isActive ? ThemeBackend.crust : (placeMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)

                                                Behavior on color {
                                                    ColorAnimation { duration: 150 }
                                                }
                                            }
                                        }

                                        Text {
                                            text: modelData.name
                                            font.family: ThemeBackend.fontFamily
                                            font.weight: parent.parent.isActive ? Font.Bold : Font.Medium
                                            font.pixelSize: Scaler.s(13)
                                            color: parent.parent.isActive ? ThemeBackend.crust : (placeMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            elide: Text.ElideRight

                                            Behavior on color {
                                                ColorAnimation { duration: 150 }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: placeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pickerRoot.gotoFolder(modelData.path)
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                spacing: Scaler.s(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Scaler.s(6)

                    IconButton {
                        Layout.preferredWidth: pickerRoot.toolbarHeight
                        Layout.preferredHeight: pickerRoot.toolbarHeight
                        Layout.minimumWidth: pickerRoot.toolbarHeight
                        Layout.maximumWidth: pickerRoot.toolbarHeight
                        cornerRadius: pickerRoot.crSmall
                        buttonIcon: "󰁍"
                        iconFontSize: Scaler.s(16)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        enabled: folderModel.folder.toString() !== "file:///"
                        onClicked: {
                            folderModel.folder = folderModel.parentFolder;
                            pickerRoot.lastVisitedFolder = folderModel.parentFolder.toString();
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: Scaler.s(50)
                        Layout.preferredHeight: pickerRoot.toolbarHeight
                        radius: pickerRoot.crSmall
                        color: ThemeBackend.surface0
                        clip: true

                        Flickable {
                            id: breadcrumbFlickable
                            anchors.fill: parent
                            contentWidth: breadcrumbRow.width
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            onContentWidthChanged: {
                                Qt.callLater(() => {
                                    if (breadcrumbFlickable.contentWidth > breadcrumbFlickable.width) {
                                        breadcrumbFlickable.contentX = breadcrumbFlickable.contentWidth - breadcrumbFlickable.width;
                                    } else {
                                        breadcrumbFlickable.contentX = 0;
                                    }
                                });
                            }

                            Row {
                                id: breadcrumbRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Scaler.s(2)
                                leftPadding: Scaler.s(6)
                                rightPadding: Scaler.s(6)

                                Repeater {
                                    id: breadcrumbRepeater
                                    model: {
                                        let rawPath = folderModel.folder.toString().replace("file://", "");
                                        try {
                                            rawPath = decodeURIComponent(rawPath);
                                        } catch (e) {}
                                        let parts = rawPath.split("/").filter(p => p !== "");
                                        let rootName = typeof I18n !== "undefined" ? I18n.t("guide.file_picker.root") : "Root";
                                        let arr = [{ name: rootName, path: "file:///" }];
                                        let cp = "file://";
                                        for (let i = 0; i < parts.length; i++) {
                                            cp += "/" + parts[i];
                                            arr.push({ name: parts[i], path: cp });
                                        }
                                        return arr;
                                    }

                                    delegate: Row {
                                        spacing: Scaler.s(2)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: "󰅂"
                                            color: ThemeBackend.surface2
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: Scaler.s(14)
                                            visible: index > 0
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Rectangle {
                                            property bool isCurrent: index === breadcrumbRepeater.count - 1
                                            height: pickerRoot.toolbarHeight - Scaler.s(6)
                                            width: bcTxt.implicitWidth + Scaler.s(14)
                                            radius: Scaler.s(6)
                                            color: isCurrent ? ThemeBackend.surface1 : (bcMa.containsMouse ? ThemeBackend.surface0 : "transparent")
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                id: bcTxt
                                                anchors.centerIn: parent
                                                text: modelData.name
                                                font.family: ThemeBackend.fontFamily
                                                color: parent.isCurrent ? ThemeBackend.mauve : (bcMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                                                font.pixelSize: Scaler.s(12)
                                            }

                                            MouseArea {
                                                id: bcMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: pickerRoot.gotoFolder(modelData.path)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Scaler.s(84)
                        Layout.preferredHeight: pickerRoot.toolbarHeight
                        Layout.minimumWidth: Scaler.s(84)
                        Layout.maximumWidth: Scaler.s(84)
                        radius: pickerRoot.crSmall
                        color: ThemeBackend.surface0
                        clip: true

                        Toggle {
                            id: hiddenToggle
                            anchors.fill: parent
                            buttonText: ""
                            buttonIcon: "󰈈"
                            iconFontSize: Scaler.s(16)
                            accentColor: ThemeBackend.mauve
                            baseColor: "transparent"
                            cornerRadius: pickerRoot.crSmall
                            textColor: ThemeBackend.text
                            checked: folderModel.showHidden
                            onToggled: function(chk) {
                                folderModel.showHidden = chk;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Scaler.s(6)

                    Input {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: pickerRoot.toolbarHeight
                        leadingIcon: "󰍉"
                        showClearButton: true
                        placeholderText: {
                            let raw = typeof I18n !== "undefined" ? I18n.t("guide.file_picker.input_placeholder") : "Search...";
                            let cleaned = raw.replace(/^[\uE000-\uF8FF\s]+/g, "").trim();
                            return cleaned !== "" ? cleaned : "Search...";
                        }
                        baseColor: ThemeBackend.surface0
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.text
                        subTextColor: ThemeBackend.subtext0
                        borderColor: "transparent"
                        cornerRadius: pickerRoot.crSmall
                        horizontalPadding: Scaler.s(10)
                        verticalPadding: Scaler.s(4)
                        fontPixelSize: Scaler.s(12)
                        onTextEdited: function(txt) {
                            searchDebounceTimer.restart();
                        }
                        onCleared: {
                            searchDebounceTimer.restart();
                        }
                        onAccepted: pickerRoot.confirmSelection()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    color: ThemeBackend.surface0
                    radius: pickerRoot.crMedium
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        text: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.not_found") : "No files found"
                        color: ThemeBackend.subtext0
                        font.pixelSize: Scaler.s(14)
                        font.family: ThemeBackend.fontFamily
                        visible: folderModel.count === 0
                    }

                    ListView {
                        id: listView
                        anchors.fill: parent
                        anchors.margins: Scaler.s(2)
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        spacing: Scaler.s(0)
                        focus: true

                        model: FolderListModel {
                            id: folderModel
                            showDirsFirst: true
                            showDotAndDotDot: false
                            showFiles: true
                            showDirs: true
                            showHidden: false
                            caseSensitive: false
                            sortField: FolderListModel.Name
                            nameFilters: pickerRoot.nameFilters
                        }

                        delegate: Rectangle {
                            id: delegateItem
                            property string searchText: searchInput.text ? searchInput.text.toLowerCase().trim() : ""
                            property bool matchesSearch: searchText === "" || fileName.toLowerCase().indexOf(searchText) !== -1

                            width: listView.width
                            height: matchesSearch ? Scaler.s(32) : 0
                            visible: matchesSearch
                            radius: pickerRoot.crSmall
                            color: (pickerRoot.selectedFilePath === pickerRoot.getAbsolutePath(filePath)) ? Qt.alpha(ThemeBackend.mauve, 0.15) : (delegateMa.containsMouse ? ThemeBackend.surface1 : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Scaler.s(8)
                                anchors.rightMargin: Scaler.s(8)
                                spacing: Scaler.s(6)

                                Text {
                                    text: fileIsDir ? "󰉋" : "󰋩"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: Scaler.s(16)
                                    color: fileIsDir ? ThemeBackend.blue : ThemeBackend.text
                                }

                                Text {
                                    text: {
                                        try {
                                            return decodeURIComponent(fileName);
                                        } catch (e) {
                                            return fileName;
                                        }
                                    }
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(13)
                                    color: ThemeBackend.text
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: delegateMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    listView.forceActiveFocus();
                                    listView.currentIndex = index;
                                    if (fileIsDir) {
                                        pickerRoot.gotoFolder(filePath);
                                    } else {
                                        pickerRoot.selectedFilePath = pickerRoot.getAbsolutePath(filePath);
                                        try {
                                            pickerRoot.selectedFileName = decodeURIComponent(fileName);
                                        } catch (e) {
                                            pickerRoot.selectedFileName = fileName;
                                        }
                                    }
                                }
                                onDoubleClicked: {
                                    if (fileIsDir) {
                                        pickerRoot.gotoFolder(filePath);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                Layout.preferredWidth: pickerRoot.previewWidth
                Layout.fillHeight: true
                sourceComponent: pickerRoot.previewComponent
                visible: pickerRoot.showPreview
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(14)

            Text {
                Layout.fillWidth: true
                text: {
                    if (pickerRoot.selectedFileName !== "") {
                        try {
                            return decodeURIComponent(pickerRoot.selectedFileName);
                        } catch (e) {
                            return pickerRoot.selectedFileName;
                        }
                    }
                    return typeof I18n !== "undefined" ? I18n.t("guide.file_picker.no_file_selected") : "No file selected";
                }
                color: pickerRoot.selectedFileName !== "" ? ThemeBackend.text : ThemeBackend.subtext0
                font.pixelSize: Scaler.s(14)
                font.family: ThemeBackend.fontFamily
                elide: Text.ElideRight
            }

            RowLayout {
                spacing: Scaler.s(6)

                IconButton {
                    Layout.preferredWidth: pickerRoot.actionHeight
                    Layout.preferredHeight: pickerRoot.actionHeight
                    cornerRadius: pickerRoot.crMedium
                    buttonIcon: "󰅖"
                    iconFontSize: Scaler.s(18)
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.text
                    onClicked: {
                        pickerRoot.fileSelected("", "");
                        pickerRoot.close();
                    }
                }

                IconButton {
                    Layout.preferredWidth: pickerRoot.actionHeight
                    Layout.preferredHeight: pickerRoot.actionHeight
                    cornerRadius: pickerRoot.crMedium
                    buttonIcon: "󰄬"
                    iconFontSize: Scaler.s(18)
                    accentColor: pickerRoot.selectedFilePath !== "" ? ThemeBackend.mauve : ThemeBackend.surface0
                    textColor: pickerRoot.selectedFilePath !== "" ? ThemeBackend.crust : ThemeBackend.subtext0
                    enabled: pickerRoot.selectedFilePath !== ""
                    onClicked: pickerRoot.confirmSelection()
                }
            }
        }
    }
}
