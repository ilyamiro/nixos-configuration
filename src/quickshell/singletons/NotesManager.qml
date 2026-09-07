pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    ListModel { id: notesModelInternal }
    property alias notesModel: notesModelInternal

    property string activeId: ""
    property string expandedId: ""
    property string pendingEditId: ""
    property string editingNoteId: ""
    property bool loaded: false
    property bool suppressSave: false

    property var previewCache: ({})
    property string pendingRenderId: ""

    readonly property string notesPath: Caching.getStateDir("notepad") + "/notes.json"
    readonly property string renderInputPath: Caching.getRunDir("notepad") + "/render_in.json"
    readonly property string mdRenderScript: Caching.serpantinumDir + "/scripts/notepad/md_render.py"

    signal noteExpanded(string id)
    signal renderFinished(string noteId, string html, bool useFallback)

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
        property string noteId: ""
        onTriggered: root.runPendingRender()
    }

    Process {
        id: renderProc
        command: ["python3", root.mdRenderScript, root.renderInputPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let noteId = root.pendingRenderId;
                if (!noteId) return;
                let html = this.text.trim();
                if (html !== "") {
                    root.previewCache[noteId] = { html: html, useFallback: false };
                    root.renderFinished(noteId, html, false);
                } else {
                    root.applyQtFallback(noteId);
                }
                root.pendingRenderId = "";
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0 && root.pendingRenderId)
                root.applyQtFallback(root.pendingRenderId);
        }
    }

    Component.onCompleted: loadFromDisk()

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

    function getNoteById(id) {
        for (let i = 0; i < notesModelInternal.count; i++) {
            let n = notesModelInternal.get(i);
            if (n && n.id === id) return n;
        }
        return null;
    }

    function indexOfId(id) {
        for (let i = 0; i < notesModel.count; i++) {
            if (notesModel.get(i).id === id) return i;
        }
        return -1;
    }

    function repopulateModel(notes) {
        notesModel.clear();
        for (let i = 0; i < notes.length; i++)
            notesModel.append(notes[i]);
    }

    function loadFromDisk() {
        let raw = notesFile.text();
        if (!raw || raw.trim() === "") {
            root.activeId = "";
            root.expandedId = "";
            root.repopulateModel([]);
            root.loaded = true;
            return;
        }
        try {
            let data = JSON.parse(raw);
            let notes = Array.isArray(data.notes) ? data.notes : [];
            root.activeId = data.activeId || "";
            if (root.activeId && root.indexOfId(root.activeId) < 0)
                root.activeId = notes.length > 0 ? notes[0].id : "";
            root.repopulateModel(notes);
        } catch (e) {
            root.activeId = "";
            root.repopulateModel([]);
        }
        root.expandedId = "";
        root.loaded = true;
    }

    function persistNotes() {
        if (!root.loaded || root.suppressSave) return;
        let notes = [];
        for (let i = 0; i < notesModel.count; i++)
            notes.push(notesModel.get(i));
        let payload = JSON.stringify({
            activeId: root.activeId,
            notes: notes
        }, null, 2);
        notesFile.setText(payload);
    }

    function scheduleSave() {
        saveTimer.restart();
    }

    function setActiveId(id) {
        root.activeId = id;
        root.scheduleSave();
    }

    function setExpandedId(id) {
        if (root.expandedId === id) return;
        root.expandedId = id;
        if (id) {
            root.activeId = id;
            root.noteExpanded(id);
            root.scheduleRender(id);
        }
        root.scheduleSave();
    }

    function toggleExpanded(id) {
        if (root.expandedId === id)
            root.setExpandedId("");
        else
            root.setExpandedId(id);
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
            text: colorToHex(ThemeBackend.text),
            base: colorToHex(ThemeBackend.base),
            mantle: colorToHex(ThemeBackend.mantle),
            mauve: colorToHex(ThemeBackend.mauve),
            surface0: colorToHex(ThemeBackend.surface0),
            subtext0: colorToHex(ThemeBackend.subtext0),
            fontFamily: ThemeBackend.fontFamily
        };
    }

    function scheduleRender(noteId) {
        if (!noteId || root.expandedId !== noteId) return;
        renderTimer.noteId = noteId;
        renderTimer.restart();
    }

    function runPendingRender() {
        let noteId = renderTimer.noteId;
        if (!noteId) return;
        let note = root.getNoteById(noteId);
        if (!note) return;
        root.pendingRenderId = noteId;
        let payload = JSON.stringify({
            markdown: note.content || "",
            theme: root.themePayload(),
            emptyHint: I18n.t("quickactions.notepad.tap_to_write")
        });
        renderInputFile.setText(payload);
        renderProc.running = false;
        renderProc.running = true;
    }

    function applyQtFallback(noteId) {
        let note = root.getNoteById(noteId);
        let content = note && note.content ? note.content : "";
        root.previewCache[noteId] = { html: content, useFallback: true };
        root.renderFinished(noteId, content, true);
        root.pendingRenderId = "";
    }

    function getPreview(noteId) {
        return root.previewCache[noteId] || null;
    }

    function updateNoteContent(id, text) {
        let idx = root.indexOfId(id);
        if (idx < 0) return;
        let note = notesModel.get(idx);
        note.content = text;
        note.title = root.noteTitle(note);
        note.updatedAt = Date.now();
        notesModel.set(idx, note);
        delete root.previewCache[id];
        root.scheduleSave();
        if (root.expandedId === id)
            root.scheduleRender(id);
    }

    function createNote() {
        let note = {
            id: root.newId(),
            title: I18n.t("quickactions.notepad.untitled"),
            content: "",
            updatedAt: Date.now()
        };
        notesModel.insert(0, note);
        root.activeId = note.id;
        root.expandedId = note.id;
        root.pendingEditId = note.id;
        root.scheduleSave();
        return note.id;
    }

    function deleteNoteAtIndex(idx) {
        if (idx < 0 || idx >= notesModel.count) return;
        let removedId = notesModel.get(idx).id;
        notesModel.remove(idx);
        delete root.previewCache[removedId];
        if (root.activeId === removedId) {
            if (notesModel.count === 0) {
                root.activeId = "";
                root.expandedId = "";
            } else {
                let nextIdx = Math.min(idx, notesModel.count - 1);
                root.activeId = notesModel.get(nextIdx).id;
                if (root.expandedId === removedId)
                    root.expandedId = "";
            }
        } else if (root.expandedId === removedId) {
            root.expandedId = "";
        }
        if (root.pendingEditId === removedId)
            root.pendingEditId = "";
        if (root.editingNoteId === removedId)
            root.editingNoteId = "";
        root.persistNotes();
    }

    function deleteNoteById(id) {
        let idx = root.indexOfId(id);
        if (idx >= 0) root.deleteNoteAtIndex(idx);
    }
}
