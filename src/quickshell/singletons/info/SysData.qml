pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property int cpu: 0
    property int ramPercent: 0
    property real ramGb: 0.0
    property int temp: 0
    property real netRx: 0
    property real netTx: 0
    property int diskPercent: 0
    property real diskGb: 0.0
    property real diskTotalGb: 0.0

    property int subscribers: 0
    property bool isScanningNet: false

    function subscribe() {
        subscribers++;
        if (subscribers === 1) {
            fetchTimer.restart();
            fetchProc.running = true;
        }
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        if (subscribers === 0) {
            fetchTimer.stop();
            fetchProc.running = false;
        }
    }

    function prewarm() {
        if (!fetchProc.running) {
            fetchProc.running = true;
        }
    }

    function scanNetwork() {
        if (isScanningNet) return;
        isScanningNet = true;
        netScanProc.running = false;
        netScanProc.running = true;
    }

    Timer {
        id: fetchTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: {
            fetchProc.running = false;
            fetchProc.running = true;
        }
    }

    Process {
        id: fetchProc
        running: false
        command: ["bash", "-c", "export QS_CACHE_SYSDATA='" + Caching.getCacheDir("sysdata") + "'; export QS_SCAN_NET=0; bash '" + Caching.qsDir + "/watchers/sys_fetcher.sh'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text ? this.text.trim() : "";
                if (!text) return;

                let p = text.split("|");
                if (p.length >= 4) {
                    root.cpu = parseInt(p[0]);
                    root.ramPercent = parseInt(p[1]);
                    root.ramGb = parseFloat(p[2]);
                    root.temp = parseInt(p[3]);
                }
                if (p.length >= 9) {
                    root.diskPercent = parseInt(p[6]);
                    root.diskGb = parseFloat(p[7]);
                    root.diskTotalGb = parseFloat(p[8]);
                }
            }
        }
    }

    Process {
        id: netScanProc
        running: false
        command: ["bash", "-c", "export QS_CACHE_SYSDATA='" + Caching.getCacheDir("sysdata") + "'; export QS_SCAN_NET=1; bash '" + Caching.qsDir + "/watchers/sys_fetcher.sh'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text ? this.text.trim() : "";
                if (text) {
                    let p = text.split("|");
                    if (p.length >= 6) {
                        root.cpu = parseInt(p[0]);
                        root.ramPercent = parseInt(p[1]);
                        root.ramGb = parseFloat(p[2]);
                        root.temp = parseInt(p[3]);
                        root.netRx = parseFloat(p[4]);
                        root.netTx = parseFloat(p[5]);
                    }
                    if (p.length >= 9) {
                        root.diskPercent = parseInt(p[6]);
                        root.diskGb = parseFloat(p[7]);
                        root.diskTotalGb = parseFloat(p[8]);
                    }
                }
                root.isScanningNet = false;
            }
        }
    }
}
