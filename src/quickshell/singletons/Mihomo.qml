pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Tunnel state for the shell, on top of a Clash-compatible controller.
//
// What this does and does not do is a deliberate line. Everything the
// controller already knows -- which groups exist, which node each one carries,
// what the latencies are, how much is flowing -- is read straight from it over
// HTTP and needs nothing else installed. Everything that is really a package
// manager's job -- fetching a subscription, probing user agents for a
// provider's real node list, parsing share links, assembling YAML -- is not
// here and should not be. That work is fragile, provider-specific, and
// reimplementing it in QML to put a node switch behind it would produce
// something worse than the tools that already do it.
//
// So: bring your own core and your own configs. mihomo, clash-verge, FlClash
// and anything else speaking the same API all work, because the shell only
// ever asks the controller questions.
Singleton {
    id: root

    readonly property var settings: Config.getSetting("vpn", ({}))

    function _s(key, fallback) {
        return (root.settings && root.settings[key] !== undefined && root.settings[key] !== "")
            ? root.settings[key] : fallback;
    }

    // ── state ──

    // There is no separate "is it running" question to ask: a controller that
    // answers is a core that is up. Nothing is polled to find this out beyond
    // the heartbeat below.
    readonly property bool controllerUp: MihomoApi.reachable
    readonly property alias running: root.controllerUp

    property string lastError: ""
    property bool busy: false

    // Every proxy's type by name, groups and nodes alike. A group's member list
    // mixes real servers with the built-ins, and only the type tells them apart.
    property var proxyTypes: ({})

    // [{ name, type, now, nodes }] for every group the user can act on.
    property var groups: []
    readonly property string primaryGroup: root._s("primaryGroup", "PROXY")

    // node name -> delay in ms, or null when the probe failed.
    property var delays: ({})
    property bool probing: false

    // rule / global / direct, as the controller reports it.
    property string mode: ""

    // Bytes per second, from the controller's streaming endpoint.
    property real upSpeed: 0
    property real downSpeed: 0

    // Where traffic comes out. Deliberately not part of anything automatic:
    // it is a request to a third party and should happen because somebody
    // asked for it.
    property var egress: null
    property bool checking: false

    // Set by the panel while it is on screen. The traffic stream and the fast
    // heartbeat exist to answer questions nobody is asking when nothing is
    // displaying the answer.
    property bool watched: false

    // Switching node without this leaves every established connection on the
    // old one, which reads as the switch not having worked.
    readonly property bool resetOnSwitch: root._s("resetOnSwitch", true)

    // ── helpers ──

    function groupNamed(name) {
        for (const g of root.groups) {
            if (g.name === name) return g;
        }
        return null;
    }

    // Members that are not nodes: the two built-ins, and any nested group.
    // A group has no latency of its own, and recording the probe's silence as
    // a failure paints AUTO red -- the one row worth picking when every node
    // beside it is red.
    function measurable(name) {
        return name !== "DIRECT" && name !== "REJECT" && !root.groupNamed(name);
    }

    readonly property var primary: root.groupNamed(root.primaryGroup)
    readonly property string currentNode: root.primary ? (root.primary.now || "") : ""
    readonly property var currentDelay: root.delays[root.currentNode]

    function formatSpeed(bytes) {
        if (bytes < 1024) return Math.round(bytes) + " B/s";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + " KB/s";
        return (bytes / 1048576).toFixed(1) + " MB/s";
    }

    // ── controller-driven ──

    function refresh() {
        root.refreshNodes();
        MihomoApi.configs((data, err) => {
            if (err || !data) return;
            root.mode = data.mode || "";
        });
    }

    function refreshNodes() {
        MihomoApi.proxies((data, err) => {
            if (err || !data || !data.proxies) {
                root.groups = [];
                return;
            }
            const out = [];
            const types = {};
            for (const name in data.proxies) {
                const entry = data.proxies[name];
                types[name] = entry.type || "";
                // Only groups the user can act on. Every individual node is in
                // this map too, and GLOBAL lists all of them a second time.
                if (entry.type !== "Selector" && entry.type !== "URLTest"
                    && entry.type !== "Fallback") continue;
                out.push({
                    name: name,
                    type: entry.type,
                    now: entry.now || "",
                    nodes: entry.all || []
                });
            }
            // Primary first, then alphabetically: the panel opens on the group
            // that actually carries traffic.
            out.sort((a, b) => {
                if (a.name === root.primaryGroup) return -1;
                if (b.name === root.primaryGroup) return 1;
                return a.name.localeCompare(b.name);
            });
            root.proxyTypes = types;
            root.groups = out;
        });
    }

    function select(group, node) {
        // Applied optimistically: the controller switch is immediate, and a
        // round trip before the checkmark moves reads as an unresponsive list.
        root.groups = root.groups.map(g =>
            g.name === group ? Object.assign({}, g, { now: node }) : g);

        MihomoApi.select(group, node, (data, err) => {
            if (err) {
                root.lastError = err;
                root.refreshNodes();
                return;
            }
            if (root.resetOnSwitch) MihomoApi.closeConnections(null);
            // The old reading belongs to the old node's route, and the panel is
            // now showing it as this node's exit.
            root.egress = null;
        });
    }

    function setMode(mode) {
        const previous = root.mode;
        root.mode = mode;
        MihomoApi.setMode(mode, (data, err) => {
            if (!err) return;
            root.lastError = err;
            root.mode = previous;
        });
    }

    function probeDelays(group) {
        if (root.probing) return;
        const name = group || root.primaryGroup;
        const target = root.groupNamed(name);
        if (!target) return;

        root.probing = true;
        // Generous, because the group is probed in parallel: this is one 5s
        // wait for the slowest node, not five seconds per node. At 3s several
        // perfectly usable nodes come back as dead.
        MihomoApi.groupDelay(name, 5000, (data, err) => {
            if (err) {
                root.probing = false;
                root.lastError = err;
                return;
            }
            // Nodes that failed the probe are absent from the reply rather than
            // reported as zero, so a miss has to be written down explicitly or
            // the previous reading would silently stand in for it.
            const next = Object.assign({}, root.delays);
            const missing = [];
            for (const node of target.nodes) {
                if (!root.measurable(node)) continue;
                if (data && data[node] !== undefined) next[node] = data[node];
                else missing.push(node);
            }
            root.delays = next;
            if (missing.length === 0) {
                root.probing = false;
                return;
            }
            root._probeEach(missing);
        });
    }

    // What a group probe left out, asked for one node at a time.
    //
    // Not every core answers a group probe the same way: some report the
    // group's own members -- AUTO, DIRECT -- and leave the nodes themselves
    // out, which leaves every row blank. A node the group did not report is
    // worth asking about individually anyway: absent from a group reply means
    // "no measurement", which is not the same as "dead".
    function _probeEach(names) {
        const next = Object.assign({}, root.delays);
        let pending = names.length;
        for (const node of names) {
            MihomoApi.nodeDelay(node, 5000, (data, err) => {
                next[node] = (!err && data && data.delay !== undefined) ? data.delay : null;
                pending -= 1;
                if (pending > 0) return;
                root.delays = next;
                root.probing = false;
            });
        }
    }

    // Probes only what has never been measured. Opening the panel should show
    // latencies without being asked, but re-probing a list the user is already
    // looking at costs seconds of controller work to redraw the same numbers.
    function probeDelaysIfStale(group) {
        const target = root.groupNamed(group || root.primaryGroup);
        if (!target) return;
        for (const node of target.nodes) {
            if (!root.measurable(node)) continue;
            if (root.delays[node] === undefined) {
                root.probeDelays(group);
                return;
            }
        }
    }

    function resetConnections() {
        MihomoApi.closeConnections(null);
    }

    // ── the core's own lifetime ──
    //
    // The shell does not know how the core was installed or who supervises it,
    // and guessing wrongly here means a button that silently does nothing. So
    // the commands are configured, and when they are not set the panel does
    // not offer to start or stop anything.

    readonly property string startCommand: root._s("startCommand", "")
    readonly property string stopCommand: root._s("stopCommand", "")
    readonly property bool canControlService: root.startCommand !== "" || root.stopCommand !== ""

    function start() {
        if (root.startCommand === "" || root.busy) return;
        root.busy = true;
        root.lastError = "";
        serviceProc.command = ["bash", "-lc", root.startCommand];
        serviceProc.running = true;
    }

    function stop() {
        if (root.stopCommand === "" || root.busy) return;
        root.busy = true;
        root.lastError = "";
        serviceProc.command = ["bash", "-lc", root.stopCommand];
        serviceProc.running = true;
    }

    property Process serviceProc: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text ? text.trim() : "";
                if (t !== "") root.lastError = t.split("\n")[0];
            }
        }
        onExited: (code) => {
            root.busy = false;
            // The core needs a moment to bind its controller port, and the
            // heartbeat is what will notice; asking immediately reports the
            // state from before the command ran.
            settleTimer.restart();
        }
    }

    property Timer _settle: Timer {
        id: settleTimer
        interval: 1200
        repeat: false
        onTriggered: {
            MihomoApi.version(null);
            root.refresh();
        }
    }

    // ── profiles ──
    //
    // Switching between configs the core already has on disk. This is not
    // subscription management: nothing is downloaded, parsed or written. The
    // file exists or it does not.

    readonly property string profilesDir: root._s("profilesDir", "")
    property var profiles: []
    property string currentProfile: ""

    function refreshProfiles() {
        if (root.profilesDir === "") {
            root.profiles = [];
            return;
        }
        profilesProc.command = ["bash", "-lc",
            "ls -1 '" + root.profilesDir + "'/*.yaml '" + root.profilesDir + "'/*.yml 2>/dev/null"];
        profilesProc.running = true;
        MihomoApi.configs((data, err) => {
            if (!err && data) root.currentProfile = data["config-file"] || "";
        });
    }

    function loadProfile(path) {
        root.busy = true;
        MihomoApi.loadConfig(path, (data, err) => {
            root.busy = false;
            if (err) {
                root.lastError = err;
                return;
            }
            root.currentProfile = path;
            root.delays = ({});
            root.refresh();
        });
    }

    property Process profilesProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text ? text.trim() : "";
                root.profiles = out === "" ? [] : out.split("\n");
            }
        }
    }

    // ── where traffic comes out ──

    readonly property string egressUrl: root._s("egressUrl", "https://ipinfo.io/json")

    function check() {
        if (root.checking || root.egressUrl === "") return;
        root.checking = true;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.checking = false;
            if (xhr.status !== 200) {
                root.egress = null;
                root.lastError = xhr.status === 0 ? "" : ("HTTP " + xhr.status);
                return;
            }
            try {
                const j = JSON.parse(xhr.responseText);
                // ipinfo, ip-api and ipwho.is disagree on field names; take
                // whichever of them answered rather than demanding one.
                root.egress = {
                    ip: j.ip || j.query || "",
                    country: j.country || j.countryCode || j.country_code || ""
                };
            } catch (e) {
                root.egress = null;
            }
        };
        xhr.open("GET", root.egressUrl);
        xhr.send();
    }

    // ── the tunnel's DNS ──
    //
    // A tunnel can be up while names do not resolve, and from outside that
    // looks like a working VPN with no internet.
    //
    // DNS inside a TUN normally rests on the core hijacking port 53 itself, so
    // systemd-resolved is not needed for it. But with auto-route the core may
    // also register the interface with resolved, and what goes in there is an
    // address from its own fake-ip range. If that registration succeeded, the
    // resolver sends queries nowhere. So a DNS server on the tunnel interface
    // is a sign of breakage, not of health.

    readonly property string tunDevice: root._s("tunDevice", "")
    property bool resolvedHijacked: false

    function checkTunDns() {
        if (!root.running || root.tunDevice === "") {
            root.resolvedHijacked = false;
            return;
        }
        dnsProc.command = ["bash", "-lc",
            "command -v resolvectl >/dev/null 2>&1 || exit 0; "
            + "resolvectl status '" + root.tunDevice + "' 2>/dev/null | grep -c 'DNS Servers'"];
        dnsProc.running = true;
    }

    property Process dnsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.resolvedHijacked = (parseInt(text.trim(), 10) || 0) > 0;
            }
        }
    }

    // ── traffic ──
    // The controller streams a line of JSON per second. A subscription rather
    // than a poll: nothing is asked for and nothing is spent while the tunnel
    // is down. curl rather than XMLHttpRequest because this is the one endpoint
    // that never completes, and SplitParser already handles line-delimited
    // streams elsewhere in the shell.
    //
    // Gated on trafficWanted as well as on the tunnel, because the stream has
    // to be restartable. Assigning to `running` directly would replace the
    // binding, and the stream would then never stop when the tunnel does.
    property bool trafficWanted: true

    property Process trafficProc: Process {
        running: root.controllerUp && root.watched && root.trafficWanted
        command: MihomoApi.secret === ""
            ? ["curl", "-sN", "--max-time", "0", MihomoApi.base + "/traffic"]
            : ["curl", "-sN", "--max-time", "0", "-H",
               "Authorization: Bearer " + MihomoApi.secret, MihomoApi.base + "/traffic"]
        stdout: SplitParser {
            onRead: line => {
                if (!line) return;
                try {
                    const j = JSON.parse(line);
                    root.upSpeed = j.up || 0;
                    root.downSpeed = j.down || 0;
                } catch (e) {
                    // A partial line at stream start is not worth reporting.
                }
            }
        }
        onExited: {
            root.upSpeed = 0;
            root.downSpeed = 0;
            if (!root.watched) return;
            // This stream ends when the core does, and nothing else here would
            // notice a daemon that died on its own.
            root.trafficWanted = false;
            trafficRetry.restart();
        }
    }

    property Timer _trafficRetry: Timer {
        id: trafficRetry
        interval: 2000
        onTriggered: root.trafficWanted = true
    }

    // ── heartbeat ──
    //
    // One request to a loopback port, which is how the bar chip knows the
    // tunnel went away without anything having to tell it. Slow while nobody
    // is looking, brisk while the panel is open.
    property Timer _heartbeat: Timer {
        interval: root.watched ? 3000 : 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            MihomoApi.version(null);
            if (root.watched) root.refreshNodes();
        }
    }
}
