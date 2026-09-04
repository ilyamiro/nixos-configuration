import QtQuick
import Quickshell
import Quickshell.Io
import "faces"
import "../"

Item {
    id: loaderRoot

    required property var screen
    required property string monitorName
    readonly property string safeMonitorName: (monitorName || "default").replace(/[^a-zA-Z0-9_-]/g, "_")

    property bool isRedacting: false

    function s(val) {
        return Math.round(Scaler.s(val));
    }

    ListModel { id: widgetsModel }

    function toBase64(str) {
        let utf8 = unescape(encodeURIComponent(str));
        let bytes = [];
        for (let i = 0; i < utf8.length; i++) {
            bytes.push(utf8.charCodeAt(i));
        }
        return Qt.btoa(bytes);
    }

    function saveNow() {
        saveTimer.stop();
        let data = [];
        for (let i = 0; i < widgetsModel.count; i++) {
            let item = widgetsModel.get(i);
            if (item.isRemoving) continue;
            let rawRot = (item.wRotation !== undefined && !isNaN(item.wRotation)) ? parseFloat(item.wRotation) : 0;
            let normRot = ((Math.round(rawRot) % 360) + 360) % 360;
            data.push({
                type: item.wType || "time",
                wType: item.wType || "time",
                wVariant: item.wVariant || WidgetRegistry.defaultVariant(item.wType || "time"),
                wX: item.wX,
                wY: item.wY,
                wWidth: item.wWidth,
                wHeight: item.wHeight,
                wOpacity: item.wOpacity !== undefined ? item.wOpacity : 1.0,
                wRotation: normRot,
                wImagePath: item.wImagePath || "",
                imagePath: item.wImagePath || "",
                wId: item.wId
            });
        }
        let jsonStr = JSON.stringify(data);
        let b64Data = toBase64(jsonStr);
        let targetDir = Caching.getStateDir("widgets/" + loaderRoot.safeMonitorName);
        let targetFile = targetDir + "/layout.json";
        let saveScript = "mkdir -p '" + targetDir + "' && printf '%s' '" + b64Data + "' | base64 -d > '" + targetFile + "'";
        Quickshell.execDetached(["bash", "-c", saveScript]);
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: loaderRoot.saveNow()
    }

    Process {
        id: loadProcess
        command: ["bash", "-c", "cat '" + Caching.getStateDir("widgets/" + loaderRoot.safeMonitorName) + "/layout.json' 2>/dev/null || echo '[]'"]
        property string output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => loadProcess.output += data
        }
        onExited: {
            let trimmed = output.trim();
            if (trimmed !== "") {
                try {
                    let data = JSON.parse(trimmed);
                    widgetsModel.clear();
                    let needSave = false;
                    for (let i = 0; i < data.length; i++) {
                        let item = data[i];
                        let itemId = item.wId || item.id;
                        if (!itemId) {
                            itemId = "w_" + Date.now() + "_" + i + "_" + Math.floor(Math.random() * 1000);
                            needSave = true;
                        }

                        let type = item.wType || item.type || "time";
                        let variant = item.wVariant || item.variant || WidgetRegistry.defaultVariant(type);
                        let defSize = WidgetRegistry.defaultSize(type);

                        let w = item.wWidth !== undefined ? parseFloat(item.wWidth) : defSize.w;
                        let h = item.wHeight !== undefined ? parseFloat(item.wHeight) : defSize.h;
                        let x = item.wX !== undefined ? parseFloat(item.wX) : 100;
                        let y = item.wY !== undefined ? parseFloat(item.wY) : 100;
                        let op = item.wOpacity !== undefined ? parseFloat(item.wOpacity) : 1.0;
                        let rot = (item.wRotation !== undefined) ? parseFloat(item.wRotation) : (item.rotation !== undefined ? parseFloat(item.rotation) : 0);
                        if (isNaN(rot)) rot = 0;
                        rot = ((Math.round(rot) % 360) + 360) % 360;
                        let imgPath = item.wImagePath || item.imagePath || item.path || "";

                        widgetsModel.append({
                            wType: type,
                            wVariant: variant,
                            wX: x,
                            wY: y,
                            wWidth: w,
                            wHeight: h,
                            wOpacity: op,
                            wRotation: rot,
                            wImagePath: imgPath,
                            wId: String(itemId),
                            isRemoving: false
                        });
                    }
                    if (needSave) {
                        loaderRoot.saveNow();
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        loadProcess.running = true;
    }

    IpcHandler {
        target: "widgets-" + loaderRoot.safeMonitorName

        function setRedactMode(active: string): string {
            let flag = (active === "true" || active === "1");
            if (!flag && loaderRoot.isRedacting) {
                loaderRoot.saveNow();
            }
            loaderRoot.isRedacting = flag;
            return "ok";
        }

        function save(): string {
            loaderRoot.saveNow();
            return "ok";
        }

        function reload(): string {
            loaderRoot.saveNow();
            loadProcess.output = "";
            loadProcess.running = false;
            loadProcess.running = true;
            return "ok";
        }

        function add(id: string, type: string, x: string, y: string, w: string, h: string, op: string, imgPath: string, rot: string): string {
            let defSize = WidgetRegistry.defaultSize(type);
            let variant = WidgetRegistry.defaultVariant(type);
            let rotVal = (rot !== undefined && rot !== "") ? parseFloat(rot) : 0;
            if (isNaN(rotVal)) rotVal = 0;

            widgetsModel.append({
                wType: type,
                wVariant: variant,
                wX: x !== undefined ? parseFloat(x) : 100,
                wY: y !== undefined ? parseFloat(y) : 100,
                wWidth: w !== undefined ? parseFloat(w) : defSize.w,
                wHeight: h !== undefined ? parseFloat(h) : defSize.h,
                wOpacity: op !== undefined ? parseFloat(op) : 1.0,
                wRotation: rotVal,
                wImagePath: imgPath !== undefined ? imgPath : "",
                wId: String(id).trim(),
                isRemoving: false
            });
            loaderRoot.saveNow();
            return "ok";
        }

        function geometry(id: string, x: string, y: string, w: string, h: string, op: string, rot: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "wX", parseFloat(x));
                    widgetsModel.setProperty(i, "wY", parseFloat(y));
                    widgetsModel.setProperty(i, "wWidth", parseFloat(w));
                    widgetsModel.setProperty(i, "wHeight", parseFloat(h));
                    if (op !== undefined) {
                        widgetsModel.setProperty(i, "wOpacity", parseFloat(op));
                    }
                    if (rot !== undefined && rot !== "") {
                        let r = parseFloat(rot);
                        if (!isNaN(r)) widgetsModel.setProperty(i, "wRotation", r);
                    }
                    saveTimer.restart();
                    return "ok";
                }
            }
            return "not_found";
        }

        function rotate(id: string, rot: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    let r = (rot !== undefined && rot !== "") ? parseFloat(rot) : 0;
                    if (isNaN(r)) r = 0;
                    widgetsModel.setProperty(i, "wRotation", r);
                    saveTimer.restart();
                    return "ok";
                }
            }
            return "not_found";
        }

        function opacity(id: string, op: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "wOpacity", parseFloat(op));
                    saveTimer.restart();
                    return "ok";
                }
            }
            return "not_found";
        }

        function imagePath(id: string, path: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "wImagePath", path);
                    loaderRoot.saveNow();
                    return "ok";
                }
            }
            return "not_found";
        }

        function move(id: string, x: string, y: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                if (String(widgetsModel.get(i).wId).trim() === target) {
                    widgetsModel.setProperty(i, "wX", parseFloat(x));
                    widgetsModel.setProperty(i, "wY", parseFloat(y));
                    saveTimer.restart();
                    return "ok";
                }
            }
            return "not_found";
        }

        function resize(id: string, w: string, h: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "wWidth", parseFloat(w));
                    widgetsModel.setProperty(i, "wHeight", parseFloat(h));
                    saveTimer.restart();
                    return "ok";
                }
            }
            return "not_found";
        }

        function variant(id: string, variant: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "wVariant", variant);
                    loaderRoot.saveNow();
                    return "ok";
                }
            }
            return "not_found";
        }

        function remove(id: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (item && String(item.wId).trim() === target) {
                    widgetsModel.setProperty(i, "isRemoving", true);
                    loaderRoot.saveNow();
                    return "ok";
                }
            }
            return "not_found";
        }

        function bringToFront(id: string): string {
            let target = String(id).trim();
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (String(item.wId).trim() === target) {
                    if (i < widgetsModel.count - 1) {
                        let rotVal = (item.wRotation !== undefined && !isNaN(item.wRotation)) ? item.wRotation : 0;
                        let obj = {
                            wType: item.wType || "time",
                            wVariant: item.wVariant || WidgetRegistry.defaultVariant(item.wType || "time"),
                            wX: item.wX,
                            wY: item.wY,
                            wWidth: item.wWidth,
                            wHeight: item.wHeight,
                            wOpacity: item.wOpacity !== undefined ? item.wOpacity : 1.0,
                            wRotation: rotVal,
                            wImagePath: item.wImagePath || "",
                            imagePath: item.wImagePath || "",
                            wId: item.wId,
                            isRemoving: false
                        };
                        widgetsModel.remove(i, 1);
                        widgetsModel.append(obj);
                        loaderRoot.saveNow();
                    }
                    return "ok";
                }
            }
            return "not_found";
        }

        function clear(): string {
            for (let i = 0; i < widgetsModel.count; i++) {
                widgetsModel.setProperty(i, "isRemoving", true);
            }
            loaderRoot.saveNow();
            return "ok";
        }

        function list(): string {
            let data = [];
            for (let i = 0; i < widgetsModel.count; i++) {
                let item = widgetsModel.get(i);
                if (item.isRemoving) continue;
                let rotVal = (item.wRotation !== undefined && !isNaN(item.wRotation)) ? item.wRotation : 0;
                data.push({
                    type: item.wType || "time",
                    wType: item.wType || "time",
                    wVariant: item.wVariant || WidgetRegistry.defaultVariant(item.wType || "time"),
                    wX: item.wX,
                    wY: item.wY,
                    wWidth: item.wWidth,
                    wHeight: item.wHeight,
                    wOpacity: item.wOpacity !== undefined ? item.wOpacity : 1.0,
                    wRotation: rotVal,
                    wImagePath: item.wImagePath || "",
                    imagePath: item.wImagePath || "",
                    wId: item.wId
                });
            }
            return JSON.stringify(data);
        }
    }

    Instantiator {
        id: widgetInstantiator
        model: widgetsModel
        delegate: Widget {
            screen: loaderRoot.screen
            visible: !loaderRoot.isRedacting && !(model.isRemoving || false)
            wId: model.wId
            wType: model.wType
            wVariant: model.wVariant
            wX: model.wX
            wY: model.wY
            wWidth: model.wWidth
            wHeight: model.wHeight
            wOpacity: model.wOpacity !== undefined ? model.wOpacity : 1.0
            wRotation: (model.wRotation !== undefined && !isNaN(model.wRotation)) ? model.wRotation : 0
            wImagePath: model.wImagePath || ""
        }
    }
}
