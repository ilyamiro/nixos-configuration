pragma Singleton
import QtQuick
import Quickshell
import "../"

// The Clash-compatible RESTful controller, spoken to directly over HTTP.
//
// mihomo, clash-meta, clash-verge and FlClash all expose the same API on a
// loopback port, so nothing here is tied to a particular launcher: whatever is
// already running the tunnel is what this talks to. The shell does not start
// the core, own its config, or know how it was installed.
//
// Address and secret come from settings because neither has a safe default to
// assume. 127.0.0.1:9090 is only mihomo's own default; a controller reached
// over a different port, or one with external-controller bound elsewhere, is
// ordinary. An empty secret means the controller was left unauthenticated,
// which is the common case on loopback.
Singleton {
    id: root

    readonly property var settings: Config.getSetting("vpn", ({}))

    readonly property string base: (settings && settings.controller)
        ? String(settings.controller).replace(/\/+$/, "")
        : "http://127.0.0.1:9090"
    readonly property string secret: (settings && settings.secret) ? String(settings.secret) : ""

    // Whether the last request got an answer at all. The panel binds its
    // "tunnel is up" state to this instead of polling for it separately.
    property bool reachable: false

    // Where latency is measured from. A generate_204 endpoint rather than a
    // real page: the response is empty, so the number is round-trip time and
    // not the size of somebody's homepage.
    readonly property string probeUrl: (settings && settings.probeUrl)
        ? String(settings.probeUrl) : "http://www.gstatic.com/generate_204"

    function _request(method, path, body, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            // Status 0 is "nothing answered", which is the ordinary state of a
            // tunnel that is down -- not a failure worth surfacing as text.
            if (xhr.status === 0) {
                root.reachable = false;
                if (done) done(null, "");
                return;
            }
            root.reachable = true;

            let parsed = null;
            if (xhr.responseText) {
                try {
                    parsed = JSON.parse(xhr.responseText);
                } catch (e) {
                    parsed = null;
                }
            }
            if (xhr.status >= 400) {
                if (done) done(parsed, (parsed && parsed.message) || ("HTTP " + xhr.status));
                return;
            }
            if (done) done(parsed, "");
        };
        xhr.open(method, root.base + path);
        if (root.secret !== "") xhr.setRequestHeader("Authorization", "Bearer " + root.secret);
        if (body === null || body === undefined) {
            xhr.send();
            return;
        }
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(body));
    }

    function version(done) {
        root._request("GET", "/version", null, done);
    }

    function proxies(done) {
        root._request("GET", "/proxies", null, done);
    }

    function select(group, node, done) {
        root._request("PUT", "/proxies/" + encodeURIComponent(group), { name: node }, done);
    }

    // The whole group in one request. Probing node by node is fifty round trips
    // that each hold a socket open for the timeout, and the core already
    // parallelises this internally.
    function groupDelay(group, timeout, done) {
        root._request("GET", "/group/" + encodeURIComponent(group) + "/delay"
            + "?timeout=" + timeout + "&url=" + encodeURIComponent(root.probeUrl),
            null, done);
    }

    function nodeDelay(node, timeout, done) {
        root._request("GET", "/proxies/" + encodeURIComponent(node) + "/delay"
            + "?timeout=" + timeout + "&url=" + encodeURIComponent(root.probeUrl),
            null, done);
    }

    // Established connections keep flowing through whichever node they were
    // opened on, so without this a switch looks like it did not take.
    function closeConnections(done) {
        root._request("DELETE", "/connections", null, done);
    }

    // The config the core is running, which is the only way to know which
    // profile is loaded without being told by whatever started it.
    function configs(done) {
        root._request("GET", "/configs", null, done);
    }

    // Reload from a path on disk. This is how a profile is switched without
    // restarting the core: the file has to exist already -- the shell does not
    // fetch, parse or assemble configs, and deliberately so.
    function loadConfig(path, done) {
        root._request("PUT", "/configs?force=true", { path: path }, done);
    }

    // Mode is part of the running config rather than a separate endpoint.
    function setMode(mode, done) {
        root._request("PATCH", "/configs", { mode: mode }, done);
    }
}
