import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../reusables"
import "../singletons"
import "../singletons/widgetcontrols"

PanelWindow {
    id: selWin

    WlrLayershell.namespace: "qs-translator-selection"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function s(val) {
        return (typeof Scaler !== "undefined" && Scaler.s) ? Scaler.s(val) : val;
    }

    property bool isVisible: TranslatorController.selectionVisible
    property real animProgress: isVisible ? 1.0 : 0.0

    Behavior on animProgress {
        NumberAnimation {
            duration: selWin.isVisible ? 220 : 150
            easing.type: selWin.isVisible ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: 1.1
        }
    }

    visible: isVisible || animProgress > 0.001

    mask: Region {
        item: (selWin.isVisible || selWin.animProgress > 0.001) ? fullScreenLayer : null
    }

    Item {
        id: fullScreenLayer
        anchors.fill: parent

        // Click outside dismiss handler
        MouseArea {
            anchors.fill: parent
            enabled: selWin.isVisible
            onClicked: TranslatorController.hideSelection()
        }

        // Auto-dismiss timer after 15 seconds
        Timer {
            id: autoDismissTimer
            interval: 15000
            repeat: false
            running: selWin.isVisible
            onTriggered: TranslatorController.hideSelection()
        }

        // Dismiss on Escape
        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            enabled: selWin.isVisible
            onActivated: TranslatorController.hideSelection()
        }

        // Floating HUD Card positioned near cursor
        Rectangle {
            id: hudCard
            width: Math.min(selWin.s(420), selWin.width - selWin.s(32))
            implicitHeight: cardCol.implicitHeight + selWin.s(24)
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface0
            border.width: 1

            // Position calculation near cursor with boundary clamping
            x: {
                let targetX = TranslatorController.cursorX + selWin.s(16);
                if (targetX + width > selWin.width - selWin.s(16)) {
                    targetX = TranslatorController.cursorX - width - selWin.s(16);
                }
                return Math.max(selWin.s(16), Math.min(selWin.width - width - selWin.s(16), targetX));
            }

            y: {
                let targetY = TranslatorController.cursorY + selWin.s(16);
                if (targetY + height > selWin.height - selWin.s(16)) {
                    targetY = TranslatorController.cursorY - height - selWin.s(16);
                }
                return Math.max(selWin.s(16), Math.min(selWin.height - height - selWin.s(16), targetY));
            }

            opacity: selWin.animProgress
            scale: 0.85 + (0.15 * selWin.animProgress)

            // Prevent clicks on the card itself from triggering the outside dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: selWin.s(12)
                spacing: selWin.s(8)

                // Header Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: selWin.s(8)

                    Rectangle {
                        Layout.preferredWidth: selWin.s(22)
                        Layout.preferredHeight: selWin.s(22)
                        radius: selWin.s(6)
                        color: Qt.alpha(ThemeBackend.mauve, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰗊"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: selWin.s(12)
                            color: ThemeBackend.mauve
                        }
                    }

                    Text {
                        text: (TranslatorController.selectionDetectedLang !== "" 
                              ? TranslatorController.getLanguageName(TranslatorController.selectionDetectedLang)
                              : "Auto") + " 󰁔 " + TranslatorController.getLanguageName(TranslatorController.targetLang)
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: selWin.s(11)
                        font.weight: Font.DemiBold
                        color: ThemeBackend.text
                    }

                    Item { Layout.fillWidth: true }

                    // Open in Full Translator Window
                    IconButton {
                        implicitWidth: selWin.s(24)
                        implicitHeight: selWin.s(24)
                        cornerRadius: selWin.s(6)
                        buttonIcon: "󰍉"
                        iconFontSize: selWin.s(11)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.subtext0
                        onClicked: {
                            let txt = TranslatorController.selectionText;
                            TranslatorController.hideSelection();
                            Quickshell.execDetached(["serpantinum", "msg", "open", "translator", txt]);
                        }
                    }

                    // Close Button
                    IconButton {
                        implicitWidth: selWin.s(24)
                        implicitHeight: selWin.s(24)
                        cornerRadius: selWin.s(6)
                        buttonIcon: "󰅖"
                        iconFontSize: selWin.s(10)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.subtext0
                        onClicked: TranslatorController.hideSelection()
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ThemeBackend.surface1
                }

                // Original Text Snippet
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: TranslatorController.selectionText
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: selWin.s(11)
                    color: ThemeBackend.subtext0
                }

                // Translated Result Box
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: resCol.implicitHeight + selWin.s(16)
                    radius: selWin.s(8)
                    color: ThemeBackend.surface0
                    border.color: ThemeBackend.surface1
                    border.width: 1

                    ColumnLayout {
                        id: resCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: selWin.s(8)
                        spacing: selWin.s(4)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: selWin.s(6)

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: TranslatorController.selectionLoading 
                                      ? I18n.t("translator.status_translating", "Translating...")
                                      : (TranslatorController.selectionResult !== "" ? TranslatorController.selectionResult : I18n.t("translator.failed", "No translation available"))
                                color: TranslatorController.selectionLoading ? ThemeBackend.subtext0 : ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: selWin.s(13)
                                font.weight: Font.DemiBold
                            }

                            // Copy Action
                            IconButton {
                                id: hudCopyBtn
                                property bool justCopied: false
                                implicitWidth: selWin.s(26)
                                implicitHeight: selWin.s(26)
                                cornerRadius: selWin.s(6)
                                buttonIcon: justCopied ? "󰄬" : "󰆏"
                                iconFontSize: selWin.s(12)
                                accentColor: justCopied ? Qt.alpha(ThemeBackend.green, 0.2) : ThemeBackend.surface1
                                textColor: justCopied ? ThemeBackend.green : ThemeBackend.mauve
                                visible: !TranslatorController.selectionLoading && TranslatorController.selectionResult !== ""
                                onClicked: {
                                    TranslatorController.copyToClipboard(TranslatorController.selectionResult);
                                    justCopied = true;
                                    hudCopiedTimer.restart();
                                }

                                Timer {
                                    id: hudCopiedTimer
                                    interval: 1200
                                    onTriggered: hudCopyBtn.justCopied = false
                                }
                            }

                            // Speak Action
                            IconButton {
                                implicitWidth: selWin.s(26)
                                implicitHeight: selWin.s(26)
                                cornerRadius: selWin.s(6)
                                buttonIcon: "󰕾"
                                iconFontSize: selWin.s(12)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.subtext0
                                visible: !TranslatorController.selectionLoading && TranslatorController.selectionResult !== ""
                                onClicked: {
                                    TranslatorController.speakText(TranslatorController.selectionResult, TranslatorController.targetLang);
                                }
                            }
                        }

                        // Transliteration
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: TranslatorController.selectionTranslit !== "" ? ("[" + TranslatorController.selectionTranslit + "]") : ""
                            visible: text !== ""
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: selWin.s(10)
                            font.italic: true
                        }
                    }
                }
            }
        }
    }
}
