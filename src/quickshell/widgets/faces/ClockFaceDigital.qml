import QtQuick
import QtQuick.Layouts
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 120
    property real minHeight: 120
    property real maxWidth: 800
    property real maxHeight: 800
    property real minAspect: 0.8
    property real maxAspect: 2.8
    property bool isRound: false

    readonly property bool isStacked: (width / height) < 1.25

    Rectangle {
        id: bgContainer
        anchors.fill: parent
        color: ThemeBackend.surfaceVariant ?? ThemeBackend.surface0
        radius: ThemeBackend.borderRadius
        antialiasing: true

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Math.min(parent.width, parent.height) * 0.08
            width: Math.min(parent.width, parent.height) * 0.55
            height: width
            radius: width * 0.4
            color: ThemeBackend.primaryContainer ?? ThemeBackend.surface1
            opacity: 0.45
            antialiasing: true
        }

        Item {
            anchors.fill: parent
            anchors.margins: Math.min(parent.width, parent.height) * 0.12

            ColumnLayout {
                visible: root.isStacked
                anchors.fill: parent
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: DateTime.hour
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Normal
                    color: ThemeBackend.onSurface ?? ThemeBackend.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: DateTime.minute
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Black
                    color: ThemeBackend.primary ?? ThemeBackend.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    implicitWidth: Math.max(dateLabelStacked.implicitWidth + 16, 40)
                    implicitHeight: Math.max(dateLabelStacked.implicitHeight + 8, 20)
                    radius: height / 2
                    color: ThemeBackend.secondaryContainer ?? ThemeBackend.surface2

                    Text {
                        id: dateLabelStacked
                        anchors.centerIn: parent
                        text: DateTime.dateBadge
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                        color: ThemeBackend.onSecondaryContainer ?? ThemeBackend.subtext0
                    }
                }
            }

            RowLayout {
                visible: !root.isStacked
                anchors.fill: parent
                spacing: Math.min(parent.width, parent.height) * 0.04

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: DateTime.time
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    font.weight: Font.Black
                    color: ThemeBackend.primary ?? ThemeBackend.text
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.max(dateLabelWide.implicitWidth + 20, 48)
                    implicitHeight: Math.max(dateLabelWide.implicitHeight + 10, 26)
                    radius: height / 2
                    color: ThemeBackend.secondaryContainer ?? ThemeBackend.surface2

                    Text {
                        id: dateLabelWide
                        anchors.centerIn: parent
                        text: DateTime.dateBadge
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        color: ThemeBackend.onSecondaryContainer ?? ThemeBackend.subtext0
                    }
                }
            }
        }
    }
}
