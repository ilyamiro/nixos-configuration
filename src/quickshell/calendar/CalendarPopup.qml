import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import QtQuick.Window
import "../"
import "../reusables"
import "../singletons"

Item {
    id: window
    focus: true

    function s(val) {
        return Scaler.s(val);
    }

    property real targetMasterHeight: window.s(510)
    property real targetMasterWidth: window.s(1360)
    implicitWidth: targetMasterWidth
    implicitHeight: targetMasterHeight
    width: targetMasterWidth
    height: targetMasterHeight

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: window.forceActiveFocus()
    }

    Shortcut {
        sequence: "Left"
        enabled: window.visible
        onActivated: {
            if (calHover.hovered) {
                window.setMonthOffset(window.targetMonthOffset - 1);
            } else {
                window.setWeatherView(window.targetWeatherView - 1);
            }
        }
    }

    Shortcut {
        sequence: "Right"
        enabled: window.visible
        onActivated: {
            if (calHover.hovered) {
                window.setMonthOffset(window.targetMonthOffset + 1);
            } else {
                window.setWeatherView(window.targetWeatherView + 1);
            }
        }
    }

    readonly property color base: ThemeBackend.base
    readonly property color mantle: ThemeBackend.mantle
    readonly property color crust: ThemeBackend.crust
    readonly property color text: ThemeBackend.text
    readonly property color subtext1: ThemeBackend.subtext1
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color overlay2: ThemeBackend.overlay2
    readonly property color overlay1: ThemeBackend.overlay1
    readonly property color overlay0: ThemeBackend.overlay0
    readonly property color surface2: ThemeBackend.surface2
    readonly property color surface1: ThemeBackend.surface1
    readonly property color surface0: ThemeBackend.surface0

    readonly property color mauve: ThemeBackend.mauve
    readonly property color pink: ThemeBackend.pink
    readonly property color blue: ThemeBackend.blue
    readonly property color sapphire: ThemeBackend.sapphire
    readonly property color peach: ThemeBackend.peach
    readonly property color yellow: ThemeBackend.yellow
    readonly property color teal: ThemeBackend.teal
    readonly property color green: ThemeBackend.green
    readonly property color red: ThemeBackend.red

    readonly property string scriptsDir: Caching.qsDir + "/calendar"

    readonly property color timeColor: {
        let h = window.currentTime.getHours();
        if (h >= 5 && h < 12) return window.peach;
        if (h >= 12 && h < 17) return window.sapphire;
        if (h >= 17 && h < 21) return window.mauve;
        return window.blue;
    }

    readonly property color timeAccent: {
        let h = window.currentTime.getHours();
        if (h >= 5 && h < 12) return window.yellow;
        if (h >= 12 && h < 17) return window.teal;
        if (h >= 17 && h < 21) return window.pink;
        return window.mauve;
    }

    readonly property color textAccent: Qt.tint(window.timeAccent, Qt.alpha(window.text, 0.35))

    property bool startupComplete: false
    property real introMain: 0
    property real introAmbient: 0
    property real introClock: 0
    property real introCalendar: 0
    property real introWeather: 0

    function resetAndPlayIntro() {
        startupComplete = false;
        introMain = 0;
        introAmbient = 0;
        introClock = 0;
        introCalendar = 0;
        introWeather = 0;
        transitionSpin = 0.0;
        transitionScale = 1.0;
        weatherContentOpacity = 1.0;
        weatherContentOffset = 0.0;
        calendarContentOpacity = 1.0;
        calendarContentOffset = 0.0;
        introAnim.restart();
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            window.currentTime = new Date();
            updateCalendarGrid();
            Weather.refresh(false);
            resetAndPlayIntro();
        } else {
            introAnim.stop();
            exitAnim.stop();
            weatherTransitionAnim.stop();
            calendarTransitionAnim.stop();
            startupComplete = false;
            introMain = 0;
            introAmbient = 0;
            introClock = 0;
            introCalendar = 0;
            introWeather = 0;
            transitionSpin = 0.0;
            transitionScale = 1.0;
            weatherContentOpacity = 1.0;
            weatherContentOffset = 0.0;
            calendarContentOpacity = 1.0;
            calendarContentOffset = 0.0;
        }
    }

    SequentialAnimation {
        id: introAnim
        running: false

        PauseAnimation { duration: 20 }

        ParallelAnimation {
            NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

            SequentialAnimation {
                PauseAnimation { duration: 150 }
                NumberAnimation { target: window; property: "introAmbient"; from: 0; to: 1.0; duration: 1000; easing.type: Easing.OutSine }
            }

            SequentialAnimation {
                PauseAnimation { duration: 250 }
                NumberAnimation { target: window; property: "introClock"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
            }

            SequentialAnimation {
                PauseAnimation { duration: 350 }
                NumberAnimation { target: window; property: "introCalendar"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuint }
            }

            SequentialAnimation {
                PauseAnimation { duration: 400 }
                NumberAnimation { target: window; property: "introWeather"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuint }
            }
        }
        ScriptAction { script: window.startupComplete = true }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introAmbient"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introClock"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCalendar"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introWeather"; to: 0; duration: 350; easing.type: Easing.InQuart }
    }

    property real globalOrbitOffset: 0
    NumberAnimation on globalOrbitOffset {
        from: 0; to: -360; duration: 60000; loops: Animation.Infinite; running: window.visible
    }

    property real globalOscPhase: 0
    NumberAnimation on globalOscPhase {
        from: 0; to: Math.PI * 2; duration: 9000; loops: Animation.Infinite; running: window.visible
    }

    property var currentTime: new Date()
    property real currentEpoch: currentTime.getTime() / 1000

    property real secondPulse: 1.0
    NumberAnimation on secondPulse {
        id: pulseReset
        to: 1.0; duration: 600; easing.type: Easing.OutQuint; running: false
    }

    Timer {
        interval: 1000; running: window.visible; repeat: true
        onTriggered: {
            window.currentTime = new Date();
            window.secondPulse = 1.02;
            pulseReset.start();

            if (window.currentTime.getHours() === 0 && window.currentTime.getMinutes() === 0 && window.currentTime.getSeconds() === 0) {
                updateCalendarGrid();
            }
        }
    }

    property var weatherData: Weather.data
    property int weatherView: 0
    property color activeWeatherHex: {
        if (!window.weatherData) return window.mauve;
        if (window.weatherView === 0 && window.weatherData.current_hex) return window.weatherData.current_hex;
        if (window.weatherData.forecast && window.weatherData.forecast[window.weatherView]) return window.weatherData.forecast[window.weatherView].hex;
        return window.mauve;
    }

    property int targetWeatherView: 0
    property real weatherContentOpacity: 1.0
    property real weatherContentOffset: 0.0
    property int weatherAnimDirection: 1

    property real transitionSpin: 0.0
    property real transitionScale: 1.0

    property real targetTemp: {
        if (!window.weatherData) return 0;
        if (window.targetWeatherView === 0 && window.weatherData.current_temp !== undefined) {
            return Number(window.weatherData.current_temp);
        }
        if (window.weatherData.forecast && window.weatherData.forecast[window.targetWeatherView]) {
            return Number(window.weatherData.forecast[window.targetWeatherView].max);
        }
        return 0;
    }

    property real displayedTemp: targetTemp

    Behavior on displayedTemp {
        NumberAnimation {
            id: tempAnim
            duration: 800
            easing.type: Easing.OutQuart
        }
    }

    property bool isTempAnimating: tempAnim.running
    property color tempGlowColor: {
        if (!isTempAnimating || !window.startupComplete) return window.text;
        if (window.targetTemp > window.displayedTemp) return window.red;
        if (window.targetTemp < window.displayedTemp) return window.blue;
        return window.text;
    }

    SequentialAnimation {
        id: weatherTransitionAnim
        ParallelAnimation {
            NumberAnimation { target: window; property: "weatherContentOpacity"; to: 0.0; duration: 250; easing.type: Easing.InSine }
            NumberAnimation { target: window; property: "weatherContentOffset"; to: -window.s(40) * weatherAnimDirection; duration: 250; easing.type: Easing.InSine }
            NumberAnimation { target: window; property: "transitionSpin"; to: 180 * weatherAnimDirection; duration: 300; easing.type: Easing.InBack }
            NumberAnimation { target: window; property: "transitionScale"; to: 0.8; duration: 300; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                window.weatherView = window.targetWeatherView;
                window.weatherContentOffset = window.s(40) * weatherAnimDirection;
                window.transitionSpin = -180 * weatherAnimDirection;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: window; property: "weatherContentOpacity"; to: 1.0; duration: 450; easing.type: Easing.OutQuart }
            NumberAnimation { target: window; property: "weatherContentOffset"; to: 0.0; duration: 450; easing.type: Easing.OutQuart }
            NumberAnimation { target: window; property: "transitionSpin"; to: 0.0; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            NumberAnimation { target: window; property: "transitionScale"; to: 1.0; duration: 500; easing.type: Easing.OutBack }
        }
    }

    function setWeatherView(idx) {
        if (idx < 0 || idx > 4 || !window.weatherData) return;
        if (idx === window.targetWeatherView) return;

        if (weatherTransitionAnim.running) {
            weatherTransitionAnim.stop();
            window.weatherView = window.targetWeatherView;
            window.transitionSpin = 0.0;
            window.transitionScale = 1.0;
            window.weatherContentOpacity = 1.0;
            window.weatherContentOffset = 0.0;
        }

        window.weatherAnimDirection = idx > window.weatherView ? 1 : -1;
        window.targetWeatherView = idx;
        weatherTransitionAnim.start();
    }

    property int activeHourIndex: {
        if (window.weatherView !== 0 || !window.weatherData || !window.weatherData.forecast || !window.weatherData.forecast[0] || !window.weatherData.forecast[0].hourly) return -1;

        let ch = window.currentTime.getHours();
        let hrArr = window.weatherData.forecast[0].hourly.slice(0, 8);
        let bestIdx = -1;
        let minDiff = 999;

        for (let i = 0; i < hrArr.length; i++) {
            let timeStr = hrArr[i].time || "00:00";
            let parts = timeStr.trim().split(" ");
            let clockPart = parts.length > 1 && parts[0].includes("-") ? parts[1] : parts[0];
            let h = parseInt(clockPart.split(":")[0]);
            if (isNaN(h)) h = 0;
            let diff = Math.abs(h - ch);
            if (diff < minDiff) {
                minDiff = diff;
                bestIdx = i;
            }
        }
        return bestIdx !== -1 ? bestIdx : 0;
    }

    property real centerOffset: 0
    property int monthOffset: 0
    property int targetMonthOffset: 0
    property string targetMonthName: ""
    ListModel { id: calendarModel }

    property real calendarContentOpacity: 1.0
    property real calendarContentOffset: 0.0
    property int calendarAnimDirection: 1

    SequentialAnimation {
        id: calendarTransitionAnim
        ParallelAnimation {
            NumberAnimation { target: window; property: "calendarContentOpacity"; to: 0.0; duration: 200; easing.type: Easing.InSine }
            NumberAnimation { target: window; property: "calendarContentOffset"; to: -window.s(20) * calendarAnimDirection; duration: 200; easing.type: Easing.InSine }
        }
        ScriptAction {
            script: {
                window.monthOffset = window.targetMonthOffset;
                window.calendarContentOffset = window.s(20) * calendarAnimDirection;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: window; property: "calendarContentOpacity"; to: 1.0; duration: 350; easing.type: Easing.OutQuart }
            NumberAnimation { target: window; property: "calendarContentOffset"; to: 0.0; duration: 350; easing.type: Easing.OutQuart }
        }
    }

    function setMonthOffset(newOffset) {
        if (newOffset === window.targetMonthOffset) return;

        if (calendarTransitionAnim.running) {
            calendarTransitionAnim.stop();
            window.monthOffset = window.targetMonthOffset;
            window.calendarContentOpacity = 1.0;
            window.calendarContentOffset = 0.0;
        }

        window.calendarAnimDirection = newOffset > window.targetMonthOffset ? 1 : -1;
        window.targetMonthOffset = newOffset;
        calendarTransitionAnim.start();
    }

    function updateCalendarGrid() {
        let d = new Date(window.currentTime.getTime());
        d.setDate(1);
        d.setMonth(d.getMonth() + window.monthOffset);

        let targetMonth = d.getMonth();
        let targetYear = d.getFullYear();

        let actualToday = new Date();
        let isRealCurrentMonth = (actualToday.getMonth() === targetMonth && actualToday.getFullYear() === targetYear);
        let todayDate = actualToday.getDate();

        window.targetMonthName = d.toLocaleDateString(Qt.locale(I18n.currentLang), "MMMM yyyy");

        let firstDay = new Date(targetYear, targetMonth, 1).getDay();
        firstDay = (firstDay === 0) ? 6 : firstDay - 1;

        let daysInMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
        let daysInPrevMonth = new Date(targetYear, targetMonth, 0).getDate();

        calendarModel.clear();

        for (let i = firstDay - 1; i >= 0; i--) {
            calendarModel.append({ dayNum: (daysInPrevMonth - i).toString(), isCurrentMonth: false, isToday: false });
        }
        for (let i = 1; i <= daysInMonth; i++) {
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: true, isToday: (isRealCurrentMonth && i === todayDate) });
        }
        let remaining = 42 - calendarModel.count;
        for (let i = 1; i <= remaining; i++) {
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: false, isToday: false });
        }
    }

    onMonthOffsetChanged: updateCalendarGrid()

    Component.onCompleted: {
        updateCalendarGrid();
        if (visible) {
            forceActiveFocus();
            focusTimer.restart();
            Weather.refresh(false);
            resetAndPlayIntro();
        }
    }

    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: window.base
            border.color: window.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.5; height: width; radius: width / 2
                x: parent.width * 0.75 - width / 2
                y: parent.height * 0.3 - height / 2
                opacity: 0.012 * window.introAmbient
                color: window.activeWeatherHex
                Behavior on color { ColorAnimation { duration: 1000 } }

                transform: Translate {
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: window.s(350); to: -window.s(350); duration: 30000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: -window.s(350); to: window.s(350); duration: 30000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on y {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: 0; to: window.s(200); duration: 15000; easing.type: Easing.OutSine }
                        NumberAnimation { from: window.s(200); to: -window.s(200); duration: 30000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: -window.s(200); to: 0; duration: 15000; easing.type: Easing.InSine }
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.6; height: width; radius: width / 2
                x: parent.width * 0.25 - width / 2
                y: parent.height * 0.7 - height / 2
                opacity: 0.01 * window.introAmbient
                color: window.timeColor
                Behavior on color { ColorAnimation { duration: 1000 } }

                transform: Translate {
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: 0; to: -window.s(300); duration: 18750; easing.type: Easing.OutSine }
                        NumberAnimation { from: -window.s(300); to: window.s(300); duration: 37500; easing.type: Easing.InOutSine }
                        NumberAnimation { from: window.s(300); to: 0; duration: 18750; easing.type: Easing.InSine }
                    }
                    SequentialAnimation on y {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: -window.s(250); to: window.s(250); duration: 37500; easing.type: Easing.InOutSine }
                        NumberAnimation { from: window.s(250); to: -window.s(250); duration: 37500; easing.type: Easing.InOutSine }
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.45; height: width; radius: width / 2
                x: parent.width * 0.5 - width / 2
                y: parent.height * 0.5 - height / 2
                opacity: 0.007 * window.introAmbient
                color: window.timeAccent
                Behavior on color { ColorAnimation { duration: 1000 } }

                transform: Translate {
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: window.s(400); to: -window.s(400); duration: 25000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: -window.s(400); to: window.s(400); duration: 25000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on y {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: 0; to: -window.s(350); duration: 12500; easing.type: Easing.OutSine }
                        NumberAnimation { from: -window.s(350); to: window.s(350); duration: 25000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: window.s(350); to: 0; duration: 12500; easing.type: Easing.InSine }
                    }
                }
            }

            Item {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.centerOffset
                z: 0
                opacity: window.introAmbient * window.weatherContentOpacity

                Text {
                    id: parallaxIcon
                    anchors.centerIn: parent
                    text: {
                        if (!window.weatherData) return "";
                        if (window.weatherView === 0 && window.weatherData.current_icon) return window.weatherData.current_icon;
                        if (window.weatherData.forecast && window.weatherData.forecast[window.weatherView]) return window.weatherData.forecast[window.weatherView].icon;
                        return "";
                    }
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: window.s(520)
                    color: window.activeWeatherHex
                    Behavior on color { ColorAnimation { duration: 1500 } }

                    opacity: 0.015
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { from: 0.015; to: 0.018; duration: 5625; easing.type: Easing.OutSine }
                        NumberAnimation { from: 0.018; to: 0.012; duration: 11250; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.012; to: 0.015; duration: 5625; easing.type: Easing.InSine }
                    }

                    transform: [
                        Translate {
                            SequentialAnimation on y {
                                loops: Animation.Infinite
                                running: window.visible
                                NumberAnimation { to: -window.s(8); duration: 6000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0; duration: 6000; easing.type: Easing.InOutSine }
                            }
                        },
                        Translate { x: window.weatherContentOffset * 2 }
                    ]
                }
            }

            Item {
                id: centralHub
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.centerOffset
                width: window.s(1)
                height: window.s(1)
                z: 5

                opacity: introClock
                scale: 0.85 + (0.15 * introClock)

                transform: [
                    Translate { y: window.s(25) * (1.0 - introClock) },
                    Translate {
                        SequentialAnimation on y {
                            loops: Animation.Infinite
                            running: window.visible
                            NumberAnimation { to: -window.s(6); duration: 4500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 4500; easing.type: Easing.InOutSine }
                        }
                    },
                    Rotation {
                        axis { x: 1; y: 0; z: 0 }
                        SequentialAnimation on angle {
                            loops: Animation.Infinite; running: window.visible
                            NumberAnimation { to: 1.5; duration: 4800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: -1.5; duration: 4800; easing.type: Easing.InOutSine }
                        }
                    },
                    Rotation {
                        axis { x: 0; y: 1; z: 0 }
                        SequentialAnimation on angle {
                            loops: Animation.Infinite; running: window.visible
                            NumberAnimation { to: 1.2; duration: 5500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: -1.2; duration: 5500; easing.type: Easing.InOutSine }
                        }
                    },
                    Rotation {
                        axis { x: 0; y: 0; z: 1 }
                        SequentialAnimation on angle {
                            loops: Animation.Infinite; running: window.visible
                            NumberAnimation { to: 0.8; duration: 6200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: -0.8; duration: 6200; easing.type: Easing.InOutSine }
                        }
                    }
                ]

                Canvas {
                    id: orbitCanvas
                    z: -10
                    anchors.centerIn: parent
                    width: window.s(680)
                    height: window.s(320)
                    opacity: 0.35

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: window.visible
                        NumberAnimation { to: 1.012; duration: 4000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 4000; easing.type: Easing.InOutSine }
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.beginPath();
                        var currentRx = window.s(268);
                        var currentRy = window.s(124);
                        for (var i = 0; i <= Math.PI * 2; i += 0.05) {
                            var xx = width / 2 + Math.cos(i) * currentRx;
                            var yy = height / 2 + Math.sin(i) * currentRy;
                            if (i === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy);
                        }
                        ctx.strokeStyle = Qt.alpha(window.textAccent, 0.45);
                        ctx.lineWidth = Math.max(1, window.s(2));
                        ctx.lineCap = "round";
                        ctx.setLineDash([window.s(4), window.s(12)]);
                        ctx.stroke();
                    }
                    Behavior on opacity { NumberAnimation { duration: 1500 } }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    z: 0
                    scale: 0.98 + (0.02 * window.secondPulse)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: DateTime.time
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: {
                            let baseSize = window.s(84);
                            let len = (DateTime.time || "").length;
                            if (len <= 5) return baseSize;
                            let scaleFactor = Math.min(1.0, Math.pow(5 / len, 0.7));
                            return Math.round(Math.max(window.s(36), baseSize * scaleFactor));
                        }
                        color: window.text
                        style: Text.Outline
                        styleColor: Qt.alpha(window.crust, 0.4)
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: DateTime.fullDate
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: window.s(16)
                        color: window.subtext0
                        opacity: 0.9
                    }
                }

                Item {
                    anchors.fill: parent
                    opacity: window.weatherContentOpacity
                    scale: window.transitionScale
                    transform: Translate { x: window.weatherContentOffset * 1.5 }

                    Repeater {
                        id: hourRepeater
                        model: window.weatherData && window.weatherData.forecast[window.weatherView] && window.weatherData.forecast[window.weatherView].hourly ? window.weatherData.forecast[window.weatherView].hourly.slice(0, 8) : []

                        delegate: Item {
                            property int mCount: hourRepeater.count
                            property bool isToday: window.weatherView === 0
                            property bool isHighlighted: isToday && index === window.activeHourIndex

                            property real rx: window.s(268) * orbitCanvas.scale
                            property real ry: window.s(124) * orbitCanvas.scale

                            property int relIdx: isToday ? (index - window.activeHourIndex) : index
                            property real targetAngleDeg: isToday ? (65 + (relIdx * 30)) : (index * (360 / Math.max(1, mCount)))
                            property real orbitOffset: isToday ? 0 : window.globalOrbitOffset
                            property real osc: isToday ? (Math.sin(window.globalOscPhase + index) * 2.5) : 0
                            property real rad: (targetAngleDeg + orbitOffset + osc + window.transitionSpin) * (Math.PI / 180)

                            property real depthFactor: (Math.sin(rad) + 1.0) / 2.0

                            x: Math.cos(rad) * rx - width / 2
                            y: Math.sin(rad) * ry - height / 2
                            z: isHighlighted ? (Math.sin(rad) * window.s(100) + 10) : (Math.sin(rad) * window.s(100))

                            property real baseScale: isHighlighted ? (0.80 + 0.55 * depthFactor) : (0.68 + 0.42 * depthFactor)
                            property real hoverScale: hrMa.containsMouse && !isHighlighted ? 1.04 : 1.0
                            Behavior on hoverScale { NumberAnimation { duration: 150 } }

                            scale: baseScale * hoverScale

                            opacity: isHighlighted ? (0.75 + 0.25 * depthFactor) : (0.55 + 0.45 * depthFactor)

                            width: window.s(52)
                            height: window.s(86)

                            Rectangle {
                                anchors.fill: parent
                                radius: Math.min(window.s(26), ThemeBackend.borderRadius * 1.75)
                                color: isHighlighted ? window.textAccent : (hrMa.containsMouse ? Qt.lighter(window.surface0, 1.12) : window.surface0)
                                border.color: isHighlighted ? Qt.lighter(window.textAccent, 1.1) : (hrMa.containsMouse ? Qt.alpha(window.surface2, 0.9) : Qt.alpha(window.surface1, 0.6))
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 180 } }
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: window.s(3)

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData ? modelData.time : ""
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(11.5)
                                        color: isHighlighted ? window.base : (hrMa.containsMouse ? window.text : window.overlay1)
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData ? (modelData.icon || (window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].icon : "")) : ""
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: window.s(16.5)
                                        color: isHighlighted ? window.base : (modelData ? (modelData.hex || window.text) : window.text)
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData ? (modelData.temp + "°") : ""
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(12.5)
                                        color: isHighlighted ? window.base : window.text
                                    }
                                }
                            }
                            MouseArea { id: hrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
            }

            Rectangle {
                id: calendarRect
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: window.s(40)
                width: window.s(310)
                height: window.s(350)
                color: Qt.alpha(window.surface0, 0.2)
                radius: ThemeBackend.borderRadius
                border.color: Qt.alpha(window.surface1, 0.4)
                border.width: 1
                z: 10

                opacity: introCalendar
                transform: Translate { x: -window.s(40) * (1.0 - introCalendar) }

                HoverHandler { id: calHover }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: window.s(12)
                    anchors.bottomMargin: window.s(12)
                    anchors.leftMargin: window.s(16)
                    anchors.rightMargin: window.s(16)
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: window.s(14)

                        IconButton {
                            Layout.preferredWidth: window.s(28)
                            Layout.preferredHeight: window.s(28)
                            size: window.s(28)
                            cornerRadius: window.s(8)
                            buttonIcon: "󰃭"
                            iconFontSize: window.s(14)
                            accentColor: window.surface0
                            textColor: window.text
                            opacity: window.targetMonthOffset !== 0 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            onClicked: { if (window.targetMonthOffset !== 0) window.setMonthOffset(0) }
                        }

                        IconButton {
                            Layout.preferredWidth: window.s(28)
                            Layout.preferredHeight: window.s(28)
                            size: window.s(28)
                            cornerRadius: window.s(8)
                            buttonIcon: ""
                            iconFontSize: window.s(14)
                            accentColor: window.surface0
                            textColor: window.text
                            onClicked: window.setMonthOffset(window.targetMonthOffset - 1)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: window.targetMonthName.toUpperCase()
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: window.s(14)
                            fontSizeMode: Text.Fit
                            minimumPixelSize: window.s(8)
                            color: window.text
                            horizontalAlignment: Text.AlignHCenter

                            opacity: window.calendarContentOpacity
                            transform: Translate { x: window.calendarContentOffset }
                        }

                        IconButton {
                            Layout.preferredWidth: window.s(28)
                            Layout.preferredHeight: window.s(28)
                            size: window.s(28)
                            cornerRadius: window.s(8)
                            buttonIcon: ""
                            iconFontSize: window.s(14)
                            accentColor: window.surface0
                            textColor: window.text
                            onClicked: window.setMonthOffset(window.targetMonthOffset + 1)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: window.s(4)

                        Repeater {
                            model: [I18n.t("calendar.days.mo"), I18n.t("calendar.days.tu"), I18n.t("calendar.days.we"), I18n.t("calendar.days.th"), I18n.t("calendar.days.fr"), I18n.t("calendar.days.sa"), I18n.t("calendar.days.su")]
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: window.s(11.5)
                                color: window.overlay0
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 7
                        rowSpacing: window.s(2)
                        columnSpacing: window.s(3)

                        opacity: window.calendarContentOpacity
                        transform: Translate { x: window.calendarContentOffset }

                        Repeater {
                            model: calendarModel
                            ClickButton {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                enabled: false
                                buttonText: dayNum
                                textFontSize: window.s(11.5)
                                cornerRadius: window.s(5)
                                horizontalPadding: 0
                                accentColor: isToday ? window.textAccent : "transparent"
                                textColor: isToday ? window.base : (isCurrentMonth ? window.text : window.surface0)
                            }
                        }
                    }
                }
            }

            Item {
                id: weatherContainer
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: window.s(40)
                width: window.s(320)
                height: window.s(430)
                z: 10

                opacity: introWeather
                transform: Translate { x: window.s(40) * (1.0 - introWeather) }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: window.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        spacing: window.s(14)

                        IconButton {
                            Layout.preferredWidth: window.s(28)
                            Layout.preferredHeight: window.s(28)
                            size: window.s(28)
                            cornerRadius: window.s(8)
                            buttonIcon: ""
                            iconFontSize: window.s(12)
                            accentColor: window.surface0
                            textColor: isHoveredOrHighlighted ? window.textAccent : window.overlay1
                            onClicked: window.setWeatherView(window.targetWeatherView - 1)
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].day_full.toUpperCase() : I18n.t("calendar.loading")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: window.s(15)
                            fontSizeMode: Text.Fit
                            minimumPixelSize: window.s(8)
                            color: window.text
                        }

                        IconButton {
                            Layout.preferredWidth: window.s(28)
                            Layout.preferredHeight: window.s(28)
                            size: window.s(28)
                            cornerRadius: window.s(8)
                            buttonIcon: ""
                            iconFontSize: window.s(12)
                            accentColor: window.surface0
                            textColor: isHoveredOrHighlighted ? window.textAccent : window.overlay1
                            onClicked: window.setWeatherView(window.targetWeatherView + 1)
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 0

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: Math.round(window.displayedTemp) + (Weather.unitSym || "°")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: window.s(72)
                            color: window.tempGlowColor
                            style: Text.Outline
                            styleColor: window.isTempAnimating ? Qt.alpha(window.tempGlowColor, 0.5) : Qt.alpha(window.crust, 0.4)

                            Behavior on color { ColorAnimation { duration: 300 } }
                            Behavior on styleColor { ColorAnimation { duration: 300 } }
                        }

                        Text {
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: window.s(320)
                            horizontalAlignment: Text.AlignRight
                            text: (typeof Location !== "undefined" && Location.city && Location.city !== "") ? Location.city : (window.weatherData && window.weatherData.city ? window.weatherData.city : "")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: window.s(14)
                            color: window.text
                            elide: Text.ElideRight
                            visible: text !== ""
                        }

                        Text {
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: window.s(320)
                            Layout.topMargin: window.s(4)
                            horizontalAlignment: Text.AlignRight
                            text: window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].desc : ""
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Medium
                            font.pixelSize: window.s(13)
                            wrapMode: Text.WordWrap
                            color: window.textAccent
                            Behavior on color { ColorAnimation { duration: 1000 } }

                            opacity: window.weatherContentOpacity
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    GridLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                        columns: 2
                        rowSpacing: window.s(8)
                        columnSpacing: window.s(8)

                        Repeater {
                            model: 4

                            ClickButton {
                                Layout.preferredWidth: window.s(118)
                                Layout.preferredHeight: window.s(42)
                                cornerRadius: window.s(9)
                                horizontalPadding: window.s(8)

                                property var forecast: window.weatherData && window.weatherData.forecast[window.targetWeatherView] ? window.weatherData.forecast[window.targetWeatherView] : null

                                buttonIcon: index === 0 ? "" : index === 1 ? "" : index === 2 ? "" : ""
                                buttonText: forecast ? (
                                    index === 0 ? forecast.wind + (Weather.unit === "imperial" ? "mph" : "m/s") :
                                    index === 1 ? forecast.humidity + "%" :
                                    index === 2 ? forecast.pop + "%" :
                                    forecast.feels_like + "°"
                                ) : ""
                                subText: index === 0 ? I18n.t("calendar.weather.wind") : index === 1 ? I18n.t("calendar.weather.humid") : index === 2 ? I18n.t("calendar.weather.rain") : I18n.t("calendar.weather.feels")

                                iconFontSize: window.s(14)
                                textFontSize: window.s(11.5)

                                accentColor: window.surface0
                                textColor: isHoveredOrHighlighted ? window.textAccent : window.overlay0
                            }
                        }
                    }
                }
            }
        }
    }
}
