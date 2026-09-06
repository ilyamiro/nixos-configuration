import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 420
    property real minHeight: 260
    property real maxWidth: 820
    property real maxHeight: 500
    property real minAspect: 1.6
    property real maxAspect: 1.6

    property real baseRef: Math.min(root.height, root.width * 0.6)
    property real dynMargin: Math.max(18, baseRef * 0.09)
    property real dynSpacing: Math.max(10, baseRef * 0.05)

    property real iconTop: Math.max(48, Math.min(78, baseRef * 0.42))
    property real tempHuge: Math.max(36, Math.min(64, baseRef * 0.28))
    property real textCity: Math.max(14, Math.min(20, baseRef * 0.08))
    property real textDesc: Math.max(12, Math.min(16, baseRef * 0.065))
    property real textFeels: Math.max(11, Math.min(14, baseRef * 0.055))
    property real forecastTemp: Math.max(13, Math.min(18, baseRef * 0.07))
    property real forecastIcon: Math.max(22, Math.min(32, baseRef * 0.14))
    property real forecastTime: Math.max(9, Math.min(13, baseRef * 0.05))

    property var weatherData: Weather.data
    property bool hasLoadedOnce: Weather.isReady
    property bool isLoading: Weather.isLoading || !Weather.isReady

    property string currentHex: Weather.currentHex
    property color accentColor: (currentHex && currentHex.length === 7) ? currentHex : ThemeBackend.mauve

    property var hourlyList: []

    property real cardRadius: ThemeBackend.clampedBorderRadius

    function formatHour(timeStr) {
        if (!timeStr) return "";
        let str = String(timeStr).trim();
        if (str.toLowerCase().indexOf("am") !== -1 || str.toLowerCase().indexOf("pm") !== -1) {
            return str;
        }
        let hour = 0;
        if (str.indexOf(":") !== -1) {
            hour = parseInt(str.split(":")[0], 10);
        } else {
            let num = parseInt(str, 10);
            if (!isNaN(num)) {
                hour = num >= 100 ? Math.floor(num / 100) : num;
            }
        }
        if (isNaN(hour)) return str;

        if (DateTime.is12Hour) {
            let period = hour >= 12 ? "PM" : "AM";
            let h12 = hour % 12;
            if (h12 === 0) h12 = 12;
            return h12 + period;
        }

        return (hour < 10 ? "0" + hour : hour) + ":00";
    }

    function getFeelsLike() {
        if (!weatherData) return Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°";
        let fl = weatherData.current_feels_like ?? weatherData.feels_like ?? weatherData.current_feelslike;
        if (fl !== undefined && fl !== null && fl !== "") {
            return Math.round(parseFloat(fl)) + "°";
        }
        if (weatherData.forecast && weatherData.forecast[0]) {
            let f0 = weatherData.forecast[0];
            if (f0.feels_like !== undefined) return Math.round(parseFloat(f0.feels_like)) + "°";
            if (f0.hourly && f0.hourly[0] && f0.hourly[0].feels_like !== undefined) {
                return Math.round(parseFloat(f0.hourly[0].feels_like)) + "°";
            }
        }
        if (Weather.currentTemp !== "") {
            return Math.round(parseFloat(Weather.currentTemp)) + "°";
        }
        return "--°";
    }

    function updateForecastData() {
        if (!weatherData || !weatherData.forecast || !Array.isArray(weatherData.forecast) || weatherData.forecast.length === 0) {
            hourlyList = [];
            return;
        }

        let allHourly = [];
        for (let d = 0; d < weatherData.forecast.length; d++) {
            if (weatherData.forecast[d] && weatherData.forecast[d].hourly) {
                allHourly = allHourly.concat(weatherData.forecast[d].hourly);
            }
        }

        if (allHourly.length === 0) {
            hourlyList = [];
            return;
        }

        let ch = DateTime.now.getHours();
        let bestIdx = 0;
        let minDiff = 999;
        for (let i = 0; i < allHourly.length; i++) {
            let timeStr = allHourly[i].time || "00:00";
            let h = parseInt(timeStr.split(":")[0], 10);
            if (isNaN(h)) {
                let n = parseInt(timeStr, 10);
                h = n >= 100 ? Math.floor(n / 100) : n;
            }
            let diff = h - ch;
            if (diff >= 0 && diff < minDiff) {
                minDiff = diff;
                bestIdx = i;
            }
        }

        if (minDiff === 999) {
            for (let i = 0; i < allHourly.length; i++) {
                let timeStr = allHourly[i].time || "00:00";
                let h = parseInt(timeStr.split(":")[0], 10);
                if (isNaN(h)) {
                    let n = parseInt(timeStr, 10);
                    h = n >= 100 ? Math.floor(n / 100) : n;
                }
                let diff = Math.abs(h - ch);
                if (diff < minDiff) {
                    minDiff = diff;
                    bestIdx = i;
                }
            }
        }

        hourlyList = allHourly.slice(bestIdx, bestIdx + 4);
    }

    onWeatherDataChanged: updateForecastData()

    Connections {
        target: DateTime
        function onHourChanged() {
            root.updateForecastData();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ThemeBackend.surface0
        radius: root.cardRadius
        clip: true

        LoaderIcon {
            anchors.centerIn: parent
            width: Math.max(28, Math.min(56, root.baseRef * 0.3))
            height: width
            accentColor: ThemeBackend.mauve
            running: root.isLoading
            visible: root.isLoading
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.dynMargin
            spacing: root.dynSpacing
            visible: !root.isLoading

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 0

                Text {
                    text: Weather.currentIcon
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.iconTop
                    color: root.accentColor
                    Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                }

                Item {
                    Layout.fillHeight: true
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignBottom | Qt.AlignLeft
                    spacing: 2

                    Text {
                        text: Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.tempHuge
                        font.weight: Font.Black
                        color: ThemeBackend.text
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Feels like " + root.getFeelsLike()
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.textFeels
                        font.weight: Font.Medium
                        color: ThemeBackend.subtext0
                        elide: Text.ElideRight
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.3
                spacing: 0

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop | Qt.AlignRight
                    spacing: 2

                    Text {
                        text: Location.city && Location.city !== "" ? Location.city : (root.weatherData && root.weatherData.city ? root.weatherData.city : "Unknown")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.textCity
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.weatherData && root.weatherData.forecast && root.weatherData.forecast[0] && root.weatherData.forecast[0].desc ? root.weatherData.forecast[0].desc : (Weather.data && Weather.data.desc ? Weather.data.desc : "")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.textDesc
                        font.weight: Font.Medium
                        color: ThemeBackend.subtext0
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                    spacing: root.dynSpacing * 0.9

                    Repeater {
                        model: root.hourlyList
                        delegate: ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                            spacing: 4

                            Text {
                                text: Math.round(parseFloat(modelData.temp)) + "°"
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.forecastTemp
                                font.weight: Font.Medium
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                transform: Translate { x: 2 }
                            }

                            Text {
                                text: modelData.icon
                                color: modelData.hex && modelData.hex.length === 7 ? modelData.hex : root.accentColor
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.forecastIcon
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                transform: Translate { x: -2 }
                            }

                            Text {
                                text: root.formatHour(modelData.time)
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.forecastTime
                                font.weight: Font.Normal
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
