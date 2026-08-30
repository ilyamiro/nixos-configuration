import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../singletons"
import "../singletons/widgetcontrols"

Item {
    id: window
    focus: true

    function s(val) {
        return (typeof Scaler !== "undefined" && Scaler.s) ? Scaler.s(val) : val;
    }

    property real introMain: 0.0
    property real introHeader: 0.0
    property real introContent: 0.0

    ParallelAnimation {
        id: introAnim
        NumberAnimation { target: window; property: "introMain"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
        NumberAnimation { target: window; property: "introHeader"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutBack }
        NumberAnimation { target: window; property: "introContent"; from: 0.0; to: 1.0; duration: 350; easing.type: Easing.OutQuint }
    }

    function gotoTab(arg) {
        if (typeof arg === "string" && arg.trim() !== "") {
            srcTextArea.text = arg.trim();
            TranslatorController.requestTranslate(srcTextArea.text, TranslatorController.sourceLang, TranslatorController.targetLang);
        }
    }

    function resetAndPlayIntro() {
        introMain = 0;
        introHeader = 0;
        introContent = 0;
        introAnim.restart();
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus();
            resetAndPlayIntro();
            srcTextArea.forceActiveFocus();
            if (srcTextArea.text === "" && TranslatorController.currentInput !== "") {
                srcTextArea.text = TranslatorController.currentInput;
            }
        } else {
            introAnim.stop();
        }
    }

    Component.onCompleted: {
        if (visible) {
            forceActiveFocus();
            resetAndPlayIntro();
            srcTextArea.forceActiveFocus();
            if (srcTextArea.text === "" && TranslatorController.currentInput !== "") {
                srcTextArea.text = TranslatorController.currentInput;
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            TranslatorController.requestTranslate(srcTextArea.text, TranslatorController.sourceLang, TranslatorController.targetLang);
        }
    }

    property var langNames: {
        let list = [];
        for (let i = 0; i < TranslatorController.languagesList.length; i++) {
            let item = TranslatorController.languagesList[i];
            list.push("\u200E" + item.native + " (" + item.code + ")");
        }
        return list;
    }

    property var langCodes: {
        let list = [];
        for (let i = 0; i < TranslatorController.languagesList.length; i++) {
            list.push(TranslatorController.languagesList[i].code);
        }
        return list;
    }

    function getIndexForCode(code) {
        for (let i = 0; i < langCodes.length; i++) {
            if (langCodes[i] === code) return i;
        }
        return 0;
    }

    Rectangle {
        id: bgCard
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: ThemeBackend.base
        border.color: ThemeBackend.surface0
        border.width: 1

        opacity: introMain
        scale: 0.96 + (0.04 * introMain)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: window.s(16)
            spacing: window.s(12)

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: window.s(10)
                opacity: introHeader
                transform: Translate { y: window.s(10) * (1.0 - introHeader) }

                Rectangle {
                    Layout.preferredWidth: window.s(36)
                    Layout.preferredHeight: window.s(36)
                    radius: window.s(10)
                    color: Qt.alpha(ThemeBackend.mauve, 0.2)
                    border.color: Qt.alpha(ThemeBackend.mauve, 0.4)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰗊"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(20)
                        color: ThemeBackend.mauve
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(8)

                    Text {
                        text: I18n.t("translator.title", "Translator")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(16)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Text {
                        visible: TranslatorController.isTranslating || TranslatorController.elapsedMs > 0
                        text: TranslatorController.isTranslating 
                              ? I18n.t("translator.status_translating", "Translating...")
                              : (TranslatorController.elapsedMs + " ms")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(11)
                        color: TranslatorController.isTranslating ? ThemeBackend.mauve : ThemeBackend.subtext0
                    }
                }

                // Source Language Selector
                Dropdown {
                    id: srcLangDropdown
                    Layout.preferredWidth: window.s(150)
                    implicitHeight: window.s(32)
                    options: window.langNames
                    currentIndex: window.getIndexForCode(TranslatorController.sourceLang)
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface0
                    dropdownColor: ThemeBackend.surface0
                    borderColor: ThemeBackend.surface1
                    hoverColor: ThemeBackend.surface1
                    textColor: ThemeBackend.text
                    activeTextColor: ThemeBackend.crust
                    subTextColor: ThemeBackend.subtext0
                    cornerRadius: window.s(8)
                    onSelected: function(idx, val) {
                        if (idx >= 0 && idx < window.langCodes.length) {
                            TranslatorController.setSourceLang(window.langCodes[idx]);
                        }
                    }
                }

                // Swap Languages Button
                IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: window.s(32)
                    implicitHeight: window.s(32)
                    cornerRadius: window.s(8)
                    buttonIcon: "󰁯"
                    iconFontSize: window.s(15)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.mauve
                    onClicked: {
                        TranslatorController.swapLanguages();
                    }
                }

                // Target Language Selector
                Dropdown {
                    id: dstLangDropdown
                    Layout.preferredWidth: window.s(150)
                    implicitHeight: window.s(32)
                    options: window.langNames.slice(1) // Skip "Auto Detect" for target
                    currentIndex: Math.max(0, window.getIndexForCode(TranslatorController.targetLang) - 1)
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface0
                    dropdownColor: ThemeBackend.surface0
                    borderColor: ThemeBackend.surface1
                    hoverColor: ThemeBackend.surface1
                    textColor: ThemeBackend.text
                    activeTextColor: ThemeBackend.crust
                    subTextColor: ThemeBackend.subtext0
                    cornerRadius: window.s(8)
                    onSelected: function(idx, val) {
                        let actualIdx = idx + 1;
                        if (actualIdx >= 0 && actualIdx < window.langCodes.length) {
                            TranslatorController.setTargetLang(window.langCodes[actualIdx]);
                        }
                    }
                }

                // Close / ESC Indicator Button
                IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: window.s(32)
                    implicitHeight: window.s(32)
                    cornerRadius: window.s(8)
                    buttonIcon: "󰅖"
                    iconFontSize: window.s(14)
                    accentColor: Qt.alpha(ThemeBackend.red, 0.15)
                    textColor: ThemeBackend.red
                    onClicked: {
                        Quickshell.execDetached(["serpantinum", "msg", "close"]);
                    }
                }
            }

            // Split View: Input Box (Left) ⇄ Output Box (Right)
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: window.s(12)
                opacity: introContent

                // Left Panel: Source Text Area
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0
                    border.color: srcTextArea.activeFocus ? ThemeBackend.mauve : ThemeBackend.surface1
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(12)
                        spacing: window.s(8)

                        // Top bar inside input area
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: window.s(6)

                            Text {
                                text: TranslatorController.detectedSourceLang !== "" 
                                      ? (I18n.t("translator.detected", "Detected: ") + TranslatorController.getLanguageName(TranslatorController.detectedSourceLang))
                                      : I18n.t("translator.input_label", "Source Text")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(11)
                                font.weight: Font.DemiBold
                                color: ThemeBackend.subtext0
                            }

                            Item { Layout.fillWidth: true }

                            // Paste from clipboard button
                            IconButton {
                                implicitWidth: window.s(26)
                                implicitHeight: window.s(26)
                                cornerRadius: window.s(6)
                                buttonIcon: "󰅌"
                                iconFontSize: window.s(12)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.subtext0
                                onClicked: {
                                    pasteProc.running = true;
                                }
                            }

                            // Clear text button
                            IconButton {
                                implicitWidth: window.s(26)
                                implicitHeight: window.s(26)
                                cornerRadius: window.s(6)
                                buttonIcon: "󰅖"
                                iconFontSize: window.s(11)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.subtext0
                                visible: srcTextArea.text.length > 0
                                onClicked: {
                                    srcTextArea.text = "";
                                    TranslatorController.requestTranslate("", TranslatorController.sourceLang, TranslatorController.targetLang);
                                    srcTextArea.forceActiveFocus();
                                }
                            }
                        }

                        // Scrollable Input Text
                        Flickable {
                            id: srcFlickable
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: srcTextArea.implicitHeight
                            clip: true

                            TextArea.flickable: TextArea {
                                id: srcTextArea
                                width: srcFlickable.width
                                wrapMode: Text.WordWrap
                                placeholderText: I18n.t("translator.placeholder", "Type, paste, or speak text here...")
                                placeholderTextColor: Qt.alpha(ThemeBackend.subtext0, 0.4)
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(13)
                                padding: 0
                                background: null
                                selectByMouse: true

                                onTextChanged: {
                                    TranslatorController.currentInput = text;
                                    debounceTimer.restart();
                                }
                            }
                        }

                        // Character Count
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: srcTextArea.text.length + " " + I18n.t("translator.chars", "chars")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(10)
                                color: Qt.alpha(ThemeBackend.subtext0, 0.6)
                            }
                        }
                    }
                }

                // Right Panel: Translated Result
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.surface0
                    border.color: ThemeBackend.surface1
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(12)
                        spacing: window.s(8)

                        // Top Bar inside result
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: window.s(6)

                            Text {
                                text: I18n.t("translator.translation_label", "Translation") + " (" + TranslatorController.getLanguageName(TranslatorController.targetLang) + ")"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(11)
                                font.weight: Font.DemiBold
                                color: ThemeBackend.mauve
                            }

                            Item { Layout.fillWidth: true }

                            // TTS Listen Button
                            IconButton {
                                implicitWidth: window.s(26)
                                implicitHeight: window.s(26)
                                cornerRadius: window.s(6)
                                buttonIcon: "󰕾"
                                iconFontSize: window.s(13)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.subtext0
                                visible: TranslatorController.currentTranslation.length > 0
                                onClicked: {
                                    TranslatorController.speakText(TranslatorController.currentTranslation, TranslatorController.targetLang);
                                }
                            }

                            // Copy Button
                            IconButton {
                                id: copyBtn
                                property bool justCopied: false
                                implicitWidth: window.s(26)
                                implicitHeight: window.s(26)
                                cornerRadius: window.s(6)
                                buttonIcon: justCopied ? "󰄬" : "󰆏"
                                iconFontSize: window.s(13)
                                accentColor: justCopied ? Qt.alpha(ThemeBackend.green, 0.2) : ThemeBackend.surface1
                                textColor: justCopied ? ThemeBackend.green : ThemeBackend.mauve
                                visible: TranslatorController.currentTranslation.length > 0
                                onClicked: {
                                    TranslatorController.copyToClipboard(TranslatorController.currentTranslation);
                                    justCopied = true;
                                    copiedResetTimer.restart();
                                }

                                Timer {
                                    id: copiedResetTimer
                                    interval: 1500
                                    onTriggered: copyBtn.justCopied = false
                                }
                            }
                        }

                        // Scrollable Translated Text
                        Flickable {
                            id: dstFlickable
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: dstTextCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: dstTextCol
                                width: dstFlickable.width
                                spacing: window.s(6)

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: TranslatorController.currentTranslation !== "" 
                                          ? TranslatorController.currentTranslation 
                                          : (srcTextArea.text.trim() === "" ? I18n.t("translator.empty_prompt", "Translation will appear here instantly...") : "")
                                    color: TranslatorController.currentTranslation !== "" ? ThemeBackend.text : Qt.alpha(ThemeBackend.subtext0, 0.4)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(14)
                                    font.weight: Font.DemiBold
                                }

                                // Transliteration / Pronunciation
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: TranslatorController.transliteration !== "" ? ("[" + TranslatorController.transliteration + "]") : ""
                                    visible: text !== ""
                                    color: ThemeBackend.subtext0
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(11)
                                    font.italic: true
                                }

                                // Synonyms List
                                Repeater {
                                    model: TranslatorController.synonyms
                                    delegate: ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(2)
                                        Layout.topMargin: window.s(4)

                                        Text {
                                            text: modelData.part_of_speech || ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: window.s(10)
                                            font.weight: Font.Bold
                                            color: ThemeBackend.mauve
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: Array.isArray(modelData.meanings) ? modelData.meanings.join(", ") : ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: window.s(11)
                                            color: ThemeBackend.subtext0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Bottom History Shelf
            RowLayout {
                Layout.fillWidth: true
                spacing: window.s(8)
                visible: TranslatorController.history.length > 0

                Text {
                    text: "󰋚 " + I18n.t("translator.recent", "Recent:")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: window.s(10)
                    color: ThemeBackend.subtext0
                }

                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: window.s(26)
                    contentWidth: historyRow.implicitWidth
                    clip: true

                    RowLayout {
                        id: historyRow
                        spacing: window.s(6)

                        Repeater {
                            model: TranslatorController.history.slice(0, 6)
                            delegate: Rectangle {
                                implicitWidth: historyItemText.implicitWidth + window.s(16)
                                implicitHeight: window.s(24)
                                radius: window.s(6)
                                color: historyMa.containsMouse ? ThemeBackend.surface1 : Qt.alpha(ThemeBackend.surface0, 0.8)
                                border.color: Qt.alpha(ThemeBackend.surface2, 0.4)
                                border.width: 1

                                Text {
                                    id: historyItemText
                                    anchors.centerIn: parent
                                    text: modelData.original
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(10)
                                    color: historyMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: historyMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        srcTextArea.text = modelData.original;
                                        TranslatorController.requestTranslate(modelData.original, modelData.src || "auto", modelData.dst || TranslatorController.targetLang);
                                    }
                                }
                            }
                        }
                    }
                }

                // Clear history button
                IconButton {
                    implicitWidth: window.s(22)
                    implicitHeight: window.s(22)
                    cornerRadius: window.s(4)
                    buttonIcon: "󰅖"
                    iconFontSize: window.s(9)
                    accentColor: Qt.alpha(ThemeBackend.surface1, 0.5)
                    textColor: ThemeBackend.subtext0
                    onClicked: TranslatorController.clearHistory()
                }
            }
        }
    }

    // Process to grab clipboard text on demand
    Process {
        id: pasteProc
        command: ["bash", "-c", "wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || true"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim() !== "") {
                    srcTextArea.text = data.trim();
                }
            }
        }
    }
}
