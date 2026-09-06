import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia
import "../"

ShellRoot {
    id: globalRoot

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                focusable: false
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                color: "#0a0a0f"

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false

                readonly property int transitionDuration: 1000
                property real transitionProgress: 1.0
                property bool isPreloading: false

                Component.onCompleted: restorePoller.running = true

                onCurrentWallpaperPathChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpaperPaths);
                        map[barWindow.screen.name] = currentWallpaperPath;
                        Wallpaper.screenWallpaperPaths = map;
                    }
                }

                onOriginalFileNameChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpapers);
                        map[barWindow.screen.name] = originalFileName;
                        Wallpaper.screenWallpapers = map;
                    }
                }

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name)
                            barWindow.changeWallpaper(path, transition);
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.currentWallpaperPath = "";
                            barWindow.pathA = "";
                            barWindow.pathB = "";
                            barWindow.isVideoA = false;
                            barWindow.isVideoB = false;
                            barWindow.originalFileName = "";
                            barWindow.stopA();
                            barWindow.stopB();
                            Quickshell.execDetached(["bash", "-c", "rm -f '" + barWindow.wpStatePath + "' '" + barWindow.wpStatePath + "_name'"]);
                        }
                    }
                }

                Process {
                    id: restorePoller
                    running: false
                    command: [
                        "bash", "-c",
                        "F1='" + barWindow.wpStatePath + "'; F2='" + barWindow.wpStatePath + "_name'; [ -f \"$F1\" ] && cat \"$F1\" || true; echo '---SPLIT---'; [ -f \"$F2\" ] && cat \"$F2\" || true"
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.split("---SPLIT---");
                            let savedPath = parts[0] ? parts[0].trim() : "";
                            let savedName = parts[1] ? parts[1].trim() : "";
                            if (savedPath !== "") {
                                barWindow.originalFileName = savedName;
                                barWindow._loadNew(savedPath, false);
                                if (barWindow.isVideo(savedPath)) {
                                    videoSnapshotProcess.targetPath = savedPath;
                                    videoSnapshotProcess.running = false;
                                    videoSnapshotProcess.running = true;
                                }
                                if (savedName !== "") {
                                    let histFile = barWindow.wpCacheDir + "/history.txt";
                                    Quickshell.execDetached(["bash", "-c",
                                        "HIST='" + histFile + "'; if [ -f \"$HIST\" ]; then if [ \"$(head -n 1 \"$HIST\" 2>/dev/null)\" != '" + savedName + "' ]; then grep -v -F -x '" + savedName + "' \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\n' '" + savedName + "' | cat - \"$HIST.tmp\" > \"$HIST\" 2>/dev/null; rm -f \"$HIST.tmp\"; fi; else printf '%s\n' '" + savedName + "' > \"$HIST\"; fi"
                                    ]);
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 250
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null; cp -f \"$2\" \"$3\" 2>/dev/null || true",
                        "_",
                        targetPath,
                        barWindow.wpSnapshotPath,
                        barWindow.wpMonitorSnapshotPath
                    ]
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
                           lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function playA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") {
                        videoLoaderA.item.play();
                    }
                }

                function stopA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") {
                        videoLoaderA.item.stop();
                    }
                }

                function playB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") {
                        videoLoaderB.item.play();
                    }
                }

                function stopB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") {
                        videoLoaderB.item.stop();
                    }
                }

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    barWindow.isPreloading = false;
                    transitionAnim.restart();
                }

                function _loadNew(path, force) {
                    if (!path) return;
                    if (!force && path === barWindow.currentWallpaperPath) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);

                    let slash = cleanPath.lastIndexOf("/");
                    let filename = cleanPath.substring(slash + 1);
                    if (!filename.startsWith("wallpaper.")) {
                        barWindow.originalFileName = filename;
                    }

                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;

                    if (barWindow.activeLayer === 1) {
                        barWindow.pathA = cleanPath;
                        barWindow.isVideoA = vid;
                        barWindow.activeLayer = 0;
                        if (vid) {
                            barWindow.playA();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    } else {
                        barWindow.pathB = cleanPath;
                        barWindow.isVideoB = vid;
                        barWindow.activeLayer = 1;
                        if (vid) {
                            barWindow.playB();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;

                    let cleanPath = String(path).trim();
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;

                    Quickshell.execDetached(["bash", "-c",
                        "mkdir -p '" + wpCopyDir + "'" +
                        " && printf '%s' '" + cleanPath + "' > '" + wpStatePath + "'" +
                        " && printf '%s' '" + origName + "' > '" + wpStatePath + "_name'" +
                        " && cp -f '" + cleanPath + "' '" + dest + "'" +
                        (vid ? "" : " && cp -f '" + cleanPath + "' '" + snapshotPath + "' && cp -f '" + cleanPath + "' '" + monSnapshotPath + "'") +
                        " && ( HIST='" + histFile + "'; if [ -f \"$HIST\" ]; then grep -v -F -x '" + origName + "' \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\n' '" + origName + "' | cat - \"$HIST.tmp\" > \"$HIST\" 2>/dev/null; rm -f \"$HIST.tmp\"; else printf '%s\n' '" + origName + "' > \"$HIST\"; fi )"
                    ]);

                    if (vid) {
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = false;
                        videoSnapshotProcess.running = true;
                    }

                    barWindow._loadNew(cleanPath, true);
                }

                PropertyAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.transitionDuration
                    easing.type: Easing.InOutCubic

                    onFinished: {
                        if (barWindow.activeLayer === 0) {
                            barWindow.stopB();
                            barWindow.pathB = "";
                            barWindow.isVideoB = false;
                        } else {
                            barWindow.stopA();
                            barWindow.pathA = "";
                            barWindow.isVideoA = false;
                        }
                    }
                }

                Component {
                    id: videoLayerCompA
                    Item {
                        anchors.fill: parent
                        function play() { playerA.play(); }
                        function stop() { playerA.stop(); }

                        MediaPlayer {
                            id: playerA
                            source: barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            videoOutput: videoOutputA
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    playerA.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerCompB
                    Item {
                        anchors.fill: parent
                        function play() { playerB.play(); }
                        function stop() { playerB.stop(); }

                        MediaPlayer {
                            id: playerB
                            source: barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            videoOutput: videoOutputB
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    playerB.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    Item {
                        id: layerA
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        Image {
                            id: imgA
                            anchors.fill: parent
                            source: !barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoA && barWindow.pathA !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? parent.width : 0
                            sourceSize.height: parent.height > 0 ? parent.height : 0
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: barWindow.isVideoA && barWindow.pathA !== ""
                            asynchronous: false
                            sourceComponent: videoLayerCompA
                            visible: barWindow.isVideoA
                            onLoaded: {
                                if (item && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    Item {
                        id: layerB
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        Image {
                            id: imgB
                            anchors.fill: parent
                            source: !barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoB && barWindow.pathB !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? parent.width : 0
                            sourceSize.height: parent.height > 0 ? parent.height : 0
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: barWindow.isVideoB && barWindow.pathB !== ""
                            asynchronous: false
                            sourceComponent: videoLayerCompB
                            visible: barWindow.isVideoB
                            onLoaded: {
                                if (item && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
