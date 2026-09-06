pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property string appClass: ""
    property string appTitle: ""
    readonly property string displayText: appTitle !== "" ? appTitle : appClass
    readonly property bool isFocused: displayText !== ""

    Process {
        id: focusDaemon
        command: ["bash", "-c", Caching.serpantinumDir + "/scripts/current_focus.sh"]
        running: typeof Caching !== "undefined" && Caching.serpantinumDir !== undefined && Caching.serpantinumDir !== ""
    }

    FileView {
        id: focusWatcher
        path: (typeof Caching !== "undefined" && Caching.getRunDir && Caching.getRunDir("focustime")) ? (Caching.getRunDir("focustime") + "/focus_state.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let data = JSON.parse(txt);
                    root.appClass = data.app_class || "";
                    root.appTitle = data.app_title || "";
                } catch(e) {}
            } else {
                root.appClass = "";
                root.appTitle = "";
            }
        }
    }
}
