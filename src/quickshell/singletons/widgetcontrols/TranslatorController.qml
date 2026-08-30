pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../singletons"

Item {
    id: controller

    property var languagesList: [
        { code: "auto", name: "Auto Detect", native: "Автоопределение" },
        { code: "ru", name: "Russian", native: "Русский" },
        { code: "en", name: "English", native: "English" },
        { code: "de", name: "German", native: "Deutsch" },
        { code: "es", name: "Spanish", native: "Español" },
        { code: "fr", name: "French", native: "Français" },
        { code: "it", name: "Italian", native: "Italiano" },
        { code: "zh", name: "Chinese", native: "中文" },
        { code: "ja", name: "Japanese", native: "日本語" },
        { code: "ko", name: "Korean", native: "한국어" },
        { code: "uk", name: "Ukrainian", native: "Українська" },
        { code: "pl", name: "Polish", native: "Polski" },
        { code: "tr", name: "Turkish", native: "Türkçe" },
        { code: "pt", name: "Portuguese", native: "Português" },
        { code: "nl", name: "Dutch", native: "Nederlands" },
        { code: "ar", name: "Arabic", native: "العربية" },
        { code: "hi", name: "Hindi", native: "हिन्दी" },
        { code: "cs", name: "Czech", native: "Čeština" },
        { code: "sv", name: "Swedish", native: "Svenska" },
        { code: "el", name: "Greek", native: "Ελληνικά" },
        { code: "he", name: "Hebrew", native: "עברית" },
        { code: "id", name: "Indonesian", native: "Bahasa Indonesia" },
        { code: "vi", name: "Vietnamese", native: "Tiếng Việt" },
        { code: "fi", name: "Finnish", native: "Suomi" },
        { code: "no", name: "Norwegian", native: "Norsk" },
        { code: "da", name: "Danish", native: "Dansk" },
        { code: "hu", name: "Hungarian", native: "Magyar" },
        { code: "ro", name: "Romanian", native: "Română" },
        { code: "bg", name: "Bulgarian", native: "Български" },
        { code: "sr", name: "Serbian", native: "Српски" },
        { code: "sk", name: "Slovak", native: "Slovenčina" },
        { code: "be", name: "Belarusian", native: "Беларуская" },
        { code: "kk", name: "Kazakh", native: "Қазақша" },
        { code: "ka", name: "Georgian", native: "ქართული" },
        { code: "hy", name: "Armenian", native: "Հայերեն" },
        { code: "az", name: "Azerbaijani", native: "Azərbaycan" },
        { code: "uz", name: "Uzbek", native: "Oʻzbekcha" }
    ]

    property var defaultSettings: ({
        "sourceLang": "auto",
        "targetLang": "ru",
        "autoCopy": false,
        "history": []
    })

    property var settings: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.translator) ? Config.rawSettings.translator : defaultSettings
    property string sourceLang: settings.sourceLang || "auto"
    property string targetLang: settings.targetLang || (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general && Config.rawSettings.general.language ? Config.rawSettings.general.language : "ru")
    property bool autoCopy: settings.autoCopy || false
    property var history: settings.history || []

    property bool isTranslating: false
    property string currentInput: ""
    property string currentTranslation: ""
    property string detectedSourceLang: ""
    property string transliteration: ""
    property var synonyms: []
    property int elapsedMs: 0

    // Selection HUD State
    property bool selectionVisible: false
    property string selectionText: ""
    property string selectionResult: ""
    property string selectionDetectedLang: ""
    property string selectionTranslit: ""
    property var selectionSynonyms: []
    property bool selectionLoading: false
    property real cursorX: 0
    property real cursorY: 0
    property var targetScreen: null

    function setSourceLang(code) {
        if (!code) return;
        sourceLang = code;
        saveSettings();
        if (currentInput.trim() !== "") {
            requestTranslate(currentInput, sourceLang, targetLang);
        }
    }

    function setTargetLang(code) {
        if (!code) return;
        targetLang = code;
        saveSettings();
        if (currentInput.trim() !== "") {
            requestTranslate(currentInput, sourceLang, targetLang);
        }
    }

    function swapLanguages() {
        if (sourceLang === "auto") {
            let actualSrc = detectedSourceLang !== "" ? detectedSourceLang : "en";
            sourceLang = targetLang;
            targetLang = actualSrc;
        } else {
            let tmp = sourceLang;
            sourceLang = targetLang;
            targetLang = tmp;
        }
        saveSettings();
        if (currentInput.trim() !== "") {
            requestTranslate(currentInput, sourceLang, targetLang);
        }
    }

    function saveSettings() {
        let current = Object.assign({}, defaultSettings, settings);
        current.sourceLang = controller.sourceLang;
        current.targetLang = controller.targetLang;
        current.autoCopy = controller.autoCopy;
        current.history = controller.history;
        if (typeof Config !== "undefined") {
            Config.setSetting("translator", current);
        }
    }

    function getLanguageName(code) {
        if (!code) return "";
        for (let i = 0; i < languagesList.length; i++) {
            if (languagesList[i].code === code) {
                return languagesList[i].native || languagesList[i].name;
            }
        }
        return code.toUpperCase();
    }

    function addToHistory(original, translated, src, dst) {
        if (!original || !translated) return;
        let item = {
            "id": "h_" + Date.now(),
            "original": original.trim(),
            "translated": translated.trim(),
            "src": src,
            "dst": dst,
            "time": Date.now()
        };
        let list = [item];
        for (let i = 0; i < controller.history.length; i++) {
            if (controller.history[i].original !== item.original && list.length < 20) {
                list.push(controller.history[i]);
            }
        }
        controller.history = list;
        saveSettings();
    }

    function clearHistory() {
        controller.history = [];
        saveSettings();
    }

    function copyToClipboard(text) {
        if (!text) return;
        Quickshell.execDetached(["bash", "-c", "printf '%s' " + JSON.stringify(text) + " | wl-copy 2>/dev/null || true"]);
        if (typeof Sounds !== "undefined") {
            Sounds.playSfx("reusables/button/click.wav");
        }
    }

    function speakText(text, lang) {
        if (!text) return;
        let l = lang || targetLang || "ru";
        let scriptPath = Quickshell.env("SERPANTINUM_DIR") ? (Quickshell.env("SERPANTINUM_DIR") + "/scripts/translate.py") : "/home/spinty/.local/share/serpantinum/src/scripts/translate.py";
        Quickshell.execDetached(["python3", scriptPath, "--speak", "--to", l, "--text", text]);
    }

    // Process for Main Window Translation
    Process {
        id: mainTransProc
        property string targetReqText: ""
        property string targetDst: ""
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                let trimmed = (data || "").trim();
                if (!trimmed) {
                    controller.isTranslating = false;
                    return;
                }
                try {
                    let parsed = JSON.parse(trimmed);
                    if (parsed && parsed.success) {
                        controller.currentTranslation = parsed.translated_text || "";
                        controller.detectedSourceLang = parsed.detected_lang || "";
                        controller.transliteration = parsed.transliteration || "";
                        controller.synonyms = parsed.synonyms || [];
                        controller.elapsedMs = parsed.elapsed_ms || 0;
                        controller.isTranslating = false;
                        controller.addToHistory(mainTransProc.targetReqText, parsed.translated_text, parsed.detected_lang, mainTransProc.targetDst);
                    } else {
                        controller.isTranslating = false;
                    }
                } catch (e) {
                    controller.isTranslating = false;
                }
            }
        }
    }

    // Process for Selection HUD Translation
    Process {
        id: selTransProc
        property string targetReqText: ""
        property string targetDst: ""
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                let trimmed = (data || "").trim();
                if (!trimmed) {
                    controller.selectionLoading = false;
                    return;
                }
                try {
                    let parsed = JSON.parse(trimmed);
                    if (parsed && parsed.success) {
                        controller.selectionResult = parsed.translated_text || "";
                        controller.selectionDetectedLang = parsed.detected_lang || "";
                        controller.selectionTranslit = parsed.transliteration || "";
                        controller.selectionSynonyms = parsed.synonyms || [];
                        controller.selectionLoading = false;
                    } else {
                        controller.selectionResult = "";
                        controller.selectionLoading = false;
                    }
                } catch (e) {
                    controller.selectionResult = "";
                    controller.selectionLoading = false;
                }
            }
        }
    }

    function requestTranslate(text, src, dst) {
        let clean = (text || "").trim();
        if (!clean) {
            currentTranslation = "";
            detectedSourceLang = "";
            transliteration = "";
            synonyms = [];
            isTranslating = false;
            return;
        }

        mainTransProc.targetReqText = clean;
        mainTransProc.targetDst = dst || targetLang;

        let scriptPath = Quickshell.env("SERPANTINUM_DIR") ? (Quickshell.env("SERPANTINUM_DIR") + "/scripts/translate.py") : "/home/spinty/.local/share/serpantinum/src/scripts/translate.py";
        mainTransProc.running = false;
        mainTransProc.command = [
            "python3",
            scriptPath,
            "--text", clean,
            "--from", src || sourceLang,
            "--to", mainTransProc.targetDst,
            "--json"
        ];
        isTranslating = true;
        mainTransProc.running = true;
    }

    function showSelection(text, cursorCoordsStr) {
        let clean = (text || "").trim();
        if (!clean) return;

        selectionText = clean;
        selectionResult = "";
        selectionDetectedLang = "";
        selectionTranslit = "";
        selectionSynonyms = [];

        let curX = 100;
        let curY = 100;
        if (cursorCoordsStr && cursorCoordsStr.includes(",")) {
            let parts = cursorCoordsStr.split(",");
            curX = parseInt(parts[0]) || 100;
            curY = parseInt(parts[1]) || 100;
        }
        cursorX = curX;
        cursorY = curY;

        selectionVisible = true;

        selTransProc.targetReqText = clean;
        selTransProc.targetDst = targetLang;

        let scriptPath = Quickshell.env("SERPANTINUM_DIR") ? (Quickshell.env("SERPANTINUM_DIR") + "/scripts/translate.py") : "/home/spinty/.local/share/serpantinum/src/scripts/translate.py";
        selTransProc.running = false;
        selTransProc.command = [
            "python3",
            scriptPath,
            "--text", clean,
            "--from", sourceLang,
            "--to", targetLang,
            "--json"
        ];
        selectionLoading = true;
        selTransProc.running = true;
    }

    function hideSelection() {
        selectionVisible = false;
        selectionLoading = false;
    }
}
