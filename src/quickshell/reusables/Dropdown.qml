import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    implicitWidth: 160
    implicitHeight: 32

    property var options: []
    property int currentIndex: 0
    readonly property string currentValue: currentIndex >= 0 && currentIndex < options.length ? options[currentIndex] : ""
    property string placeholderText: "Select..."
    property string fontFamily: "JetBrains Mono"
    property bool useOptionAsFontFamily: false

    property bool fuzzySearch: true
    property bool isPathSelector: false

    property color accentColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.mauve) ? ThemeBackend.mauve : "#89b4fa"
    property color baseColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.surface0) ? ThemeBackend.surface0 : "#313244"
    property color hoverColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.surface1) ? ThemeBackend.surface1 : Qt.lighter(baseColor, 1.2)
    property color dropdownColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.surface0) ? ThemeBackend.surface0 : "#1e1e2e"
    property color borderColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.surface1) ? ThemeBackend.surface1 : "#45475a"
    property color textColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.text) ? ThemeBackend.text : "#cdd6f4"
    property color activeTextColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.crust) ? ThemeBackend.crust : "#11111b"
    property color subTextColor: (typeof ThemeBackend !== "undefined" && ThemeBackend.subtext0) ? ThemeBackend.subtext0 : "#a6adc8"

    property real cornerRadius: ThemeBackend.clampedBorderRadius
    property int fontPixelSize: 11
    property int iconSize: 16
    property int charSpacing: 1
    property real horizontalPadding: 12

    property bool enabled: true
    property bool action_highlight: false
    property string clickSound: "reusables/dropdown/click.wav"
    property string listSound: "reusables/dropdown/list.wav"
    property string keySound: "reusables/input/type.wav"

    property var filteredOptions: options
    property bool isEditing: false
    property string searchText: ""

    property real flashOpacity: 0.0
    property real popScale: 1.0
    property bool isOpen: false
    property int visibleCount: 0

    property bool isHoveredOrHighlighted: (btnMa.containsMouse || root.action_highlight) && root.enabled
    readonly property real charSlotStep: globalCharMetrics.width + root.charSpacing
    property real scrollOffset: 0

    signal valueChanged(int index, string value)
    signal selected(int index, string value)
    signal clicked()
    signal opened()
    signal closed()
    signal searchChanged(string text)

    function fuzzyScore(query, text) {
        let q = String(query).toLowerCase();
        let t = String(text).toLowerCase();
        let qLen = q.length;
        let tLen = t.length;
        if (qLen === 0) return 1;
        if (qLen > tLen) return -1;
        let qIdx = 0;
        let score = 0;
        let consecutive = 0;
        let prevMatchedIdx = -1;

        for (let tIdx = 0; tIdx < tLen && qIdx < qLen; tIdx++) {
            if (t[tIdx] === q[qIdx]) {
                score += 10;
                if (prevMatchedIdx === tIdx - 1) {
                    consecutive++;
                    score += consecutive * 5;
                } else {
                    consecutive = 0;
                }
                if (tIdx === 0 || t[tIdx - 1] === '/' || t[tIdx - 1] === '_' || t[tIdx - 1] === '-' || t[tIdx - 1] === ' ' || t[tIdx - 1] === '.') {
                    score += 15;
                }
                prevMatchedIdx = tIdx;
                qIdx++;
            }
        }
        return qIdx === qLen ? score : -1;
    }

    function scanPath(query) {
        if (!root.isPathSelector) return;
        let q = query.trim();
        let home = (typeof Quickshell !== "undefined" && Quickshell.env("HOME")) ? Quickshell.env("HOME") : "";
        if (q.startsWith("~") && home !== "") {
            q = home + q.slice(1);
        }
        pathScanProcess.targetQuery = q;
        pathScanProcess.running = false;
        pathScanProcess.running = true;
    }

    Timer {
        id: pathScanTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (root.isPathSelector && root.isEditing && root.searchText.length > 0) {
                root.scanPath(root.searchText);
            }
        }
    }

    Process {
        id: pathScanProcess
        property string targetQuery: ""
        running: false
        command: {
            let pyScript =
                "import os, sys\n" +
                "home = os.path.expanduser('~')\n" +
                "q = sys.argv[1].strip()\n" +
                "exts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.mp4', '.mkv', '.mov', '.webm'}\n" +
                "dirs = set()\n" +
                "base = q if os.path.isdir(q) else (os.path.dirname(q) if (os.path.isabs(q) and os.path.exists(os.path.dirname(q))) else '')\n" +
                "search_roots = []\n" +
                "if base and os.path.isdir(base):\n" +
                "    search_roots.append(base)\n" +
                "else:\n" +
                "    search_roots = [home, os.path.join(home, 'Pictures'), os.path.join(home, 'Wallpapers'), os.path.join(home, 'Videos'), '/usr/share/backgrounds', '/usr/share/wallpapers']\n" +
                "for r in search_roots:\n" +
                "    if not os.path.isdir(r): continue\n" +
                "    dirs.add(r)\n" +
                "    for root_dir, subdirs, files in os.walk(r, followlinks=True):\n" +
                "        depth = root_dir[len(r):].count(os.sep)\n" +
                "        if depth > 3:\n" +
                "            subdirs[:] = []\n" +
                "            continue\n" +
                "        subdirs[:] = [d for d in subdirs if not d.startswith('.')]\n" +
                "        if any(os.path.splitext(f)[1].lower() in exts for f in files) or (q and q.lower() in root_dir.lower()):\n" +
                "            dirs.add(root_dir)\n" +
                "for d in sorted(list(dirs), key=lambda x: (x.count(os.sep), x.lower()))[:60]:\n" +
                "    print(d)\n";
            return ["python3", "-c", pyScript, targetQuery];
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
                if (lines.length > 0) {
                    let merged = root.options.slice();
                    let seen = new Set();
                    for (let i = 0; i < merged.length; i++) {
                        seen.add(merged[i]);
                    }
                    for (let i = 0; i < lines.length; i++) {
                        if (!seen.has(lines[i])) {
                            seen.add(lines[i]);
                            merged.push(lines[i]);
                        }
                    }
                    root.options = merged;
                    root.filterData();
                }
            }
        }
    }

    function closePopup() {
        popup.close();
    }

    function openPopup() {
        if (filteredOptions.length > 0) {
            popup.open();
        }
    }

    function startEditing() {
        if (!root.enabled) return;
        root.isEditing = true;
        root.searchText = "";
        innerInput.text = "";
        charModel.clear();
        root.scrollOffset = 0;
        root.filterData();
        innerInput.forceActiveFocus();
        if (root.isPathSelector && root.currentValue) {
            root.scanPath(root.currentValue);
        }
        if (!root.isOpen && root.filteredOptions.length > 0) {
            popup.open();
        }
    }

    function stopEditing() {
        root.isEditing = false;
        root.searchText = "";
        innerInput.text = "";
        charModel.clear();
        root.scrollOffset = 0;
        root.filteredOptions = root.options;
    }

    function filterData() {
        if (root.searchText === "") {
            root.filteredOptions = root.options.slice();
        } else {
            if (root.fuzzySearch) {
                let matches = [];
                for (let i = 0; i < root.options.length; i++) {
                    let opt = String(root.options[i]);
                    let score = root.fuzzyScore(root.searchText, opt);
                    if (score >= 0) {
                        matches.push({ opt: root.options[i], score: score, index: i });
                    }
                }
                matches.sort(function(a, b) {
                    return b.score - a.score || a.index - b.index;
                });
                root.filteredOptions = matches.map(function(m) { return m.opt; });
            } else {
                let lower = root.searchText.toLowerCase();
                root.filteredOptions = root.options.filter(function(opt) {
                    return String(opt).toLowerCase().indexOf(lower) !== -1;
                });
            }
        }
        if (root.filteredOptions.length === 0) {
            if (root.isOpen) popup.close();
        } else if (root.isEditing && !root.isOpen) {
            popup.open();
        }
    }

    function updateScroll() {
        let totalW = charRow.contentWidth;
        let visibleW = searchFieldArea.width;

        if (visibleW <= 0) return;

        if (totalW <= visibleW) {
            root.scrollOffset = 0;
            return;
        }

        let curX = innerInput.cursorPosition * root.charSlotStep;
        let minOffset = visibleW - totalW;
        let maxOffset = 0;
        let margin = 4;
        let curScreenX = curX + root.scrollOffset;

        if (curScreenX < margin) {
            root.scrollOffset = Math.min(maxOffset, Math.max(minOffset, margin - curX));
        } else if (curScreenX > visibleW - margin - 2) {
            root.scrollOffset = Math.min(maxOffset, Math.max(minOffset, visibleW - margin - 2 - curX));
        } else {
            root.scrollOffset = Math.min(maxOffset, Math.max(minOffset, root.scrollOffset));
        }
    }

    function syncModel() {
        let str = innerInput.text;
        let oldCount = charModel.count;
        let newCount = str.length;

        let prefix = 0;
        while (prefix < oldCount && prefix < newCount && charModel.get(prefix).char === str[prefix]) {
            prefix++;
        }

        let suffix = 0;
        while (suffix < (oldCount - prefix) && suffix < (newCount - prefix) && charModel.get(oldCount - 1 - suffix).char === str[newCount - 1 - suffix]) {
            suffix++;
        }

        let deleteCount = oldCount - prefix - suffix;
        if (deleteCount > 0) {
            charModel.remove(prefix, deleteCount);
        }

        let insertStr = str.slice(prefix, newCount - suffix);
        for (let i = 0; i < insertStr.length; i++) {
            charModel.insert(prefix + i, { char: insertStr[i] });
        }
        updateScroll();
    }

    onOptionsChanged: {
        if (!root.isEditing) {
            root.filteredOptions = root.options;
        } else {
            root.filterData();
        }
    }

    TextMetrics {
        id: globalCharMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        text: "0"
    }

    ListModel {
        id: charModel
    }

    Rectangle {
        id: mainBtn
        anchors.fill: parent
        radius: root.cornerRadius
        color: (root.isOpen || root.isHoveredOrHighlighted) ? root.hoverColor : root.baseColor
        border.color: root.isHoveredOrHighlighted ? Qt.lighter(root.borderColor, 1.2) : root.borderColor
        border.width: 1
        opacity: root.enabled ? 1.0 : 0.5

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        scale: (!root.enabled ? 1.0 : (btnMa.pressed ? 0.96 : 1.0)) * root.popScale
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.horizontalPadding
            anchors.rightMargin: root.horizontalPadding
            spacing: 8

            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    id: displayText
                    anchors.fill: parent
                    visible: !root.isEditing
                    text: root.currentValue !== "" ? root.currentValue : root.placeholderText
                    font.family: root.useOptionAsFontFamily && root.currentValue !== "" ? root.currentValue : root.fontFamily
                    font.pixelSize: root.fontPixelSize
                    color: root.textColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    layoutDirection: Qt.LeftToRight
                }

                Item {
                    id: searchFieldArea
                    anchors.fill: parent
                    visible: root.isEditing
                    clip: true
                    onWidthChanged: root.updateScroll()

                    Text {
                        id: placeholderLabel
                        text: root.placeholderText
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPixelSize
                        color: root.subTextColor
                        opacity: (innerInput.text.length === 0 && charModel.count === 0) ? 0.45 : 0.0
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    Rectangle {
                        id: selectionHighlight
                        readonly property int selMin: Math.min(innerInput.selectionStart, innerInput.selectionEnd)
                        readonly property int selMax: Math.max(innerInput.selectionStart, innerInput.selectionEnd)
                        readonly property bool hasSelection: selMax > selMin

                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.min(parent.height - 4, root.fontPixelSize * 1.7)
                        radius: 4
                        color: root.accentColor
                        opacity: hasSelection ? 0.28 : 0.0

                        x: root.scrollOffset + (selMin * root.charSlotStep) - 2
                        width: hasSelection ? ((selMax - selMin) * root.charSlotStep - root.charSpacing + 4) : 0

                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on x { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                        Behavior on width { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                    }

                    ListView {
                        id: charRow
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        orientation: ListView.Horizontal
                        interactive: false
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: root.charSpacing
                        width: contentWidth
                        x: root.scrollOffset
                        model: charModel

                        onContentWidthChanged: root.updateScroll()

                        property int entranceDuration: 420
                        property real entranceOvershoot: 3.2
                        property int exitDuration: 160

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 0.3; to: 1.0; duration: charRow.entranceDuration; easing.type: Easing.OutBack; easing.overshoot: charRow.entranceOvershoot }
                                NumberAnimation { property: "y"; from: 10; to: 0; duration: charRow.entranceDuration; easing.type: Easing.OutBack; easing.overshoot: charRow.entranceOvershoot * 0.8 }
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                            }
                        }

                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; to: 0.3; duration: charRow.exitDuration; easing.type: Easing.InBack }
                                NumberAnimation { property: "y"; to: -8; duration: charRow.exitDuration; easing.type: Easing.InCubic }
                                NumberAnimation { property: "opacity"; to: 0; duration: charRow.exitDuration * 0.9; easing.type: Easing.InCubic }
                            }
                        }

                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }

                        delegate: Item {
                            id: slot
                            width: globalCharMetrics.width
                            height: charRow.height
                            transformOrigin: Item.Center

                            Text {
                                anchors.centerIn: parent
                                text: model.char
                                color: root.textColor
                                font.family: root.fontFamily
                                font.pixelSize: root.fontPixelSize
                            }
                        }
                    }

                    Rectangle {
                        id: caretRect
                        width: 2
                        height: root.fontPixelSize * 1.2
                        color: root.accentColor
                        visible: root.isEditing && (innerInput.activeFocus || root.action_highlight)
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.scrollOffset + (innerInput.cursorPosition * root.charSlotStep)

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                        SequentialAnimation on opacity {
                            running: root.isEditing && (innerInput.activeFocus || root.action_highlight)
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 100; easing.type: Easing.InQuad }
                            PauseAnimation { duration: 400 }
                            NumberAnimation { to: 1; duration: 100; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 400 }
                        }
                    }

                    TextInput {
                        id: innerInput
                        anchors.fill: parent
                        opacity: 0
                        color: "transparent"
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        selectByMouse: true
                        mouseSelectionMode: TextInput.SelectCharacters
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPixelSize
                        enabled: root.enabled && root.isEditing

                        onCursorPositionChanged: root.updateScroll()
                        onSelectionStartChanged: root.updateScroll()
                        onSelectionEndChanged: root.updateScroll()

                        onTextEdited: {
                            if (root.isEditing) {
                                root.searchText = text;
                                root.syncModel();
                                if (typeof Sounds !== "undefined") {
                                    Sounds.playSfx(root.keySound);
                                }
                                root.filterData();
                                root.searchChanged(text);
                                if (root.isPathSelector) {
                                    pathScanTimer.restart();
                                }
                            }
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus && !root.isOpen) {
                                root.stopEditing();
                            }
                        }

                        Keys.onEscapePressed: {
                            popup.close();
                            root.stopEditing();
                        }

                        onAccepted: {
                            let textVal = innerInput.text.trim();
                            let home = (typeof Quickshell !== "undefined" && Quickshell.env("HOME")) ? Quickshell.env("HOME") : "";
                            let expandedVal = textVal;
                            if (expandedVal.startsWith("~") && home !== "") {
                                expandedVal = home + expandedVal.slice(1);
                            }

                            if (root.filteredOptions.length > 0) {
                                let actualValue = root.filteredOptions[0];
                                let actualIndex = root.options.indexOf(actualValue);
                                if (actualIndex !== -1) {
                                    if (root.currentIndex !== actualIndex) {
                                        root.currentIndex = actualIndex;
                                        root.valueChanged(actualIndex, actualValue);
                                    }
                                    root.selected(actualIndex, actualValue);
                                }
                            } else if (root.isPathSelector && textVal !== "") {
                                let opts = root.options.slice();
                                let idx = opts.indexOf(expandedVal);
                                if (idx === -1) {
                                    opts.unshift(expandedVal);
                                    root.options = opts;
                                    idx = 0;
                                }
                                if (root.currentIndex !== idx) {
                                    root.currentIndex = idx;
                                    root.valueChanged(idx, expandedVal);
                                }
                                root.selected(idx, expandedVal);
                            }
                            popup.close();
                            root.stopEditing();
                        }
                    }
                }
            }

            Text {
                text: root.isOpen ? "󰅃" : "󰅀"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.iconSize
                color: root.textColor
                verticalAlignment: Text.AlignVCenter
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            }
        }

        Rectangle {
            id: flashRect
            anchors.fill: parent
            radius: parent.radius
            color: "#ffffff"
            opacity: root.flashOpacity
            PropertyAnimation on opacity { id: btnFlashAnim; to: 0; duration: 350; easing.type: Easing.OutExpo }
        }

        SequentialAnimation {
            id: btnPopAnim
            NumberAnimation { target: root; property: "popScale"; to: 1.04; duration: 100; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "popScale"; to: 1.0; duration: 350; easing.type: Easing.OutQuint }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: root.enabled
            enabled: root.enabled
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            onClicked: {
                if (!root.enabled) return;
                btnPopAnim.start();
                root.flashOpacity = 0.2;
                btnFlashAnim.start();

                if (typeof Sounds !== "undefined") {
                    Sounds.playSfx(root.clickSound);
                }
                root.clicked();

                if (root.isEditing) {
                    popup.close();
                    root.stopEditing();
                    return;
                }

                if (root.isOpen) {
                    popup.close();
                } else {
                    if (root.filteredOptions.length > 0) {
                        popup.open();
                    }
                }
            }

            onDoubleClicked: {
                if (!root.enabled) return;
                btnPopAnim.start();
                root.flashOpacity = 0.2;
                btnFlashAnim.start();
                root.startEditing();
            }
        }
    }

    Popup {
        id: popup
        y: root.height + 6
        width: root.width
        padding: 4
        margins: 0
        transformOrigin: Item.Top
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
 	    radius: Math.min(root.cornerRadius, 16)
	    color: root.dropdownColor
            border.color: root.borderColor
            border.width: 1
            layer.enabled: true
        }

        onAboutToShow: {
            root.visibleCount = Math.min(root.filteredOptions.length, Math.floor((250 + 2) / 34));
            root.isOpen = true;
        }

        onAboutToHide: {
            root.isOpen = false;
        }

        onOpened: {
            root.opened();
        }

        onClosed: {
            root.closed();
            if (!innerInput.activeFocus) {
                root.stopEditing();
            }
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutQuint }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200; easing.type: Easing.OutQuint }
        }

        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InQuint }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 150; easing.type: Easing.InQuint }
        }

        contentItem: ListView {
            id: listView
            implicitHeight: Math.min(contentHeight, 250)
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            spacing: 2
            model: root.filteredOptions

            delegate: Rectangle {
                id: delegateRect
                width: listView.width
                height: 32
                radius: Math.max(2, Math.min(root.cornerRadius - 4, 16))

                property int realIndex: root.options.indexOf(modelData)
                property bool shown: root.isEditing

                Timer {
                    id: showTimer
                    running: root.isOpen && !root.isEditing && index < root.visibleCount && !delegateRect.shown
                    interval: index * 40 + 20
                    onTriggered: {
                        if (!delegateRect.shown) {
                            delegateRect.shown = true;
                            if (typeof Sounds !== "undefined") {
                                Sounds.playSfx(root.listSound, 0.75);
                            }
                        }
                    }
                }

                Connections {
                    target: root
                    function onIsOpenChanged() {
                        if (root.isOpen) {
                            if (root.isEditing || index >= root.visibleCount) {
                                delegateRect.shown = true;
                            }
                        } else {
                            delegateRect.shown = false;
                        }
                    }
                    function onIsEditingChanged() {
                        if (root.isEditing) {
                            delegateRect.shown = true;
                        }
                    }
                }

                Component.onCompleted: {
                    if (root.isEditing || (root.isOpen && index >= root.visibleCount)) {
                        delegateRect.shown = true;
                    }
                }

                opacity: (root.isEditing || shown) ? 1.0 : 0.0
                transform: Translate {
                    y: (root.isEditing || shown) ? 0 : 8
                    Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                color: root.currentIndex === realIndex ? root.accentColor : (itemMa.pressed ? Qt.darker(root.hoverColor, 1.1) : (itemMa.containsMouse ? root.hoverColor : "transparent"))
                Behavior on color { ColorAnimation { duration: 150 } }

                scale: itemMa.pressed ? 0.96 : (itemMa.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                property real flashOpacity: 0.0

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "#ffffff"
                    opacity: delegateRect.flashOpacity
                    PropertyAnimation on opacity { id: itemFlashAnim; to: 0; duration: 350; easing.type: Easing.OutExpo }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: modelData
                    font.family: root.useOptionAsFontFamily ? modelData : root.fontFamily
                    font.pixelSize: root.fontPixelSize
                    color: root.currentIndex === realIndex ? root.activeTextColor : root.textColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    layoutDirection: Qt.LeftToRight
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: itemMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        let selectedVal = modelData;
                        let rIdx = root.options.indexOf(selectedVal);
                        if (rIdx !== -1 && root.currentIndex !== rIdx) {
                            root.currentIndex = rIdx;
                            root.valueChanged(rIdx, selectedVal);
                        }
                        if (rIdx !== -1) {
                            root.selected(rIdx, selectedVal);
                        }
                        popup.close();
                        root.stopEditing();
                        if (typeof Sounds !== "undefined") {
                            Sounds.playSfx(root.clickSound);
                        }
                    }
                }
            }
        }
    }
}
