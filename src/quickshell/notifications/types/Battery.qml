import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../"
import "../../reusables"
import "../"

Notification {
    id: faceRoot

    fullSummary: model ? (model.summary || "Battery") : "Battery"
    fullBody: model && model.body !== "" ? model.body : ""

    readonly property int urgencyLevel: model && typeof model.urgency !== "undefined" ? model.urgency : 1

    readonly property string batIcon: {
        let ic = model ? (model.icon || "") : "";
        if (ic === "battery-full-charged") return "󰂄";
        if (ic === "battery-level-0-symbolic" || faceRoot.urgencyLevel === 2) return "󰂃";
        if (ic === "battery-level-20-symbolic") return "󰁺";
        return "󰁹";
    }

    accentColor: {
        let ic = model ? (model.icon || "") : "";
        if (ic === "battery-full-charged") return ThemeBackend.green;
        if (faceRoot.urgencyLevel === 2 || ic === "battery-level-0-symbolic") return ThemeBackend.red;
        if (ic === "battery-level-20-symbolic") return ThemeBackend.peach;
        return ThemeBackend.teal;
    }

    iconArea: [
        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(faceRoot.accentColor, 0.15)
            }

            Text {
                anchors.centerIn: parent
                text: faceRoot.batIcon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: s(22)
                color: faceRoot.accentColor
            }
        }
    ]

    headerArea: [
        Text {
            Layout.fillWidth: true
            text: model ? (model.displayName || model.appName || "Battery") : "Battery"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: s(11)
            color: ThemeBackend.subtext0
            elide: Text.ElideRight
        }
    ]
}
