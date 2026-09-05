pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    property string username: Quickshell.env("USER") ? Quickshell.env("USER") : (Quickshell.env("LOGNAME") ? Quickshell.env("LOGNAME") : "user")
    property string desktopEnv: Quickshell.env("XDG_CURRENT_DESKTOP") ? Quickshell.env("XDG_CURRENT_DESKTOP") : (Quickshell.env("DESKTOP_SESSION") ? Quickshell.env("DESKTOP_SESSION") : "Unknown")
    property string shell: Quickshell.env("SHELL") ? Quickshell.env("SHELL") : "Unknown"

    property string hostname: ""
    property string avatarPath: ""
    property string osName: ""
    property string kernelVersion: ""
    property string uptime: ""
    property int uptimeSeconds: 0

    property string cpuModel: ""
    property int cpuCores: 0
    property real totalRamGb: 0.0

    property string gpuModel: ""
    property string diskModel: ""
    property real diskTotalGb: 0.0
    property real diskUsedGb: 0.0
    property int diskPercent: 0

    property bool isDesktop: true

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.fetch();
        }
    }

    function fetch() {
        osReleaseFile.reload();
        kernelFile.reload();
        hostnameFile.reload();
        cpuFile.reload();
        memFile.reload();
        uptimeFile.reload();
        chassisFile.reload();

        hwProc.running = false;
        hwProc.running = true;

        return {
            "username": root.username,
            "hostname": root.hostname,
            "avatarPath": root.avatarPath,
            "osName": root.osName,
            "kernelVersion": root.kernelVersion,
            "uptime": root.uptime,
            "uptimeSeconds": root.uptimeSeconds,
            "cpuModel": root.cpuModel,
            "cpuCores": root.cpuCores,
            "totalRamGb": root.totalRamGb,
            "gpuModel": root.gpuModel,
            "desktopEnv": root.desktopEnv,
            "shell": root.shell,
            "diskModel": root.diskModel,
            "diskTotalGb": root.diskTotalGb,
            "diskUsedGb": root.diskUsedGb,
            "diskPercent": root.diskPercent,
            "isDesktop": root.isDesktop
        };
    }

    Component.onCompleted: {
        root.fetch();
    }

    FileView {
        id: chassisFile
        path: "/sys/class/dmi/id/chassis_type"
        onLoaded: {
            let txt = text();
            if (txt) {
                let code = parseInt(txt.trim());
                let laptopCodes = [8, 9, 10, 11, 14, 30, 31, 32];
                if (laptopCodes.indexOf(code) !== -1) {
                    root.isDesktop = false;
                }
            }
        }
    }

    FileView {
        id: osReleaseFile
        path: "/etc/os-release"
        onLoaded: {
            let txt = text();
            if (!txt) return;
            let lines = txt.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (line.startsWith("PRETTY_NAME=")) {
                    root.osName = line.split("=")[1].replace(/"/g, "").trim();
                    break;
                } else if (line.startsWith("NAME=") && !root.osName) {
                    root.osName = line.split("=")[1].replace(/"/g, "").trim();
                }
            }
        }
    }

    FileView {
        id: kernelFile
        path: "/proc/sys/kernel/osrelease"
        onLoaded: {
            let txt = text();
            if (txt) root.kernelVersion = txt.trim();
        }
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        onLoaded: {
            let txt = text();
            if (txt) root.hostname = txt.trim();
        }
    }

    FileView {
        id: cpuFile
        path: "/proc/cpuinfo"
        onLoaded: {
            let txt = text();
            if (!txt) return;
            let lines = txt.split("\n");
            let count = 0;
            let model = "";
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (line.startsWith("model name")) {
                    count++;
                    if (!model) {
                        let parts = line.split(":");
                        if (parts.length > 1) model = parts[1].trim();
                    }
                }
            }
            root.cpuModel = model;
            root.cpuCores = count;
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            let txt = text();
            if (!txt) return;
            let lines = txt.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (line.startsWith("MemTotal:")) {
                    let parts = line.split(/\s+/);
                    if (parts.length >= 2) {
                        let kb = parseInt(parts[1]);
                        root.totalRamGb = parseFloat((kb / 1048576).toFixed(1));
                    }
                    break;
                }
            }
        }
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: {
            let txt = text();
            if (!txt) return;
            let parts = txt.trim().split(/\s+/);
            if (parts.length > 0) {
                let sec = Math.floor(parseFloat(parts[0]));
                root.uptimeSeconds = sec;
                let d = Math.floor(sec / 86400);
                let h = Math.floor((sec % 86400) / 3600);
                let m = Math.floor((sec % 3600) / 60);
                let res = "";
                if (d > 0) res += d + "d ";
                if (h > 0 || d > 0) res += h + "h ";
                res += m + "m";
                root.uptime = res.trim();
            }
        }
    }

    Process {
        id: hwProc
        running: false
        command: [
            "bash",
            "-c",
            "gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d':' -f3 | sed -e 's/^[ \t]*//' -e 's/ (rev .*)$//' | head -n1); " +
            "[ -z \"$gpu\" ] && gpu=\"Unknown GPU\"; " +
            "disk_mod=$(lsblk -d -n -o MODEL 2>/dev/null | grep -v '^$' | head -n1); " +
            "[ -z \"$disk_mod\" ] && disk_mod=\"Generic Drive\"; " +
            "df_out=$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2\"|\"$3\"|\"$5}'); " +
            "cropped_avatar=\"" + Caching.getCacheDir("avatar") + "/avatar_cropped.png\"; " +
            "cfg_avatar=\"" + (Config.getSetting("general", {}).avatarPath || "") + "\"; " +
            "avatar=\"\"; " +
            "if [ -f \"$cropped_avatar\" ]; then avatar=\"$cropped_avatar\"; " +
            "elif [ -n \"$cfg_avatar\" ] && [ -f \"$cfg_avatar\" ]; then avatar=\"$cfg_avatar\"; " +
            "else " +
            "for a in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do " +
                "if [ -f \"$a\" ]; then avatar=\"$a\"; break; fi; " +
            "done; fi; " +
            "has_battery=0; " +
            "for p in /sys/class/power_supply/*; do " +
                "if [ -f \"$p/type\" ] && grep -qi 'Battery' \"$p/type\" 2>/dev/null; then " +
                    "if [ -f \"$p/scope\" ] && grep -qi 'Device' \"$p/scope\" 2>/dev/null; then continue; fi; " +
                    "has_battery=1; break; " +
                "fi; " +
            "done; " +
            "echo \"$gpu|$disk_mod|$df_out|$avatar|$has_battery\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text ? this.text.trim() : "";
                if (!txt) return;
                let p = txt.split("|");
                if (p.length >= 7) {
                    root.gpuModel = p[0];
                    root.diskModel = p[1];
                    root.diskTotalGb = parseFloat((parseInt(p[2]) / 1073741824).toFixed(1));
                    root.diskUsedGb = parseFloat((parseInt(p[3]) / 1073741824).toFixed(1));
                    root.diskPercent = parseInt(p[4].replace("%", ""));
                    root.avatarPath = p[5];
                    if (p[6] === "1") {
                        root.isDesktop = false;
                    }
                }
            }
        }
    }
}
