//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../singletons"
import "../../"
import "../../reusables"

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property bool keepAlive: inNoteView && isEditing
    property bool isEditing: false
    property bool inNoteView: false
    property real noteViewProgress: 0
    property bool suppressViewTransition: false
    property int listExpandResetToken: 0
    property bool useSyncedListExpand: false
    property real syncedListExpand: 0
    property bool closeDragActive: false
    property string iconFont: "Font Awesome 6 Free Solid"
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    property string previewHtml: ""
    property bool useQtFallback: false
    property string activeNoteTitle: ""

    function s(val) { return typeof scaleFunc === "function" ? scaleFunc(val) : val; }

    property real baseW: s(380)
    property real baseL: s(420)
    property real preferredWidth: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseL + 50 : baseW
    property real preferredExtraLength: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (safeActiveEdge === "right") return 180;
        if (safeActiveEdge === "bottom") return 90;
        if (safeActiveEdge === "top") return -90;
        return 0;
    }

    property color cBase: ThemeBackend.base
    property color cMantle: ThemeBackend.mantle
    property color cSurface0: ThemeBackend.surface0
    property color cSurface1: ThemeBackend.surface1
    property color cText: ThemeBackend.text
    property color cSubtext0: ThemeBackend.subtext0
    property color cMauve: ThemeBackend.mauve
    property color cCrust: ThemeBackend.crust

    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a); }

    readonly property string notesPath: Caching.getStateDir("notepad") + "/notes.json"
    readonly property string renderInputPath: Caching.getRunDir("notepad") + "/render_in.json"
    readonly property string mdRenderScript: Caching.serpantinumDir + "/scripts/notepad/md_render.py"

    property var notes: []
    property string activeId: ""
    property bool loaded: false
    property bool suppressSave: false

    property var interceptedShortcuts: {
        if (!inNoteView || !isEditing || !editorArea.activeFocus) return [];
        return ["Return", "Enter", "Left", "Right", "Up", "Down", "Tab", "Shift+Tab", "Backspace"];
    }

    FileView {
        id: notesFile
        path: root.notesPath
        blockLoading: true
        watchChanges: false
    }

    FileView {
        id: renderInputFile
        path: root.renderInputPath
    }

    Timer {
        id: saveTimer
        interval: 400
        repeat: false
        onTriggered: root.persistNotes()
    }

    Timer {
        id: renderTimer
        interval: 120
        repeat: false
        onTriggered: root.requestRender()
    }

    Process {
        id: renderProc
        command: ["python3", root.mdRenderScript, root.renderInputPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let html = this.text.trim();
                if (html !== "") {
                    root.previewHtml = html;
                    root.useQtFallback = false;
                } else {
                    root.applyQtFallback();
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) root.applyQtFallback();
        }
    }

    function colorToHex(c) {
        if (!c) return "#ffffff";
        function channel(v) {
            let n = Math.round(Math.max(0, Math.min(1, v)) * 255);
            let h = n.toString(16);
            return h.length === 1 ? "0" + h : h;
        }
        return "#" + channel(c.r) + channel(c.g) + channel(c.b);
    }

    function themePayload() {
        return {
            text: colorToHex(cText),
            base: colorToHex(cBase),
            mantle: colorToHex(cMantle),
            mauve: colorToHex(cMauve),
            surface0: colorToHex(cSurface0),
            subtext0: colorToHex(cSubtext0),
            fontFamily: ThemeBackend.fontFamily
        };
    }

    function newId() {
        return "n_" + Date.now().toString(36) + "_" + Math.floor(Math.random() * 1e6).toString(36);
    }

    function stripMarkdown(line) {
        if (!line) return "";
        line = line.replace(/^#+\s*/, "");
        line = line.replace(/\*\*(.*?)\*\*/g, "$1");
        line = line.replace(/\*(.*?)\*/g, "$1");
        line = line.replace(/`(.*?)`/g, "$1");
        line = line.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
        return line.trim();
    }

    function noteTitle(note) {
        if (!note || !note.content) return I18n.t("quickactions.notepad.untitled");
        let lines = note.content.split("\n");
        for (let i = 0; i < lines.length; i++) {
            let line = root.stripMarkdown(lines[i]);
            if (line !== "") return line;
        }
        return I18n.t("quickactions.notepad.untitled");
    }

    function syncActiveNoteTitle() {
        root.activeNoteTitle = root.noteTitle(root.activeNote());
    }

    function activeNote() {
        for (let i = 0; i < root.notes.length; i++)
            if (root.notes[i].id === root.activeId) return root.notes[i];
        return null;
    }

    function activeIndex() {
        for (let i = 0; i < root.notes.length; i++)
            if (root.notes[i].id === root.activeId) return i;
        return -1;
    }

    function repopulateModel() {
        notesModel.clear();
        for (let i = 0; i < root.notes.length; i++)
            notesModel.append(root.notes[i]);
    }

    function loadFromDisk() {
        let raw = notesFile.text();
        if (!raw || raw.trim() === "") {
            root.notes = [];
            root.activeId = "";
            root.loaded = true;
            return;
        }
        try {
            let data = JSON.parse(raw);
            root.notes = Array.isArray(data.notes) ? data.notes : [];
            root.activeId = data.activeId || "";
            if (root.activeId && !root.activeNote()) root.activeId = root.notes.length > 0 ? root.notes[0].id : "";
        } catch (e) {
            root.notes = [];
            root.activeId = "";
        }
        root.loaded = true;
        root.syncActiveNoteTitle();
    }

    function persistNotes() {
        if (!root.loaded || root.suppressSave) return;
        let payload = JSON.stringify({
            activeId: root.activeId,
            notes: root.notes
        }, null, 2);
        notesFile.setText(payload);
    }

    function scheduleSave() {
        saveTimer.restart();
    }

    function scheduleRender() {
        if (!inNoteView || isEditing) return;
        renderTimer.restart();
    }

    function requestRender() {
        if (!inNoteView || isEditing) return;
        let note = root.activeNote();
        if (!note) return;
        let payload = JSON.stringify({
            markdown: note.content || "",
            theme: themePayload(),
            emptyHint: I18n.t("quickactions.notepad.tap_to_write")
        });
        renderInputFile.setText(payload);
        renderProc.running = false;
        renderProc.running = true;
    }

    function applyQtFallback() {
        root.useQtFallback = true;
        let note = root.activeNote();
        previewArea.text = note && note.content ? note.content : "";
    }

    function updateActiveContent(text) {
        let note = root.activeNote();
        if (!note) return;
        note.content = text;
        note.title = root.noteTitle(note);
        note.updatedAt = Date.now();
        let idx = root.activeIndex();
        if (idx >= 0) notesModel.set(idx, note);
        root.syncActiveNoteTitle();
        root.scheduleSave();
    }

    function beginEditing() {
        root.isEditing = true;
        root.suppressSave = true;
        editorArea.text = root.activeNote() ? (root.activeNote().content || "") : "";
        root.suppressSave = false;
        Qt.callLater(() => editorArea.forceActiveFocus());
    }

    function finishEditing() {
        if (!root.isEditing) return;
        root.updateActiveContent(editorArea.text);
        root.isEditing = false;
        root.scheduleRender();
    }

    function openNote(id) {
        root.activeId = id;
        root.inNoteView = true;
        root.isEditing = false;
        root.noteViewProgress = 1.0;
        root.syncActiveNoteTitle();
        root.scheduleRender();
    }

    function openNoteFromDrag(id, progress) {
        root.finishEditing();
        noteViewSnapAnim.stop();
        root.cancelCloseDragSync();
        root.suppressViewTransition = true;
        root.listExpandResetToken++;
        root.activeId = id;
        root.inNoteView = true;
        root.isEditing = false;
        root.noteViewProgress = 1.0;
        root.syncActiveNoteTitle();
        root.scheduleRender();
        Qt.callLater(() => root.suppressViewTransition = false);
    }

    function closeNoteView() {
        root.finishEditing();
        root.persistNotes();
        root.inNoteView = false;
        root.isEditing = false;
        root.noteViewProgress = 0;
        root.cancelCloseDragSync();
    }

    function beginCloseDragSync() {
        if (root.useSyncedListExpand) return;
        let idx = root.activeIndex();
        if (idx >= 0)
            notesList.positionViewAtIndex(idx, ListView.Beginning);
        root.closeDragActive = true;
        root.useSyncedListExpand = true;
        root.syncedListExpand = root.noteViewProgress;
    }

    function updateCloseDragProgress(progress) {
        let clamped = Math.max(0.0, Math.min(1.0, progress));
        if (root.closeDragActive && root.inNoteView && clamped < 0.06)
            clamped = 0.06;
        root.noteViewProgress = clamped;
        if (root.useSyncedListExpand)
            root.syncedListExpand = clamped;
    }

    function finishCloseDragGesture() {
        if (root.noteViewProgress < 0.65)
            root.commitDragClose();
        else
            root.snapNoteViewOpen();
    }

    function cancelCloseDragSync() {
        listCollapseAnim.stop();
        root.closeDragActive = false;
        root.useSyncedListExpand = false;
        root.syncedListExpand = 0;
    }

    function handoffToListCollapse() {
        let progress = root.useSyncedListExpand
            ? root.syncedListExpand
            : root.noteViewProgress;
        if (progress <= 0.01 && root.closeDragActive)
            progress = 0.12;
        root.closeDragActive = false;
        root.finishEditing();
        root.persistNotes();
        root.inNoteView = false;
        root.isEditing = false;
        root.noteViewProgress = 0;

        if (progress <= 0.01) {
            root.cancelCloseDragSync();
            root.listExpandResetToken++;
            return;
        }

        root.useSyncedListExpand = true;
        root.syncedListExpand = progress;
        listCollapseAnim.stop();
        listCollapseAnim.from = progress;
        listCollapseAnim.to = 0;
        listCollapseAnim.start();
    }

    function animateNoteViewClose() {
        if (!root.inNoteView) return;
        noteViewSnapAnim.stop();
        root.handoffToListCollapse();
    }

    function commitDragClose() {
        if (!root.inNoteView) return;
        noteViewSnapAnim.stop();
        root.handoffToListCollapse();
    }

    function snapNoteViewOpen() {
        root.cancelCloseDragSync();
        noteViewSnapAnim.from = root.noteViewProgress;
        noteViewSnapAnim.to = 1.0;
        noteViewSnapAnim.start();
    }

    function createNote() {
        let note = {
            id: root.newId(),
            title: I18n.t("quickactions.notepad.untitled"),
            content: "",
            updatedAt: Date.now()
        };
        root.notes.unshift(note);
        notesModel.insert(0, note);
        root.openNote(note.id);
        root.beginEditing();
    }

    function deleteNoteAtIndex(idx) {
        if (idx < 0 || idx >= root.notes.length) return;
        let removedId = root.notes[idx].id;
        root.notes.splice(idx, 1);
        notesModel.remove(idx);
        if (root.activeId === removedId) {
            if (root.notes.length === 0) {
                root.activeId = "";
                root.inNoteView = false;
                root.isEditing = false;
                root.noteViewProgress = 0;
            } else {
                root.activeId = root.notes[Math.min(idx, root.notes.length - 1)].id;
            }
        }
        root.persistNotes();
    }

    function selectNote(id) {
        root.finishEditing();
        root.openNote(id);
    }

    ListModel { id: notesModel }

    Behavior on noteViewProgress {
        enabled: !root.suppressViewTransition && !noteViewSnapAnim.running
            && !noteViewHeaderMa.draggingClose && !previewClickMa.closeDragging
        NumberAnimation { duration: 280; easing.type: Easing.OutQuart }
    }

    NumberAnimation {
        id: noteViewSnapAnim
        target: root
        property: "noteViewProgress"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: Qt.callLater(() => root.suppressViewTransition = false)
    }

    NumberAnimation {
        id: listCollapseAnim
        target: root
        property: "syncedListExpand"
        duration: 280
        easing.type: Easing.OutQuart
        onFinished: {
            root.useSyncedListExpand = false;
            root.syncedListExpand = 0;
            root.listExpandResetToken++;
        }
    }

    onIsActiveTabChanged: {
        if (!isActiveTab && isEditing) root.finishEditing();
    }

    Component.onCompleted: {
        loadFromDisk();
        repopulateModel();
        inNoteView = false;
    }

    Component.onDestruction: persistNotes()

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: root.cMantle
            radius: ThemeBackend.borderRadius
            z: -1
        }

        ColumnLayout {
            id: listLayer
            anchors.fill: parent
            anchors.margins: root.s(12)
            spacing: root.s(8)
            z: 0
            readonly property bool showLayer: !root.inNoteView || root.useSyncedListExpand
            visible: showLayer
            opacity: showLayer ? 1 : 0
            Behavior on opacity {
                enabled: !root.suppressViewTransition && !root.useSyncedListExpand
                NumberAnimation { duration: 180 }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                Text {
                    text: I18n.t("quickactions.notepad.title")
                    font.family: ThemeBackend.fontFamily
                    font.bold: true
                    font.pixelSize: root.s(14)
                    color: root.cText
                }

                Item { Layout.fillWidth: true }

                ClickButton {
                    buttonText: I18n.t("quickactions.notepad.new")
                    onTriggered: root.createNote()
                }

                DeleteButton {
                    Layout.preferredWidth: root.s(30)
                    Layout.preferredHeight: root.s(30)
                    enabled: root.activeId !== ""
                    onTriggered: root.deleteNoteAtIndex(root.activeIndex());
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: notesList
                    anchors.fill: parent
                    spacing: root.s(4)
                    model: notesModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    displaced: Transition {
                        enabled: root.useSyncedListExpand || listCollapseAnim.running
                        NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutQuart }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: notesModel.count === 0
                        text: I18n.t("quickactions.notepad.empty_list")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(11)
                        color: root.cSubtext0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    delegate: Item {
                        id: noteDelegateWrapper
                        width: notesList.width
                        height: noteDelegateWrapper.isDismissing ? 0 : noteDelegateCard.height

                        property bool isSelected: model.id === root.activeId
                        property real dragX: 0
                        property bool isDismissing: false
                        property real localExpandProgress: 0
                        readonly property real itemExpandProgress: (root.useSyncedListExpand && model.id === root.activeId)
                            ? root.syncedListExpand : noteDelegateWrapper.localExpandProgress

                        readonly property real cardBaseH: root.s(52)
                        readonly property real cardExpandedH: Math.max(root.s(160), notesList.height)

                        Connections {
                            target: root
                            function onListExpandResetTokenChanged() {
                                noteDelegateWrapper.localExpandProgress = 0;
                            }
                        }

                        Behavior on localExpandProgress {
                            enabled: !noteCardMa.draggingV && !root.suppressViewTransition && !root.useSyncedListExpand
                            NumberAnimation { duration: 280; easing.type: Easing.OutQuart }
                        }

                        scale: (noteCardMa.pressed && !noteCardMa.draggingH && !noteCardMa.draggingV) ? 0.98 : 1.0
                        Behavior on scale {
                            enabled: !noteCardMa.draggingH && !noteCardMa.draggingV
                            NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                        }

                        NumberAnimation {
                            id: noteResetAnim
                            target: noteDelegateWrapper
                            property: "dragX"
                            from: noteDelegateWrapper.dragX
                            to: 0
                            duration: 200
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            id: expandResetAnim
                            target: noteDelegateWrapper
                            property: "localExpandProgress"
                            duration: 220
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            id: noteDismissAnim
                            target: noteDelegateWrapper
                            property: "dragX"
                            from: noteDelegateWrapper.dragX
                            to: 0
                            duration: 200
                            easing.type: Easing.OutQuad
                            onFinished: root.deleteNoteAtIndex(index)
                        }

                        Rectangle {
                            id: noteDelegateCard
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: noteDelegateWrapper.cardBaseH
                                + (noteDelegateWrapper.cardExpandedH - noteDelegateWrapper.cardBaseH) * noteDelegateWrapper.itemExpandProgress
                            radius: Math.min(ThemeBackend.borderRadius, root.s(12))
                            color: {
                                if (noteDelegateWrapper.itemExpandProgress > 0) return root.cBase;
                                if (noteDelegateWrapper.isSelected) return root.cMauve;
                                return noteCardMa.containsMouse && !noteCardMa.draggingH && !noteCardMa.draggingV
                                    ? Qt.lighter(root.cSurface1, 1.04) : root.cSurface1;
                            }
                            border.width: noteDelegateWrapper.itemExpandProgress > 0 ? 1 : 0
                            border.color: root.cSurface1
                            clip: true

                            transform: Translate { x: noteDelegateWrapper.dragX }
                            opacity: Math.max(0.0, 1.0 - (Math.abs(noteDelegateWrapper.dragX) / (noteDelegateCard.width * 0.75)))

                            Behavior on color {
                                enabled: !noteCardMa.draggingH && !noteCardMa.draggingV
                                ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: root.s(12)
                                anchors.rightMargin: root.s(12)
                                anchors.topMargin: root.s(8)
                                anchors.bottomMargin: root.s(8)
                                spacing: root.s(2)
                                opacity: Math.max(0.0, 1.0 - noteDelegateWrapper.itemExpandProgress * 2.5)

                                Text {
                                    Layout.fillWidth: true
                                    text: root.noteTitle({ content: model.content, title: model.title })
                                    font.family: ThemeBackend.fontFamily
                                    font.bold: noteDelegateWrapper.isSelected
                                    font.pixelSize: root.s(12)
                                    color: noteDelegateWrapper.isSelected ? root.cCrust : root.cText
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (!model.content || model.content.trim() === "") return I18n.t("quickactions.notepad.tap_to_write");
                                        let preview = root.stripMarkdown(model.content.replace(/\n/g, " ").trim());
                                        return preview.length > 60 ? preview.substring(0, 60) + "…" : preview;
                                    }
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(11)
                                    color: noteDelegateWrapper.isSelected
                                        ? root.alpha(root.cCrust, 0.85)
                                        : root.cSubtext0
                                    elide: Text.ElideRight
                                    maximumLineCount: 1

                                    Behavior on color {
                                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: model.updatedAt > 0
                                    text: {
                                        let d = new Date(model.updatedAt);
                                        return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
                                    }
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(8)
                                    color: noteDelegateWrapper.isSelected
                                        ? root.alpha(root.cCrust, 0.65)
                                        : root.alpha(root.cSubtext0, 0.75)
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Item {
                                z: 2
                                anchors.fill: parent
                                anchors.margins: root.s(8)
                                clip: true
                                visible: noteDelegateWrapper.itemExpandProgress > 0.15
                                opacity: Math.max(0.0, (noteDelegateWrapper.itemExpandProgress - 0.15) / 0.85)

                                Text {
                                    anchors.fill: parent
                                    text: {
                                        if (!model.content || model.content.trim() === "")
                                            return I18n.t("quickactions.notepad.tap_to_write");
                                        return model.content;
                                    }
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(12)
                                    color: root.cText
                                    wrapMode: Text.Wrap
                                    clip: true
                                }
                            }

                            MouseArea {
                                id: noteCardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !noteDelegateWrapper.isDismissing
                                cursorShape: Qt.PointingHandCursor

                                property real startRootX: 0
                                property real startRootY: 0
                                property bool draggingH: false
                                property bool draggingV: false

                                onPressed: (mouse) => {
                                    let pt = mapToItem(notesList, mouse.x, mouse.y);
                                    startRootX = pt.x;
                                    startRootY = pt.y;
                                    draggingH = false;
                                    draggingV = false;
                                    noteResetAnim.stop();
                                    expandResetAnim.stop();
                                }

                                onPositionChanged: (mouse) => {
                                    if (!pressed) return;
                                    let pt = mapToItem(notesList, mouse.x, mouse.y);
                                    let dx = pt.x - startRootX;
                                    let dy = pt.y - startRootY;

                                    if (!draggingH && !draggingV) {
                                        if (Math.abs(dx) > root.s(6) && Math.abs(dx) > Math.abs(dy)) {
                                            draggingH = true;
                                            noteCardMa.preventStealing = true;
                                        } else if (Math.abs(dy) > root.s(6) && Math.abs(dy) >= Math.abs(dx)) {
                                            draggingV = true;
                                            noteCardMa.preventStealing = true;
                                        }
                                    }

                                    if (draggingH) {
                                        noteDelegateWrapper.dragX = dx;
                                    } else if (draggingV) {
                                        let dragDist = root.s(120);
                                        noteDelegateWrapper.localExpandProgress = Math.max(0.0, Math.min(1.0, dy / dragDist));
                                    }
                                }

                                onReleased: (mouse) => {
                                    noteCardMa.preventStealing = false;
                                    if (draggingH) {
                                        let threshold = noteDelegateCard.width * 0.25;
                                        if (Math.abs(noteDelegateWrapper.dragX) > threshold) {
                                            noteDelegateWrapper.isDismissing = true;
                                            noteDismissAnim.from = noteDelegateWrapper.dragX;
                                            noteDismissAnim.to = noteDelegateWrapper.dragX > 0
                                                ? noteDelegateCard.width * 1.2
                                                : -noteDelegateCard.width * 1.2;
                                            noteDismissAnim.start();
                                        } else {
                                            noteResetAnim.from = noteDelegateWrapper.dragX;
                                            noteResetAnim.start();
                                        }
                                        draggingH = false;
                                    } else if (draggingV) {
                                        if (noteDelegateWrapper.localExpandProgress > 0.35) {
                                            root.openNoteFromDrag(model.id, noteDelegateWrapper.localExpandProgress);
                                        } else {
                                            expandResetAnim.from = noteDelegateWrapper.localExpandProgress;
                                            expandResetAnim.to = 0;
                                            expandResetAnim.start();
                                        }
                                        draggingV = false;
                                    } else {
                                        root.activeId = model.id;
                                        root.selectNote(model.id);
                                    }
                                }

                                onCanceled: {
                                    noteCardMa.preventStealing = false;
                                    if (draggingH) {
                                        noteResetAnim.from = noteDelegateWrapper.dragX;
                                        noteResetAnim.start();
                                        draggingH = false;
                                    }
                                    if (draggingV) {
                                        expandResetAnim.from = noteDelegateWrapper.localExpandProgress;
                                        expandResetAnim.to = 0;
                                        expandResetAnim.start();
                                        draggingV = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: noteViewLayer
            anchors.fill: parent
            anchors.margins: root.s(12)
            spacing: root.s(8)
            z: 1
            visible: root.inNoteView
            opacity: root.inNoteView ? 1 : 0
            Behavior on opacity {
                enabled: !root.suppressViewTransition && !root.useSyncedListExpand
                NumberAnimation { duration: 180 }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(6)
                z: 2
                opacity: root.useSyncedListExpand ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }

                ClickButton {
                    buttonText: I18n.t("quickactions.notepad.back_to_list")
                    enabled: !root.useSyncedListExpand
                    onTriggered: root.animateNoteViewClose()
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(20)

                    Text {
                        anchors.fill: parent
                        text: root.activeNoteTitle
                        font.family: ThemeBackend.fontFamily
                        font.bold: true
                        font.pixelSize: root.s(12)
                        color: root.cText
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        id: noteViewHeaderMa
                        anchors.fill: parent
                        enabled: !root.isEditing
                        cursorShape: Qt.ClosedHandCursor

                        property real startY: 0
                        property bool draggingClose: false

                        onPressed: (mouse) => {
                            startY = mouse.y;
                            draggingClose = false;
                            noteViewSnapAnim.stop();
                        }

                        onPositionChanged: (mouse) => {
                            if (!pressed || root.isEditing) return;
                            let dy = mouse.y - startY;
                            if (!draggingClose && dy < -root.s(6)) {
                                draggingClose = true;
                                noteViewHeaderMa.preventStealing = true;
                            }
                            if (draggingClose) {
                                root.beginCloseDragSync();
                                let dragDist = root.s(120);
                                root.updateCloseDragProgress(1.0 + (dy / dragDist));
                            }
                        }

                        function finishCloseDrag() {
                            noteViewHeaderMa.preventStealing = false;
                            if (!draggingClose) return;
                            draggingClose = false;
                            root.finishCloseDragGesture();
                        }

                        onReleased: finishCloseDrag()
                        onCanceled: finishCloseDrag()
                    }
                }
            }

            Item {
                id: noteViewBodyHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

            Rectangle {
                id: noteViewCard
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                readonly property real fillProgress: root.useSyncedListExpand
                    ? root.syncedListExpand
                    : root.noteViewProgress
                height: Math.max(root.s(52), parent.height * fillProgress)
                opacity: root.useSyncedListExpand ? 0 : 1
                radius: ThemeBackend.borderRadius
                color: root.cBase
                border.width: root.useSyncedListExpand ? 0 : 1
                border.color: root.isEditing ? root.cMauve : root.cSurface1
                clip: true

                // --- PREVIEW (rendered markdown) ---
                Item {
                    id: previewLayer
                    anchors.fill: parent
                    visible: !root.isEditing
                    opacity: root.isEditing ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Flickable {
                        id: previewFlickable
                        anchors.fill: parent
                        anchors.margins: root.s(8)
                        contentWidth: width
                        contentHeight: Math.max(height, previewArea.paintedHeight + root.s(48))
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: previewArea
                            width: parent.width
                            readOnly: true
                            selectByMouse: false
                            focus: false
                            textFormat: root.useQtFallback ? TextEdit.MarkdownText : TextEdit.RichText
                            text: root.useQtFallback
                                ? ((root.activeNote() && root.activeNote().content) ? root.activeNote().content : "")
                                : root.previewHtml
                            color: root.cText
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(13)
                            wrapMode: TextEdit.Wrap
                        }
                    }

                    MouseArea {
                        id: previewClickMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.isEditing
                        cursorShape: Qt.IBeamCursor

                        property real pressY: 0
                        property real pressContentY: 0
                        property bool closeDragging: false
                        property bool didDrag: false

                        onPressed: (mouse) => {
                            pressY = mouse.y;
                            pressContentY = previewFlickable.contentY;
                            closeDragging = false;
                            didDrag = false;
                            noteViewSnapAnim.stop();
                        }

                        onPositionChanged: (mouse) => {
                            if (!pressed || root.isEditing) return;
                            let dy = mouse.y - pressY;
                            if (Math.abs(dy) > root.s(4))
                                didDrag = true;
                            if (!closeDragging && pressContentY <= 0 && dy < -root.s(6)) {
                                closeDragging = true;
                                previewClickMa.preventStealing = true;
                                root.beginCloseDragSync();
                            }
                            if (closeDragging) {
                                let dragDist = root.s(120);
                                root.updateCloseDragProgress(1.0 + (dy / dragDist));
                            }
                        }

                        function finishCloseDrag() {
                            previewClickMa.preventStealing = false;
                            if (closeDragging) {
                                closeDragging = false;
                                root.finishCloseDragGesture();
                                return;
                            }
                            if (!didDrag)
                                root.beginEditing();
                        }

                        onReleased: finishCloseDrag()
                        onCanceled: finishCloseDrag()
                    }
                }

                // --- SOURCE EDITOR ---
                Item {
                    id: editorLayer
                    anchors.fill: parent
                    visible: root.isEditing
                    opacity: root.isEditing ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: root.s(14)
                        visible: editorArea.text.length === 0
                        text: I18n.t("quickactions.notepad.placeholder")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(13)
                        color: root.alpha(root.cSubtext0, 0.65)
                        z: 1
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: root.s(10)
                        contentWidth: width
                        contentHeight: Math.max(height, editorArea.paintedHeight + root.s(24))
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: editorArea
                            width: parent.width
                            color: root.cText
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(13)
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            selectionColor: root.alpha(root.cMauve, 0.35)
                            selectedTextColor: root.cText

                            onTextChanged: {
                                if (root.suppressSave) return;
                                root.updateActiveContent(text);
                            }

                            onActiveFocusChanged: {
                                if (!activeFocus && root.isEditing)
                                    root.finishEditing();
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    root.finishEditing();
                                    event.accepted = true;
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
