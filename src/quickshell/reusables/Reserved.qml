import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"

Item {
    id: root
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    property real imageSize: 220
    property real textSize: 15
    property real spacing: 16
    property string text: I18n.t("notifications.center.reserved")
    property string imageSource: ""

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: root.spacing

        ImageBox {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.imageSize
            Layout.preferredHeight: root.imageSize
            source: root.imageSource !== "" ? root.imageSource : (Caching.serpantinumDir ? ("file://" + Caching.serpantinumDir + "/assets/pushy2.gif") : Qt.resolvedUrl("../assets/pushy2.gif"))
            isGif: true
            playing: true
            fillMode: Image.PreserveAspectFit
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.textSize
            color: ThemeBackend.subtext0
        }
    }
}
