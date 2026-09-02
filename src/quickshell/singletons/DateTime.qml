pragma Singleton
import QtQuick
import Quickshell
import "../"

Item {
    id: root

    property var now: new Date()

    readonly property string timeFormat: {
        if (typeof Config !== "undefined" && Config.rawSettings) {
            if (Config.rawSettings.bar && Config.rawSettings.bar.time && Config.rawSettings.bar.time.format !== undefined) {
                return Config.rawSettings.bar.time.format;
            }
            if (Config.rawSettings.general && Config.rawSettings.general.time_format !== undefined) {
                return Config.rawSettings.general.time_format;
            }
        }
        return "HH:mm:ss";
    }

    readonly property string hourFormat: {
        if (timeFormat.indexOf("HH") !== -1) return "HH";
        if (timeFormat.indexOf("hh") !== -1) return "hh";
        if (timeFormat.indexOf("H") !== -1) return "H";
        if (timeFormat.indexOf("h") !== -1) return "h";
        return "HH";
    }

    readonly property string minuteFormat: {
        if (timeFormat.indexOf("mm") !== -1) return "mm";
        if (timeFormat.indexOf("m") !== -1) return "m";
        return "mm";
    }

    readonly property string secondFormat: {
        if (timeFormat.indexOf("ss") !== -1) return "ss";
        if (timeFormat.indexOf("s") !== -1) return "s";
        return "";
    }

    readonly property string amPmFormat: {
        if (timeFormat.indexOf("AP") !== -1) return "AP";
        if (timeFormat.indexOf("ap") !== -1) return "ap";
        if (timeFormat.indexOf("A") !== -1 || timeFormat.indexOf("a") !== -1) return "AP";
        return "";
    }

    readonly property bool is12Hour: amPmFormat !== "" || hourFormat === "hh" || hourFormat === "h"

    readonly property string time: Qt.formatDateTime(now, timeFormat)
    readonly property string timeShort: Qt.formatDateTime(now, hourFormat + ":" + minuteFormat + (amPmFormat !== "" ? " " + amPmFormat : ""))
    readonly property string timeLong: Qt.formatDateTime(now, "HH:mm:ss")
    readonly property string timeOnly: Qt.formatDateTime(now, timeFormat)

    readonly property string hour: Qt.formatDateTime(now, hourFormat)
    readonly property string minute: Qt.formatDateTime(now, minuteFormat)
    readonly property string second: secondFormat !== "" ? Qt.formatDateTime(now, secondFormat) : ""
    readonly property string amPm: amPmFormat !== "" ? Qt.formatDateTime(now, amPmFormat) : ""

    readonly property string fullDate: now.toLocaleDateString(Qt.locale(I18n.currentLang), "dddd, MMMM dd")
    readonly property string shortDate: Qt.formatDateTime(now, "d MMM")
    readonly property string dateBadge: Qt.formatDateTime(now, "d MMM").toUpperCase()
    readonly property string day: Qt.formatDateTime(now, "dd")
    readonly property string dayShort: Qt.formatDateTime(now, "d")
    readonly property string dayName: Qt.formatDateTime(now, "dddd")
    readonly property string dayNameShort: Qt.formatDateTime(now, "ddd")
    readonly property string month: Qt.formatDateTime(now, "MMMM")
    readonly property string monthShort: Qt.formatDateTime(now, "MMM")
    readonly property string year: Qt.formatDateTime(now, "yyyy")

    function format(pattern, dateObj) {
        return Qt.formatDateTime(dateObj || now, pattern);
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            root.now = new Date();
        }
    }
}
