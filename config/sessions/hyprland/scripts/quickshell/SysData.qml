pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    
    Caching { id: paths }
    
    // --- Centralized Properties ---
    property int cpu: 0
    property int gpu: -1
    property int ramPercent: 0
    property real ramGb: 0.0
    property int temp: 0
    property real netRx: 0
    property real netTx: 0
    
    // --- Lifecycle Management ---
    property int subscribers: 0
    
    function subscribe() { 
        subscribers++; 
        if (subscribers === 1) {
            fetchTimer.restart();
            fetchProc.running = true; // Fetch immediately on first open
        }
    }
    
    function unsubscribe() { 
        subscribers = Math.max(0, subscribers - 1); 
        if (subscribers === 0) {
            fetchTimer.stop();
            fetchProc.running = false;
        }
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
        // Safely delegates path expansion directly to bash, preventing QML parsing issues
        // Passes dynamic sysdata cache dir in case the script needs it
        command: ["bash", "-c", "export QS_CACHE_SYSDATA=" + paths.getCacheDir("sysdata") + "; bash ~/.config/hypr/scripts/quickshell/watchers/sys_fetcher.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text ? this.text.trim() : "";
                if (!text) return;
                
                let p = text.split("|");
                if (p.length >= 6) {
                    root.cpu = parseInt(p[0]);
                    root.ramPercent = parseInt(p[1]);
                    root.ramGb = parseFloat(p[2]);
                    root.temp = parseInt(p[3]);
                    root.netRx = parseFloat(p[4]);
                    root.netTx = parseFloat(p[5]);
                    root.gpu = p.length >= 7 ? parseInt(p[6]) : -1;
                }
            }
        }
    }
}
