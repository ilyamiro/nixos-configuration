import QtQuick
import Quickshell
import "../"

FilePicker {
    id: imagePickerRoot

    width: Scaler.s(1180)
    previewWidth: Scaler.s(440)
    titleText: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.title") : "Choose image"
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif"]
    showPreview: true
    
    places: [
        { name: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.places.home") : "Home", icon: "󰋜", path: "file://" + (Quickshell.env("HOME") || "") },
        { name: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.places.downloads") : "Downloads", icon: "󰇚", path: "file://" + (Quickshell.env("HOME") || "") + "/Downloads" },
        { name: typeof I18n !== "undefined" ? I18n.t("guide.file_picker.places.pictures") : "Pictures", icon: "󰋩", path: "file://" + (Quickshell.env("HOME") || "") + "/Pictures" }
    ]

    property bool showCircleMask: false
    signal imageSelected(string filePath, string fileName)

    onFileSelected: function(filePath, fileName) {
        imagePickerRoot.imageSelected(filePath, fileName);
    }

    function openPicker(initialPath, circleMask) {
        if (circleMask !== undefined) {
            showCircleMask = Boolean(circleMask);
        }
        openWithOptionalPath(initialPath);
    }

    previewComponent: Component {
        Item {
            anchors.fill: parent

            Rectangle {
                property real side: Math.min(parent.width, parent.height)
                width: side
                height: side
                anchors.centerIn: parent
                color: ThemeBackend.surface0
                radius: imagePickerRoot.showCircleMask ? (side / 2) : imagePickerRoot.crMedium
                clip: true

                AnimatedImage {
                    anchors.fill: parent
                    source: imagePickerRoot.selectedFilePath !== "" ? "file://" + imagePickerRoot.selectedFilePath : ""
                    fillMode: imagePickerRoot.showCircleMask ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    playing: true
                }

                Canvas {
                    anchors.fill: parent
                    visible: imagePickerRoot.showCircleMask
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        if (width <= 0 || height <= 0) return;
                        ctx.fillStyle = Qt.alpha(ThemeBackend.crust, 0.7);
                        ctx.fillRect(0, 0, width, height);
                        ctx.globalCompositeOperation = "destination-out";
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }
            }
        }
    }
}
