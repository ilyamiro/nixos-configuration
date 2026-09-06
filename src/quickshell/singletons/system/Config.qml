pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: config

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string userConfigDir: homeDir + "/.config/serpantinum"
    
    readonly property string settingsJsonPath: Quickshell.env("QS_SETTINGS") ? Quickshell.env("QS_SETTINGS") : (userConfigDir + "/settings.json")

    property bool dataReady: false
    property var rawSettings: ({})

    signal settingsLoaded()

    function sh(cmd) {
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function getSetting(key, fallbackValue) {
        return (rawSettings && rawSettings.hasOwnProperty(key)) ? rawSettings[key] : fallbackValue;
    }

    function setSetting(key, value) {
        let temp = Object.assign({}, rawSettings);
        temp[key] = value;
        rawSettings = temp;

        let safeValue = typeof value === "string" ? `"${value}"` : value;
        if (typeof value === "object") safeValue = JSON.stringify(value).replace(/'/g, "'\\''");

        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -s '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `jq '. + {"${key}": ${safeValue}}' '${settingsJsonPath}' > '${settingsJsonPath}.tmp' 2>/dev/null && ` +
                  `jq -e . '${settingsJsonPath}.tmp' > /dev/null 2>&1 && ` +
                  `cp '${settingsJsonPath}.tmp' '${settingsJsonPath}' && rm -f '${settingsJsonPath}.tmp'`;
        sh(cmd);
    }

    function updateJsonBulk(dataObj) {
        let jsonStr = JSON.stringify(dataObj).replace(/'/g, "'\\''");
        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -s '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `jq '. + ${jsonStr}' '${settingsJsonPath}' > '${settingsJsonPath}.tmp' 2>/dev/null && ` +
                  `jq -e . '${settingsJsonPath}.tmp' > /dev/null 2>&1 && ` +
                  `cp '${settingsJsonPath}.tmp' '${settingsJsonPath}' && rm -f '${settingsJsonPath}.tmp'`;
        sh(cmd);
        
        let temp = Object.assign({}, rawSettings);
        for (let key in dataObj) {
            temp[key] = dataObj[key];
        }
        rawSettings = temp;
    }

    FileView {
        id: settingsWatcher
        path: config.settingsJsonPath
        watchChanges: true
        onFileChanged: reload()
        
        onLoaded: {
            try {
                let raw = typeof text === "function" ? text() : text;
                if (typeof raw === "string") {
                    let trimmed = raw.trim();
                    if (trimmed.length > 0) {
                        config.rawSettings = JSON.parse(trimmed);
                    }
                }
            } catch (e) {
            }
            config.settingsLoaded();
            config.dataReady = true;
        }
    }

    Component.onCompleted: {
        if (settingsWatcher.path) {
            settingsWatcher.reload();
        }
    }
}
