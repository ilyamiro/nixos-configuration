import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../singletons"
import "../../reusables"
import "../../"

Item {
    id: cardRoot

    property string noteId: ""
    property string noteContent: ""
    property real noteUpdatedAt: 0
    property int index: 0
    property bool isSelected: false
    property bool isExpanded: false
    property var scaleFunc: null
    property var listView: null
    property real availableExpandHeight: s(280)

    property bool isEditing: false
    property string previewHtml: ""
    property bool useQtFallback: false

    property real itemExpandProgress: 0
    property real dragX: 0
    property bool isDismissing: false
    property bool suppressExpandBinding: false
    readonly property bool canExpand: true
    readonly property bool isOverlayCard: !cardRoot.listView

    signal dismissRequested()

    function s(val) { return typeof scaleFunc === "function" ? scaleFunc(val) : val; }

    function syncExpandBinding() {
        cardRoot.itemExpandProgress = Qt.binding(() => cardRoot.isExpanded ? 1.0 : 0.0);
    }

    function breakExpandBinding() {
        cardRoot.itemExpandProgress = cardRoot.itemExpandProgress;
    }

    function resetDragState() {
        cardRoot.dragX = 0;
        cardRoot.isDismissing = false;
        cardRoot.suppressExpandBinding = false;
        cardRoot.syncExpandBinding();
    }

    onNoteIdChanged: {
        cardRoot.dragX = 0;
        cardRoot.isDismissing = false;
        if (cardRoot.isOverlayCard) {
            cardRoot.applyPreviewCache();
            NotesManager.scheduleRender(noteId);
            if (cardRoot.isExpanded)
                cardRoot.syncExpandBinding();
        } else {
            cardRoot.resetDragState();
        }
    }

    readonly property color cSurface1: ThemeBackend.surface1
    readonly property color cText: ThemeBackend.text
    readonly property color cSubtext0: ThemeBackend.subtext0
    readonly property color cCrust: ThemeBackend.crust
    readonly property color cBase: ThemeBackend.base
    readonly property color cMauve: ThemeBackend.mauve
    readonly property bool showExpandedBody: cardRoot.displayProgress > 0.02
    readonly property real displayProgress: (cardRoot.isOverlayCard && cardRoot.isExpanded)
        ? 1.0 : cardRoot.itemExpandProgress

    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a); }

    width: listView ? listView.width : parent.width
    height: cardRoot.isDismissing ? 0
        : (cardRoot.isOverlayCard && parent ? parent.height : noteCard.height)
    z: isSelected ? 2 : 1

    scale: (cardMa.pressed && !cardMa.draggingH && !cardMa.draggingV) ? 0.98 : 1.0
    Behavior on scale {
        enabled: !cardMa.draggingH && !cardMa.draggingV
        NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
    }

    Behavior on itemExpandProgress {
        enabled: !cardMa.draggingV && !entryExpandAnim.running && !collapseCloseAnim.running
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuart
            onRunningChanged: {
                if (!running && cardRoot.isSelected && cardRoot.listView)
                    cardRoot.listView.positionViewAtIndex(cardRoot.index, ListView.Contain);
            }
        }
    }

    Component.onCompleted: {
        if (cardRoot.isOverlayCard)
            cardRoot.itemExpandProgress = 0;
        else
            cardRoot.syncExpandBinding();
    }

    onIsExpandedChanged: {
        if (isExpanded) {
            applyPreviewCache();
            NotesManager.scheduleRender(noteId);
            if (NotesManager.pendingEditId === noteId) {
                NotesManager.pendingEditId = "";
                Qt.callLater(beginEditing);
            }
            if (listView) {
                if (!cardMa.draggingV && !cardRoot.suppressExpandBinding)
                    cardRoot.syncExpandBinding();
                listView.positionViewAtIndex(index, ListView.Beginning);
            } else if (cardRoot.visible) {
                cardRoot.playExpandEntry(0);
            } else {
                cardRoot.itemExpandProgress = 0;
            }
        } else {
            if (!cardMa.draggingV && !cardRoot.suppressExpandBinding)
                cardRoot.syncExpandBinding();
            if (isEditing)
                finishEditing();
        }
    }

    onVisibleChanged: {
        if (visible && isExpanded && cardRoot.isOverlayCard) {
            applyPreviewCache();
            NotesManager.scheduleRender(noteId);
            cardRoot.suppressExpandBinding = false;
            cardRoot.syncExpandBinding();
        }
    }

    Connections {
        target: NotesManager
        function onExpandedIdChanged() {
            if (NotesManager.expandedId === "" && cardRoot.listView)
                cardRoot.resetDragState();
        }
        function onRenderFinished(nid, html, fallback) {
            if (nid !== cardRoot.noteId) return;
            if (!html || html.trim() === "") {
                cardRoot.applyPreviewCache();
                return;
            }
            cardRoot.previewHtml = html;
            cardRoot.useQtFallback = fallback;
        }
    }

    function playExpandEntry(fromProgress) {
        if (entryExpandAnim.running) entryExpandAnim.stop();
        cardRoot.suppressExpandBinding = true;
        cardRoot.itemExpandProgress = fromProgress;
        entryExpandAnim.from = fromProgress;
        entryExpandAnim.to = 1.0;
        entryExpandAnim.start();
    }

    onItemExpandProgressChanged: {
        if (cardRoot.itemExpandProgress > 0.15 && !cardRoot.isEditing) {
            cardRoot.applyPreviewCache();
            NotesManager.scheduleRender(noteId, true);
        }
    }

    function applyPreviewCache() {
        let cached = NotesManager.getPreview(noteId);
        if (cached && cached.html !== undefined && cached.html !== "") {
            previewHtml = cached.html;
            useQtFallback = cached.useFallback;
        } else {
            useQtFallback = true;
            previewHtml = noteContent || "";
        }
    }

    onNoteContentChanged: {
        if (cardRoot.useQtFallback || !cardRoot.previewHtml)
            cardRoot.applyPreviewCache();
    }

    function toggleExpand() {
        if (cardRoot.isOverlayCard && cardRoot.isExpanded) {
            cardRoot.suppressExpandBinding = true;
            collapseCloseAnim.from = cardRoot.itemExpandProgress;
            collapseCloseAnim.to = 0;
            collapseCloseAnim.start();
            return;
        }
        NotesManager.toggleExpanded(noteId);
    }

    function beginEditing() {
        if (!isExpanded) NotesManager.setExpandedId(noteId);
        isEditing = true;
        NotesManager.editingNoteId = noteId;
        suppressEditorSave = true;
        editorArea.text = noteContent || "";
        suppressEditorSave = false;
        Qt.callLater(() => editorArea.forceActiveFocus());
    }

    function finishEditing() {
        if (!isEditing) return;
        NotesManager.updateNoteContent(noteId, editorArea.text);
        isEditing = false;
        if (NotesManager.editingNoteId === noteId)
            NotesManager.editingNoteId = "";
        NotesManager.scheduleRender(noteId);
    }

    property bool suppressEditorSave: false

    NumberAnimation {
        id: entryExpandAnim
        target: cardRoot
        property: "itemExpandProgress"
        duration: 280
        easing.type: Easing.OutQuart
        onFinished: {
            cardRoot.suppressExpandBinding = false;
            if (cardRoot.isExpanded)
                cardRoot.syncExpandBinding();
        }
    }

    NumberAnimation {
        id: collapseCloseAnim
        target: cardRoot
        property: "itemExpandProgress"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: {
            cardRoot.suppressExpandBinding = false;
            NotesManager.setExpandedId("");
            cardRoot.syncExpandBinding();
        }
    }

    NumberAnimation {
        id: resetAnim
        target: cardRoot
        property: "dragX"
        from: cardRoot.dragX
        to: 0
        duration: 200
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: dismissAnim
        target: cardRoot
        property: "dragX"
        from: cardRoot.dragX
        to: 0
        duration: 200
        easing.type: Easing.OutQuad
        onFinished: cardRoot.dismissRequested()
    }

    Text {
        id: textMeasure
        visible: false
        width: Math.max(10, cardRoot.width - cardRoot.s(80))
        text: cardRoot.noteContent || ""
        font.family: ThemeBackend.fontFamily
        font.pixelSize: cardRoot.s(13)
        wrapMode: Text.Wrap
    }

    Rectangle {
        id: noteCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        readonly property real baseH: cardRoot.s(52)
        readonly property real expandedH: {
            if (cardRoot.listView)
                return Math.max(cardRoot.s(160), cardRoot.listView.height);
            let hostH = cardRoot.parent ? cardRoot.parent.height : cardRoot.availableExpandHeight;
            return Math.max(cardRoot.s(160), cardRoot.availableExpandHeight, hostH);
        }
        height: (cardRoot.isOverlayCard && cardRoot.isExpanded)
            ? expandedH
            : baseH + (expandedH - baseH) * cardRoot.itemExpandProgress

        transform: Translate { x: cardRoot.dragX }
        opacity: Math.max(0.0, 1.0 - (Math.abs(cardRoot.dragX) / (noteCard.width * 0.75)))

        radius: Math.min(ThemeBackend.borderRadius, cardRoot.s(12))
        color: {
            if (cardRoot.showExpandedBody) return cardRoot.cSurface1;
            if (cardRoot.isSelected) return cardRoot.cMauve;
            return cardMa.containsMouse && !cardMa.draggingH && !cardMa.draggingV
                ? Qt.lighter(cardRoot.cSurface1, 1.04) : cardRoot.cSurface1;
        }
        clip: true

        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: !cardRoot.isDismissing
            cursorShape: Qt.PointingHandCursor

            property real startRootX: 0
            property real startRootY: 0
            property bool draggingH: false
            property bool draggingV: false

            onPressed: (mouse) => {
                NotesManager.setActiveId(cardRoot.noteId);
                cardRoot.breakExpandBinding();
                let pt = mapToItem(cardRoot.listView || cardRoot, mouse.x, mouse.y);
                startRootX = pt.x;
                startRootY = pt.y;
                draggingH = false;
                draggingV = false;
                resetAnim.stop();
                collapseCloseAnim.stop();
            }

            onPositionChanged: (mouse) => {
                if (!pressed) return;
                let pt = mapToItem(cardRoot.listView || cardRoot, mouse.x, mouse.y);
                let dx = pt.x - startRootX;
                let dy = pt.y - startRootY;

                if (!draggingH && !draggingV) {
                    if (Math.abs(dx) > cardRoot.s(6) && Math.abs(dx) > Math.abs(dy)) {
                        draggingH = true;
                        cardMa.preventStealing = true;
                    } else if (cardRoot.canExpand && Math.abs(dy) > cardRoot.s(6) && Math.abs(dy) >= Math.abs(dx)) {
                        draggingV = true;
                        cardMa.preventStealing = true;
                    }
                }

                if (draggingH) {
                    cardRoot.dragX = dx;
                } else if (draggingV && cardRoot.canExpand) {
                    let dragDist = cardRoot.s(120);
                    let targetProg = cardRoot.isExpanded
                        ? Math.max(0.0, Math.min(1.0, 1.0 + (dy / dragDist)))
                        : Math.max(0.0, Math.min(1.0, dy / dragDist));
                    cardRoot.itemExpandProgress = targetProg;
                }
            }

            onReleased: (mouse) => {
                cardMa.preventStealing = false;
                if (draggingH) {
                    let threshold = noteCard.width * 0.25;
                    if (Math.abs(cardRoot.dragX) > threshold) {
                        cardRoot.isDismissing = true;
                        dismissAnim.from = cardRoot.dragX;
                        dismissAnim.to = cardRoot.dragX > 0 ? noteCard.width * 1.2 : -noteCard.width * 1.2;
                        dismissAnim.start();
                    } else {
                        resetAnim.from = cardRoot.dragX;
                        resetAnim.start();
                    }
                    draggingH = false;
                } else if (draggingV && cardRoot.canExpand) {
                    if (!cardRoot.isExpanded && cardRoot.itemExpandProgress > 0.35) {
                        NotesManager.setExpandedId(cardRoot.noteId);
                        cardRoot.resetDragState();
                    } else if (cardRoot.isExpanded && cardRoot.itemExpandProgress < 0.65) {
                        if (cardRoot.isOverlayCard) {
                            cardRoot.suppressExpandBinding = true;
                            collapseCloseAnim.from = cardRoot.itemExpandProgress;
                            collapseCloseAnim.to = 0;
                            collapseCloseAnim.start();
                        } else {
                            cardRoot.syncExpandBinding();
                        }
                    } else {
                        cardRoot.syncExpandBinding();
                    }
                    draggingV = false;
                } else {
                    let ptE = mapToItem(expandIcon, mouse.x, mouse.y);
                    let inE = expandIcon.visible && ptE.x >= 0 && ptE.y >= 0
                        && ptE.x <= expandIcon.width && ptE.y <= expandIcon.height;
                    if (!inE) {
                        if (cardRoot.isExpanded)
                            cardRoot.beginEditing();
                        else
                            NotesManager.setExpandedId(cardRoot.noteId);
                    }
                }
            }

            onCanceled: {
                cardMa.preventStealing = false;
                if (draggingH) {
                    resetAnim.from = cardRoot.dragX;
                    resetAnim.start();
                    draggingH = false;
                }
                if (draggingV && cardRoot.canExpand) {
                    cardRoot.syncExpandBinding();
                    draggingV = false;
                }
            }
        }

        ColumnLayout {
            id: collapsedLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: cardRoot.s(12)
            anchors.rightMargin: cardRoot.canExpand ? cardRoot.s(42) : cardRoot.s(12)
            anchors.topMargin: cardRoot.s(8)
            anchors.bottomMargin: cardRoot.s(8)
            spacing: cardRoot.s(2)
            visible: cardRoot.displayProgress < 0.99
            opacity: Math.max(0.0, 1.0 - cardRoot.displayProgress * 2.5)

            Text {
                Layout.fillWidth: true
                text: NotesManager.noteTitle({ content: cardRoot.noteContent, title: "" })
                font.family: ThemeBackend.fontFamily
                font.bold: cardRoot.isSelected
                font.pixelSize: cardRoot.s(12)
                color: cardRoot.isSelected ? cardRoot.cCrust : cardRoot.cText
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (!cardRoot.noteContent || cardRoot.noteContent.trim() === "")
                        return I18n.t("quickactions.notepad.tap_to_write");
                    let preview = NotesManager.stripMarkdown(cardRoot.noteContent.replace(/\n/g, " ").trim());
                    return preview.length > 60 ? preview.substring(0, 60) + "…" : preview;
                }
                font.family: ThemeBackend.fontFamily
                font.pixelSize: cardRoot.s(11)
                color: cardRoot.isSelected ? cardRoot.alpha(cardRoot.cCrust, 0.85) : cardRoot.cSubtext0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                visible: cardRoot.noteUpdatedAt > 0
                text: {
                    let d = new Date(cardRoot.noteUpdatedAt);
                    return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
                }
                font.family: ThemeBackend.fontFamily
                font.pixelSize: cardRoot.s(8)
                color: cardRoot.isSelected ? cardRoot.alpha(cardRoot.cCrust, 0.65) : cardRoot.alpha(cardRoot.cSubtext0, 0.75)
                elide: Text.ElideRight
            }
        }

        FlipIcon {
            id: expandIcon
            z: 4
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: cardRoot.s(12.8)
            anchors.rightMargin: cardRoot.s(8)
            size: cardRoot.s(26.4)
            cornerRadius: cardRoot.s(6.6)
            accentColor: cardRoot.showExpandedBody ? ThemeBackend.surface2 : (cardRoot.isSelected ? Qt.rgba(0, 0, 0, 0.15) : ThemeBackend.surface2)
            iconColor: cardRoot.showExpandedBody
                ? (isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.subtext1)
                : (cardRoot.isSelected
                    ? (isHoveredOrHighlighted ? ThemeBackend.base : cardRoot.cCrust)
                    : (isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.subtext1))
            autoToggle: false
            visible: cardRoot.canExpand
            flipped: cardRoot.displayProgress > 0.5
            onClicked: {
                NotesManager.setActiveId(cardRoot.noteId);
                cardRoot.toggleExpand();
            }
        }

        Item {
            id: expandedArea
            z: 3
            visible: cardRoot.displayProgress > 0.001
            opacity: cardRoot.isOverlayCard && cardRoot.isExpanded
                ? 1.0
                : Math.max(0.0, (cardRoot.displayProgress - 0.15) / 0.85)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: cardRoot.s(6)
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Math.min(ThemeBackend.borderRadius, cardRoot.s(10))
                color: cardRoot.cBase
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: cardRoot.s(8)
                spacing: cardRoot.s(6)

                Text {
                    Layout.fillWidth: true
                    visible: cardRoot.displayProgress > 0.2
                    text: NotesManager.noteTitle({ content: cardRoot.noteContent, title: "" })
                    font.family: ThemeBackend.fontFamily
                    font.bold: true
                    font.pixelSize: cardRoot.s(13)
                    color: cardRoot.cText
                    elide: Text.ElideRight
                    opacity: Math.min(1.0, (cardRoot.displayProgress - 0.2) / 0.35)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        id: previewLayer
                        anchors.fill: parent
                        visible: !cardRoot.isEditing
                        opacity: cardRoot.isEditing ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Flickable {
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: Math.max(height, previewArea.paintedHeight)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: previewArea
                                width: parent.width
                                readOnly: true
                                selectByMouse: false
                                focus: false
                                textFormat: cardRoot.useQtFallback ? TextEdit.MarkdownText : TextEdit.RichText
                                text: cardRoot.useQtFallback
                                    ? (cardRoot.noteContent || "")
                                    : (cardRoot.previewHtml || cardRoot.noteContent || "")
                                color: cardRoot.cText
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: cardRoot.s(13)
                                wrapMode: TextEdit.Wrap
                            }
                        }

                        MouseArea {
                            id: previewClickMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: cardRoot.beginEditing()
                        }
                    }

                    Item {
                        id: editorLayer
                        anchors.fill: parent
                        visible: cardRoot.isEditing
                        opacity: cardRoot.isEditing ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Text {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            visible: editorArea.text.length === 0
                            text: I18n.t("quickactions.notepad.placeholder")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: cardRoot.s(13)
                            color: cardRoot.alpha(cardRoot.cSubtext0, 0.65)
                            z: 1
                        }

                        Flickable {
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: Math.max(height, editorArea.paintedHeight + cardRoot.s(16))
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: editorArea
                                width: parent.width
                                color: cardRoot.cText
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: cardRoot.s(13)
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                selectionColor: cardRoot.alpha(cardRoot.cMauve, 0.35)
                                selectedTextColor: cardRoot.cText

                                onTextChanged: {
                                    if (cardRoot.suppressEditorSave) return;
                                    NotesManager.updateNoteContent(cardRoot.noteId, text);
                                }

                                onActiveFocusChanged: {
                                    if (!activeFocus && cardRoot.isEditing)
                                        cardRoot.finishEditing();
                                }

                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) {
                                        cardRoot.finishEditing();
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
