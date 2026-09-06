pragma Singleton
import QtQuick

QtObject {
    id: root

    property bool isActive: false
    property string timeFormatted: ""
    property string icon: "\uF017"
    property string colorType: "mauve"
}
