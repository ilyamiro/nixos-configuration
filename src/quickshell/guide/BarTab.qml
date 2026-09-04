import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"
import "../reusables"

Item {
    id: barTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property real cardRadius: ThemeBackend.clampedBorderRadius

    onVisibleChanged: {
        if (visible) {
            syncSettings();
            loadModuleModels();
        } else {
            clearPendingGroup();
            if (barPosDropdown.isOpen) barPosDropdown.closePopup();
        }
    }

    property var defaultBarSettings: {
        "position": "top",
        "width": 100,
        "opacity": 100,
        "style": "modular",
        "distinctPills": false,
        "time": {"format": "HH:mm:ss"},
        "autohide": false,
        "autohideTimeout": 1000,
        "workspaceCount": 8,
        "workspaceGroupsPerMonitor": false,
        "groupColors": {},
        "modules": {
            "left": ["left", "workspaces", "media"],
            "center": ["timedate", "info", "weather"],
            "right": ["tray", ["kb", "wifi", "bt", "vol", "bat"]]
        }
    }

    property var barSettings: Config.getSetting("bar", defaultBarSettings)
    property string barPosition: barSettings.position !== undefined ? barSettings.position : "top"
    property real currentBarWidth: barSettings.width !== undefined ? barSettings.width : 100
    property real currentBarOpacity: barSettings.opacity !== undefined ? barSettings.opacity : 100
    property string barStyle: {
        let s = barSettings.style;
        if (typeof s === "string") return s;
        if (s && typeof s === "object") {
            if (s.fill || s.mode === "fill") return "fill";
            if (s.solid || s.mode === "solid") return "solid";
        }
        return "modular";
    }
    property bool distinctPills: barSettings.distinctPills !== undefined ? barSettings.distinctPills : false
    property string timeFormat: barSettings.time && barSettings.time.format !== undefined ? barSettings.time.format : "HH:mm:ss"
    property bool autohide: barSettings.autohide !== undefined ? barSettings.autohide : false
    property int autohideTimeout: barSettings.autohideTimeout !== undefined ? barSettings.autohideTimeout : 1000
    property int workspaceCount: barSettings.workspaceCount !== undefined ? barSettings.workspaceCount : 8
    property bool workspaceGroupsPerMonitor: barSettings.workspaceGroupsPerMonitor !== undefined ? barSettings.workspaceGroupsPerMonitor : false

    ListModel { id: leftModel }
    ListModel { id: centerModel }
    ListModel { id: rightModel }
    ListModel { id: availableModel }

    property string currentPlaceholderList: ""
    property int currentPlaceholderIndex: -1

    property string pendingGroupModuleId: ""
    property string pendingGroupList: ""
    property var assignedGroupColors: barSettings.groupColors || ({})

    property string lastSavedModulesString: ""

    Timer {
        id: barWidthDebounceTimer
        interval: 100
        repeat: false
        onTriggered: {
            barTabRoot.updateBarSettings();
        }
    }

    function clearPendingGroup() {
        barTabRoot.pendingGroupModuleId = "";
        barTabRoot.pendingGroupList = "";
    }

    function getValidItemCount(m) {
        if (!m) return 0;
        let count = 0;
        for (let i = 0; i < m.count; i++) {
            let it = m.get(i);
            if (it && !it.isPlaceholder) count++;
        }
        return count;
    }

    function getModulesString(modulesObj) {
        if (!modulesObj) return "";
        return JSON.stringify({
            center: modulesObj.center || [],
            left: modulesObj.left || [],
            right: modulesObj.right || []
        });
    }

    function colorToString(c) {
        if (!c) return "#000000";
        if (typeof c === "string") return c;
        if (typeof c === "object" && c.hex) return String(c.hex);
        return String(c);
    }

    function getAllColors() {
        let colors = [
            ThemeBackend.mauve,
            ThemeBackend.pink,
            ThemeBackend.lavender,
            ThemeBackend.blue,
            ThemeBackend.sapphire,
            ThemeBackend.teal,
            ThemeBackend.green,
            ThemeBackend.yellow,
            ThemeBackend.peach,
            ThemeBackend.flamingo
        ];
        let res = [];
        for (let i = 0; i < colors.length; i++) {
            if (colors[i] !== undefined) {
                res.push(colorToString(colors[i]));
            }
        }
        return res;
    }

    function assignGroupColor(gId) {
        if (!gId || gId === "") return;
        if (barTabRoot.assignedGroupColors && barTabRoot.assignedGroupColors[gId]) return;

        let palette = barTabRoot.getAllColors();
        let used = Object.values(barTabRoot.assignedGroupColors || {});

        let chosenColor = "";
        for (let i = 0; i < palette.length; i++) {
            if (used.indexOf(palette[i]) === -1) {
                chosenColor = palette[i];
                break;
            }
        }
        if (chosenColor === "") {
            let count = Object.keys(barTabRoot.assignedGroupColors || {}).length;
            chosenColor = palette[count % palette.length];
        }

        let newAssigned = Object.assign({}, barTabRoot.assignedGroupColors || {});
        newAssigned[gId] = chosenColor;
        barTabRoot.assignedGroupColors = newAssigned;
    }

    function getGroupColor(gId) {
        if (!gId || gId === "") return colorToString(ThemeBackend.surface0);
        if (barTabRoot.assignedGroupColors && barTabRoot.assignedGroupColors[gId]) {
            return barTabRoot.assignedGroupColors[gId];
        }
        let palette = barTabRoot.getAllColors();
        if (!palette || palette.length === 0) return colorToString(ThemeBackend.surface0);
        let hash = 0;
        for (let i = 0; i < gId.length; i++) {
            hash = ((hash << 5) - hash) + gId.charCodeAt(i);
            hash |= 0;
        }
        return palette[Math.abs(hash) % palette.length] || colorToString(ThemeBackend.surface0);
    }

    function getContrastTextColor(bg) {
        let c = Qt.color(bg);
        let bgLum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        let tColor = Qt.color(ThemeBackend.text);
        let tLum = 0.2126 * tColor.r + 0.7152 * tColor.g + 0.0722 * tColor.b;
        let cColor = Qt.color(ThemeBackend.crust);
        let cLum = 0.2126 * cColor.r + 0.7152 * cColor.g + 0.0722 * cColor.b;
        if (bgLum > 0.5) {
            return tLum < cLum ? ThemeBackend.text : ThemeBackend.crust;
        } else {
            return tLum > cLum ? ThemeBackend.text : ThemeBackend.crust;
        }
    }

    function getModuleInfo(id) {
        let labels = {
            "left": I18n.t("guide.bar.modules.actions"),
            "workspaces": I18n.t("guide.bar.modules.workspaces"),
            "focus": I18n.t("guide.bar.modules.focus"),
            "timedate": I18n.t("guide.bar.modules.timedate"),
            "info": I18n.t("guide.bar.modules.info"),
            "weather": I18n.t("guide.bar.modules.weather"),
            "media": I18n.t("guide.bar.modules.media"),
            "vis": I18n.t("guide.bar.modules.vis"),
            "tray": I18n.t("guide.bar.modules.tray"),
            "sysmon": I18n.t("guide.bar.modules.sysmon"),
            "kb": I18n.t("guide.bar.modules.keyboard"),
            "wifi": I18n.t("guide.bar.modules.network"),
            "bt": I18n.t("guide.bar.modules.bluetooth"),
            "vol": I18n.t("guide.bar.modules.volume"),
            "bat": I18n.t("guide.bar.modules.battery")
        };
        let icons = {
            "left": "󰍜",
            "workspaces": "󰮯",
            "focus": "󰈈",
            "timedate": "󰃰",
            "info": "󰋼",
            "weather": "󰖐",
            "media": "󰎈",
            "vis": "󰝚",
            "tray": "󱊞",
            "sysmon": "󰍛",
            "kb": "󰌌",
            "wifi": "󰤨",
            "bt": "󰂲",
            "vol": "󰕾",
            "bat": "󰁹"
        };
        let colors = {
            "left": ThemeBackend.blue,
            "workspaces": ThemeBackend.mauve,
            "focus": ThemeBackend.teal,
            "timedate": ThemeBackend.peach,
            "info": ThemeBackend.red,
            "weather": ThemeBackend.yellow,
            "media": ThemeBackend.green,
            "vis": ThemeBackend.mauve,
            "tray": ThemeBackend.yellow,
            "sysmon": ThemeBackend.mauve,
            "kb": ThemeBackend.text,
            "wifi": ThemeBackend.blue,
            "bt": ThemeBackend.mauve,
            "vol": ThemeBackend.peach,
            "bat": ThemeBackend.green
        };
        return {
            "moduleId": id,
            "moduleLabel": labels[id] || id,
            "moduleIcon": icons[id] || "󰅂",
            "moduleColor": colorToString(colors[id] || ThemeBackend.text),
            "isPlaceholder": false,
            "placeholderWidth": 0,
            "groupId": ""
        };
    }

    function loadModuleModels() {
        let ms = barTabRoot.barSettings.modules;
        if (!ms) ms = barTabRoot.defaultBarSettings.modules;

        let l = ms.left ? JSON.parse(JSON.stringify(ms.left)) : [];
        let c = ms.center ? JSON.parse(JSON.stringify(ms.center)) : [];
        let r = ms.right ? JSON.parse(JSON.stringify(ms.right)) : [];

        function migrate(arr) {
            if (!arr) return [];
            var res = [];
            for (var i = 0; i < arr.length; i++) {
                if (Array.isArray(arr[i])) {
                    var group = [];
                    for (var j = 0; j < arr[i].length; j++) {
                        if (arr[i][j] === "system") group.push("sysmon", "kb", "wifi", "bt", "vol", "bat");
                        else if (arr[i][j] === "centerbox" || arr[i][j] === "center") group.push("timedate", "info", "weather");
                        else group.push(arr[i][j]);
                    }
                    if (group.length === 1) res.push(group[0]);
                    else if (group.length > 1) res.push(group);
                } else {
                    if (arr[i] === "system") res.push(...["sysmon", "kb", "wifi", "bt", "vol", "bat"]);
                    else if (arr[i] === "centerbox" || arr[i] === "center") res.push(...["timedate", "info", "weather"]);
                    else res.push(arr[i]);
                }
            }
            return res;
        }

        l = migrate(l);
        c = migrate(c);
        r = migrate(r);

        if (!l.length && !c.length && !r.length && ms.active) {
            let order = migrate(ms.active);
            let cIdx = -1;
            for (let i = 0; i < order.length; i++) {
                if (order[i] === "center" || (Array.isArray(order[i]) && order[i].indexOf("center") !== -1)) { cIdx = i; break; }
            }
            for (let i = 0; i < order.length; i++) {
                if (order[i] === "center" || (Array.isArray(order[i]) && order[i].indexOf("center") !== -1)) continue;
                if (cIdx === -1 || i < cIdx) l.push(order[i]);
                else r.push(order[i]);
            }
            c = ["timedate", "info", "weather"];
        }

        function filterCenter(arr) {
            let out = [];
            for (let i = 0; i < arr.length; i++) {
                if (Array.isArray(arr[i])) {
                    let filtered = arr[i].filter(id => id !== "center" && id !== "centerbox");
                    if (filtered.length === 1) out.push(filtered[0]);
                    else if (filtered.length > 1) out.push(filtered);
                } else if (arr[i] !== "center" && arr[i] !== "centerbox") {
                    out.push(arr[i]);
                }
            }
            return out;
        }

        l = filterCenter(l);
        c = filterCenter(c);
        r = filterCenter(r);

        leftModel.clear();
        centerModel.clear();
        rightModel.clear();
        availableModel.clear();

        let used = {};
        function add(arr, model) {
            for (var i = 0; i < arr.length; i++) {
                if (Array.isArray(arr[i])) {
                    var gId = "g_" + arr[i][0];
                    barTabRoot.assignGroupColor(gId);
                    for (var j = 0; j < arr[i].length; j++) {
                        var info = getModuleInfo(arr[i][j]);
                        info.groupId = gId;
                        model.append(info);
                        used[arr[i][j]] = true;
                    }
                } else {
                    var info = getModuleInfo(arr[i]);
                    info.groupId = "";
                    model.append(info);
                    used[arr[i]] = true;
                }
            }
        }
        add(l, leftModel);
        add(c, centerModel);
        add(r, rightModel);

        let allKeys = ["left", "workspaces", "focus", "timedate", "info", "weather", "media", "vis", "tray", "sysmon", "kb", "wifi", "bt", "vol", "bat"];
        for (let i = 0; i < allKeys.length; i++) {
            if (!used[allKeys[i]]) availableModel.append(getModuleInfo(allKeys[i]));
        }
    }

    function getModel(name) {
        if (name === "left") return leftModel;
        if (name === "center") return centerModel;
        if (name === "right") return rightModel;
        if (name === "available") return availableModel;
        return null;
    }

    function buildModelArray(model) {
        let res = [];
        let currentGroup = [];
        let currentGroupId = "";

        for (let i = 0; i < model.count; i++) {
            let item = model.get(i);
            if (item.isPlaceholder) continue;

            if (item.groupId && item.groupId !== "") {
                if (currentGroupId === item.groupId) {
                    currentGroup.push(item.moduleId);
                } else {
                    if (currentGroup.length > 0) {
                        res.push(currentGroup.length === 1 ? currentGroup[0] : currentGroup);
                    }
                    currentGroupId = item.groupId;
                    currentGroup = [item.moduleId];
                }
            } else {
                if (currentGroup.length > 0) {
                    res.push(currentGroup.length === 1 ? currentGroup[0] : currentGroup);
                    currentGroup = [];
                    currentGroupId = "";
                }
                res.push(item.moduleId);
            }
        }
        if (currentGroup.length > 0) {
            res.push(currentGroup.length === 1 ? currentGroup[0] : currentGroup);
        }
        return res;
    }

    function saveModuleModels() {
        let l = buildModelArray(leftModel);
        let c = buildModelArray(centerModel);
        let r = buildModelArray(rightModel);

        let current = Config.getSetting("bar", barTabRoot.defaultBarSettings);
        current.modules = { "left": l, "center": c, "right": r };
        current.groupColors = barTabRoot.assignedGroupColors;

        barTabRoot.lastSavedModulesString = barTabRoot.getModulesString(current.modules);
        Config.setSetting("bar", current);
    }

    function resetBarSettings() {
        clearPendingGroup();
        let current = Config.getSetting("bar", barTabRoot.defaultBarSettings);
        current.modules = JSON.parse(JSON.stringify(barTabRoot.defaultBarSettings.modules));
        current.groupColors = {};
        current.workspaceCount = barTabRoot.defaultBarSettings.workspaceCount;
        current.workspaceGroupsPerMonitor = barTabRoot.defaultBarSettings.workspaceGroupsPerMonitor;
        current.distinctPills = barTabRoot.defaultBarSettings.distinctPills;
        barTabRoot.assignedGroupColors = {};
        barTabRoot.workspaceCount = barTabRoot.defaultBarSettings.workspaceCount;
        barTabRoot.workspaceGroupsPerMonitor = barTabRoot.defaultBarSettings.workspaceGroupsPerMonitor;
        barTabRoot.distinctPills = barTabRoot.defaultBarSettings.distinctPills;
        barTabRoot.lastSavedModulesString = barTabRoot.getModulesString(current.modules);
        Config.setSetting("bar", current);
        barTabRoot.barSettings = current;
        barTabRoot.loadModuleModels();
    }

    function clearPlaceholders() {
        let models = [leftModel, centerModel, rightModel, availableModel];
        for (let m = 0; m < models.length; m++) {
            let model = models[m];
            for (let i = 0; i < model.count; i++) {
                if (model.get(i).isPlaceholder) {
                    model.remove(i, 1);
                    i--;
                }
            }
        }
    }

    function updatePlaceholder(listName, index, width, id, label, icon, sourceListName, sourceModuleId) {
        if (currentPlaceholderList === listName && currentPlaceholderIndex === index) return;

        clearPlaceholders();

        let model = getModel(listName);
        if (model) {
            let rawIndex = index;
            if (listName === sourceListName) {
                for (let i = 0; i < model.count; i++) {
                    let it = model.get(i);
                    if (!it.isPlaceholder && it.moduleId === sourceModuleId) {
                        if (index >= i) rawIndex = index + 1;
                        break;
                    }
                }
            }
            rawIndex = Math.max(0, Math.min(rawIndex, model.count));
            model.insert(rawIndex, {
                moduleId: id,
                moduleLabel: label,
                moduleIcon: icon,
                moduleColor: "#000000",
                isPlaceholder: true,
                placeholderWidth: width,
                groupId: ""
            });
        }
        currentPlaceholderList = listName;
        currentPlaceholderIndex = index;
    }

    function getPendingGroupId() {
        if (barTabRoot.pendingGroupModuleId === "") return "";
        if (barTabRoot.pendingGroupList === "") return "";
        let m = barTabRoot.getModel(barTabRoot.pendingGroupList);
        if (!m) return "";
        for (let i = 0; i < m.count; i++) {
            let it = m.get(i);
            if (it && it.moduleId === barTabRoot.pendingGroupModuleId) return it.groupId || "";
        }
        return "";
    }

    function cleanupGroups() {
        var mList = [leftModel, centerModel, rightModel, availableModel];
        var counts = {};
        var pendingGId = barTabRoot.getPendingGroupId();
        var i = 0;
        var j = 0;

        for (i = 0; i < mList.length; i++) {
            var m = mList[i];
            for (j = 0; j < m.count; j++) {
                var it = m.get(j);
                if (it && it.groupId && it.groupId !== "") {
                    counts[it.groupId] = (counts[it.groupId] || 0) + 1;
                }
            }
        }

        var dissolved = {};
        for (i = 0; i < mList.length; i++) {
            var m = mList[i];
            for (j = 0; j < m.count; j++) {
                var it = m.get(j);
                if (it && it.groupId && it.groupId !== "" && counts[it.groupId] < 2 && it.groupId !== pendingGId) {
                    var gId = it.groupId;
                    if (!dissolved[gId]) {
                        dissolved[gId] = true;
                        if (barTabRoot.assignedGroupColors[gId]) {
                            var newAssigned = Object.assign({}, barTabRoot.assignedGroupColors);
                            delete newAssigned[gId];
                            barTabRoot.assignedGroupColors = newAssigned;
                        }
                    }
                    m.setProperty(j, "groupId", "");
                }
            }
        }
    }

    function uniteElements(pendingId, targetId, listName) {
        if (pendingId === targetId) return;
        let m = barTabRoot.getModel(listName);
        if (!m) return;
        let pIdx = -1;
        let tIdx = -1;

        for (let i = 0; i < m.count; i++) {
            let it = m.get(i);
            if (it && it.moduleId === pendingId && !it.isPlaceholder) pIdx = i;
            if (it && it.moduleId === targetId && !it.isPlaceholder) tIdx = i;
        }

        if (pIdx === -1 || tIdx === -1) return;

        let targetItem = m.get(tIdx);
        let gId = (targetItem && targetItem.groupId) ? targetItem.groupId : "";
        if (!gId || gId === "") {
            gId = "g_" + targetId;
            barTabRoot.assignGroupColor(gId);
            m.setProperty(tIdx, "groupId", gId);
        }

        let pendingItem = m.get(pIdx);
        let pData = {
            moduleId: pendingItem.moduleId,
            moduleLabel: pendingItem.moduleLabel,
            moduleIcon: pendingItem.moduleIcon,
            moduleColor: colorToString(pendingItem.moduleColor),
            isPlaceholder: false,
            placeholderWidth: 0,
            groupId: gId
        };

        let wasBefore = pIdx < tIdx;
        m.remove(pIdx, 1);

        let groupIndices = [];
        for (let i = 0; i < m.count; i++) {
            let it = m.get(i);
            if (it && it.groupId === gId && !it.isPlaceholder) {
                groupIndices.push(i);
            }
        }

        if (groupIndices.length > 0) {
            if (wasBefore) {
                let insertIdx = groupIndices[0];
                m.insert(insertIdx, pData);
            } else {
                let insertIdx = groupIndices[groupIndices.length - 1] + 1;
                m.insert(insertIdx, pData);
            }
        } else {
            m.insert(m.count, pData);
        }

        barTabRoot.cleanupGroups();
        barTabRoot.saveModuleModels();
    }

    function executeDrop(dragSource) {
        let sList = dragSource.listName;
        let sId = dragSource.moduleId;
        let sModel = getModel(sList);
        if (!sModel) return;

        let itemData = null;
        for (let i = 0; i < sModel.count; i++) {
            let item = sModel.get(i);
            if (item && item.moduleId === sId && !item.isPlaceholder) {
                itemData = {
                    moduleId: item.moduleId,
                    moduleLabel: item.moduleLabel,
                    moduleIcon: item.moduleIcon,
                    moduleColor: colorToString(item.moduleColor),
                    isPlaceholder: false,
                    placeholderWidth: 0,
                    groupId: item.groupId || ""
                };
                sModel.remove(i, 1);
                break;
            }
        }

        let tList = currentPlaceholderList;
        let tIdx = currentPlaceholderIndex;

        clearPlaceholders();

        if (itemData && tList !== "") {
            let tModel = getModel(tList);
            if (tModel) {
                tIdx = Math.max(0, Math.min(tIdx, tModel.count));

                if (tList === "available") {
                    itemData.groupId = "";
                } else {
                    let prevItem = (tIdx > 0 && tIdx - 1 < tModel.count) ? tModel.get(tIdx - 1) : null;
                    let nextItem = (tIdx >= 0 && tIdx < tModel.count) ? tModel.get(tIdx) : null;
                    let prevGroup = (prevItem && prevItem.groupId) ? prevItem.groupId : "";
                    let nextGroup = (nextItem && nextItem.groupId) ? nextItem.groupId : "";

                    let joinGroup = "";
                    if (prevGroup !== "" && prevGroup === nextGroup) {
                        joinGroup = prevGroup;
                    } else if (prevGroup !== "" && nextGroup === "") {
                        joinGroup = prevGroup;
                    } else if (nextGroup !== "" && prevGroup === "") {
                        joinGroup = nextGroup;
                    }
                    itemData.groupId = joinGroup;
                }

                tModel.insert(tIdx, itemData);
            }
        } else if (itemData) {
            sModel.insert(sModel.count, itemData);
        }

        currentPlaceholderList = "";
        currentPlaceholderIndex = -1;
        barTabRoot.cleanupGroups();
        saveModuleModels();
    }

    function getDropIndex(flow, mx, my) {
        let count = 0;
        let phIndex = -1;
        let phWidth = 0;
        let hasPlaceholder = false;

        for (let i = 0; i < flow.children.length; i++) {
            let child = flow.children[i];
            if (child.isDelegate && child.isPlaceholder) {
                hasPlaceholder = true;
                phWidth = child.width;
                phIndex = count;
                break;
            }
            if (child.isDelegate && !child.isBeingDragged) {
                count++;
            }
        }

        count = 0;
        let target = 0;
        let found = false;
        for (let i = 0; i < flow.children.length; i++) {
            let child = flow.children[i];
            if (child.isDelegate && !child.isBeingDragged && !child.isPlaceholder) {
                let unshiftedX = child.x;
                if (hasPlaceholder && count >= phIndex) {
                    unshiftedX -= (phWidth + flow.spacing);
                }
                let centerX = unshiftedX + child.width / 2;
                let centerY = child.y + child.height / 2;

                if (!found) {
                    if (Math.abs(my - centerY) < child.height / 2 + flow.spacing / 2) {
                        if (mx < centerX) {
                            target = count;
                            found = true;
                        }
                    } else if (my < child.y) {
                        target = count;
                        found = true;
                    }
                }
                count++;
            }
        }
        if (!found) target = count;
        return target;
    }

    function syncSettings() {
        let ts = Config.getSetting("bar", barTabRoot.defaultBarSettings);
        barTabRoot.barPosition = ts.position !== undefined ? ts.position : "top";
        barTabRoot.currentBarWidth = ts.width !== undefined ? ts.width : 100;
        barTabRoot.currentBarOpacity = ts.opacity !== undefined ? ts.opacity : 100;
        if (typeof ts.style === "string") {
            barTabRoot.barStyle = ts.style;
        } else if (ts.style && typeof ts.style === "object") {
            if (ts.style.fill || ts.style.mode === "fill") barTabRoot.barStyle = "fill";
            else if (ts.style.solid || ts.style.mode === "solid") barTabRoot.barStyle = "solid";
            else barTabRoot.barStyle = "modular";
        } else {
            barTabRoot.barStyle = "modular";
        }
        barTabRoot.distinctPills = ts.distinctPills !== undefined ? ts.distinctPills : false;
        barTabRoot.timeFormat = ts.time && ts.time.format !== undefined ? ts.time.format : "HH:mm:ss";
        barTabRoot.autohide = ts.autohide !== undefined ? ts.autohide : false;
        barTabRoot.autohideTimeout = ts.autohideTimeout !== undefined ? ts.autohideTimeout : 1000;
        barTabRoot.workspaceCount = ts.workspaceCount !== undefined ? ts.workspaceCount : 8;
        barTabRoot.workspaceGroupsPerMonitor = ts.workspaceGroupsPerMonitor !== undefined ? ts.workspaceGroupsPerMonitor : false;
        if (ts.groupColors) {
            barTabRoot.assignedGroupColors = ts.groupColors;
        }
        barTabRoot.barSettings = ts;
    }

    Component.onCompleted: {
        syncSettings();
        loadModuleModels();
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            syncSettings();
            let ts = Config.getSetting("bar", barTabRoot.defaultBarSettings);
            let tsModules = ts.modules || barTabRoot.defaultBarSettings.modules;
            let currentStr = barTabRoot.getModulesString(tsModules);
            if (currentStr === barTabRoot.lastSavedModulesString) {
                return;
            }
            barTabRoot.lastSavedModulesString = "";
            barTabRoot.loadModuleModels();
        }
    }

    function updateBarSettings() {
        let current = Config.getSetting("bar", barTabRoot.defaultBarSettings);
        current.position = barTabRoot.barPosition;
        current.width = barTabRoot.currentBarWidth;
        current.opacity = barTabRoot.currentBarOpacity;
        current.style = barTabRoot.barStyle;
        current.distinctPills = barTabRoot.distinctPills;
        if (!current.time) current.time = {};
        current.time.format = barTabRoot.timeFormat;
        current.autohide = barTabRoot.autohide;
        current.autohideTimeout = barTabRoot.autohideTimeout;
        current.workspaceCount = barTabRoot.workspaceCount;
        current.workspaceGroupsPerMonitor = barTabRoot.workspaceGroupsPerMonitor;
        if (!current.modules) current.modules = barTabRoot.defaultBarSettings.modules;
        current.groupColors = barTabRoot.assignedGroupColors;

        barTabRoot.lastSavedModulesString = barTabRoot.getModulesString(current.modules);
        Config.setSetting("bar", current);
    }

    Component {
        id: dragBoxComp
        Rectangle {
            id: dragBoxRoot
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: lName !== "available"
            implicitHeight: Math.max(rootObj.s(lName === "available" ? 68 : 90), titleText.implicitHeight + (flowList.childrenRect.height > 0 ? flowList.childrenRect.height : flowList.implicitHeight) + rootObj.s(20))
            color: ThemeBackend.mantle
            radius: barTabRoot.cardRadius
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
            clip: true

            property var listModel
            property string lName
            property string title: {
                if (lName === "available") return I18n.t("guide.bar.config.available");
                if (lName === "left") return I18n.t("guide.bar.config.left");
                if (lName === "center") return I18n.t("guide.bar.config.center");
                if (lName === "right") return I18n.t("guide.bar.config.right");
                return "";
            }

            MouseArea {
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {
                    barTabRoot.clearPendingGroup();
                }
            }

            Text {
                id: titleText
                z: 1
                anchors.top: parent.top
                anchors.topMargin: rootObj.s(8)
                anchors.left: lName !== "right" ? parent.left : undefined
                anchors.leftMargin: lName !== "right" ? rootObj.s(12) : 0
                anchors.right: lName === "right" ? parent.right : undefined
                anchors.rightMargin: lName === "right" ? rootObj.s(12) : 0
                text: dragBoxRoot.title
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                font.weight: Font.Bold
                color: ThemeBackend.subtext0
            }

            DropArea {
                anchors.fill: parent
                z: 0
                onPositionChanged: function(drag) {
                    let mappedX = drag.x - flowList.x;
                    let mappedY = drag.y - flowList.y;
                    let idx = barTabRoot.getDropIndex(flowList, mappedX, mappedY);
                    barTabRoot.updatePlaceholder(dragBoxRoot.lName, idx, drag.source.btnWidth, drag.source.moduleId, drag.source.moduleLabel, drag.source.moduleIcon, drag.source.listName, drag.source.moduleId);
                }
                onExited: {
                    if (barTabRoot.currentPlaceholderList === dragBoxRoot.lName) {
                        barTabRoot.clearPlaceholders();
                        barTabRoot.currentPlaceholderList = "";
                        barTabRoot.currentPlaceholderIndex = -1;
                    }
                }
            }

            Flow {
                id: flowList
                z: 1
                anchors.top: titleText.bottom
                anchors.topMargin: rootObj.s(4)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: rootObj.s(8)
                anchors.rightMargin: rootObj.s(8)
                spacing: rootObj.s(8)

                Repeater {
                    model: listModel
                    delegate: Item {
                        id: delegateRoot
                        property bool isDelegate: true
                        property bool isPlaceholder: model.isPlaceholder !== undefined ? model.isPlaceholder : false
                        property string moduleId: model.moduleId
                        property string moduleLabel: {
                            if (moduleId === "left") return I18n.t("guide.bar.modules.actions");
                            if (moduleId === "workspaces") return I18n.t("guide.bar.modules.workspaces");
                            if (moduleId === "focus") return I18n.t("guide.bar.modules.focus");
                            if (moduleId === "timedate") return I18n.t("guide.bar.modules.timedate");
                            if (moduleId === "info") return I18n.t("guide.bar.modules.info");
                            if (moduleId === "weather") return I18n.t("guide.bar.modules.weather");
                            if (moduleId === "media") return I18n.t("guide.bar.modules.media");
                            if (moduleId === "vis") return I18n.t("guide.bar.modules.vis");
                            if (moduleId === "tray") return I18n.t("guide.bar.modules.tray");
                            if (moduleId === "sysmon") return I18n.t("guide.bar.modules.sysmon");
                            if (moduleId === "kb") return I18n.t("guide.bar.modules.keyboard");
                            if (moduleId === "wifi") return I18n.t("guide.bar.modules.network");
                            if (moduleId === "bt") return I18n.t("guide.bar.modules.bluetooth");
                            if (moduleId === "vol") return I18n.t("guide.bar.modules.volume");
                            if (moduleId === "bat") return I18n.t("guide.bar.modules.battery");
                            return model.moduleLabel !== undefined ? model.moduleLabel : moduleId;
                        }
                        property string moduleIcon: model.moduleIcon
                        property string listName: dragBoxRoot.lName
                        property int moduleIndex: index

                        property bool isBeingDragged: dragArea.drag.active
                        property int btnWidth: btn.implicitWidth

                        property bool isGrouped: model.groupId !== undefined && model.groupId !== ""
                        property bool showError: false

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: floatWrapper; property: "x"; to: -2; duration: 50 }
                            NumberAnimation { target: floatWrapper; property: "x"; to: 2; duration: 50 }
                            NumberAnimation { target: floatWrapper; property: "x"; to: -2; duration: 50 }
                            NumberAnimation { target: floatWrapper; property: "x"; to: 2; duration: 50 }
                            NumberAnimation { target: floatWrapper; property: "x"; to: 0; duration: 50 }
                            onStarted: delegateRoot.showError = true
                            onStopped: delegateRoot.showError = false
                        }

                        function triggerError() {
                            shakeAnim.stop();
                            shakeAnim.start();
                        }

                        implicitWidth: isPlaceholder ? model.placeholderWidth : btn.implicitWidth
                        implicitHeight: rootObj.s(32)
                        width: isPlaceholder ? model.placeholderWidth : (isBeingDragged ? 0 : btn.implicitWidth)
                        height: isPlaceholder ? rootObj.s(32) : (isBeingDragged ? 0 : rootObj.s(32))
                        visible: isPlaceholder || !isBeingDragged

                        Behavior on width {
                            enabled: !delegateRoot.isBeingDragged
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuint }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: delegateRoot.isPlaceholder
                            color: "transparent"
                            border.color: ThemeBackend.subtext0
                            border.width: 1
                            radius: ThemeBackend.borderRadius
                            Rectangle { anchors.fill: parent; color: ThemeBackend.subtext0; opacity: 0.15; radius: ThemeBackend.borderRadius }
                        }

                        Item {
                            id: floatWrapper
                            anchors.fill: !dragArea.drag.active ? parent : undefined
                            visible: !delegateRoot.isPlaceholder

                            Drag.active: dragArea.drag.active
                            Drag.source: delegateRoot
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            states: [
                                State {
                                    when: dragArea.drag.active
                                    ParentChange { target: floatWrapper; parent: barTabRoot }
                                    PropertyChanges {
                                        target: floatWrapper
                                        width: delegateRoot.btnWidth
                                        height: rootObj.s(32)
                                        opacity: 0.9
                                        scale: 1.05
                                    }
                                }
                            ]

                            ClickButton {
                                id: btn
                                anchors.fill: parent
                                buttonText: delegateRoot.moduleLabel
                                buttonIcon: delegateRoot.moduleIcon
                                accentColor: delegateRoot.isGrouped ? barTabRoot.getGroupColor(model.groupId) : ThemeBackend.surface0
                                textColor: delegateRoot.isGrouped ? barTabRoot.getContrastTextColor(barTabRoot.getGroupColor(model.groupId)) : ThemeBackend.text
                                cornerRadius: ThemeBackend.borderRadius
                                horizontalPadding: rootObj.s(12)
                                iconFontSize: rootObj.s(15)
                                textFontSize: rootObj.s(12)
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                onClicked: function() {
                                    barTabRoot.clearPendingGroup();
                                }

                                onRightClicked: function() {
                                    if (delegateRoot.listName === "available") {
                                        barTabRoot.clearPendingGroup();
                                        return;
                                    }

                                    let m = barTabRoot.getModel(delegateRoot.listName);
                                    if (!m) return;

                                    if (barTabRoot.pendingGroupModuleId !== "") {
                                        if (barTabRoot.pendingGroupModuleId === delegateRoot.moduleId) {
                                            barTabRoot.clearPendingGroup();
                                            return;
                                        }

                                        if (barTabRoot.pendingGroupList === delegateRoot.listName) {
                                            barTabRoot.uniteElements(barTabRoot.pendingGroupModuleId, delegateRoot.moduleId, delegateRoot.listName);
                                            barTabRoot.clearPendingGroup();
                                        } else {
                                            delegateRoot.triggerError();
                                            barTabRoot.clearPendingGroup();
                                        }
                                        return;
                                    }

                                    if (barTabRoot.getValidItemCount(m) <= 1) {
                                        return;
                                    }

                                    if (model.groupId && model.groupId !== "") {
                                        m.setProperty(delegateRoot.moduleIndex, "groupId", "");
                                        barTabRoot.cleanupGroups();
                                        barTabRoot.saveModuleModels();
                                    } else {
                                        barTabRoot.pendingGroupModuleId = delegateRoot.moduleId;
                                        barTabRoot.pendingGroupList = delegateRoot.listName;
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: ThemeBackend.red
                                opacity: delegateRoot.showError ? 0.15 : 0.0
                                radius: ThemeBackend.borderRadius
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                z: 4
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: ThemeBackend.mauve
                                opacity: barTabRoot.pendingGroupModuleId === delegateRoot.moduleId ? 0.2 : 0.0
                                radius: ThemeBackend.borderRadius
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                z: 5
                            }

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                drag.target: floatWrapper
                                cursorShape: Qt.OpenHandCursor
                                acceptedButtons: Qt.LeftButton
                                onPressed: {
                                    barTabRoot.clearPendingGroup();
                                    cursorShape = Qt.ClosedHandCursor
                                    if (typeof Sounds !== "undefined") {
                                        Sounds.playSfx("guide/barconfig/out.wav");
                                    }
                                }
                                onReleased: {
                                    cursorShape = Qt.OpenHandCursor
                                    if (typeof Sounds !== "undefined") {
                                        Sounds.playSfx("guide/barconfig/in.wav");
                                    }
                                    floatWrapper.Drag.drop();
                                    if (barTabRoot.currentPlaceholderList !== "") {
                                        barTabRoot.executeDrop(delegateRoot);
                                    } else {
                                        barTabRoot.clearPlaceholders();
                                    }
                                    floatWrapper.x = 0;
                                    floatWrapper.y = 0;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: settingsCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        onMovementStarted: {
            barTabRoot.clearPendingGroup();
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                barTabRoot.clearPendingGroup();
            }
        }

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: row0Layout.implicitHeight + rootObj.s(18)
                    color: "transparent"

                    RowLayout {
                        id: row0Layout
                        anchors.left: parent.left
                        anchors.leftMargin: rootObj.s(12)
                        anchors.right: parent.right
                        anchors.rightMargin: rootObj.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: rootObj.s(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text { text: I18n.t("guide.bar.position.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                            Text { text: I18n.t("guide.bar.position.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                        }

                        Dropdown {
                            id: barPosDropdown
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(180)
                            implicitHeight: rootObj.s(32)
                            options: [I18n.t("guide.bar.position.top"), I18n.t("guide.bar.position.bottom"), I18n.t("guide.bar.position.left"), I18n.t("guide.bar.position.right")]
                            currentIndex: barTabRoot.barPosition === "bottom" ? 1 : (barTabRoot.barPosition === "left" ? 2 : (barTabRoot.barPosition === "right" ? 3 : 0))
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            hoverColor: ThemeBackend.surface1
                            dropdownColor: ThemeBackend.surface0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            fontPixelSize: rootObj.s(11)
                            onValueChanged: function(index, value) {
                                barTabRoot.clearPendingGroup();
                                if (index === 0) barTabRoot.barPosition = "top";
                                else if (index === 1) barTabRoot.barPosition = "bottom";
                                else if (index === 2) barTabRoot.barPosition = "left";
                                else if (index === 3) barTabRoot.barPosition = "right";
                                barTabRoot.updateBarSettings();
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.2); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rowStyleLayout.implicitHeight + rootObj.s(18)
                    color: "transparent"
                    RowLayout {
                        id: rowStyleLayout
                        anchors.left: parent.left
                        anchors.leftMargin: rootObj.s(12)
                        anchors.right: parent.right
                        anchors.rightMargin: rootObj.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: rootObj.s(16)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text { text: I18n.t("guide.bar.style.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                            Text { text: I18n.t("guide.bar.style.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(210); implicitHeight: rootObj.s(32)
                            options: [I18n.t("guide.bar.style.modular"), I18n.t("guide.bar.style.solid"), I18n.t("guide.bar.style.fill")]
                            currentIndex: barTabRoot.barStyle === "fill" ? 2 : (barTabRoot.barStyle === "solid" ? 1 : 0)
                            accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.subtext0; activeTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius; fontPixelSize: rootObj.s(11)
                            onToggled: function(index) {
                                barTabRoot.clearPendingGroup();
                                if (index === 0) barTabRoot.barStyle = "modular";
                                else if (index === 1) barTabRoot.barStyle = "solid";
                                else if (index === 2) barTabRoot.barStyle = "fill";
                                barTabRoot.updateBarSettings();
                            }
                        }
                    }
                }

                Item {
                    id: distinctPillsSectionWrapper
                    Layout.fillWidth: true
                    property bool isOpen: barTabRoot.barStyle === "solid" || barTabRoot.barStyle === "fill"
                    clip: true
                    visible: implicitHeight > 0
                    opacity: isOpen ? 1.0 : 0.0
                    implicitHeight: isOpen ? distinctPillsInnerCol.implicitHeight : 0

                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: distinctPillsInnerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.alpha(ThemeBackend.surface1, 0.2)
                            Layout.topMargin: rootObj.s(5)
                            Layout.bottomMargin: rootObj.s(5)
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rowDistinctPillsLayout.implicitHeight + rootObj.s(18)
                            color: "transparent"

                            RowLayout {
                                id: rowDistinctPillsLayout
                                anchors.left: parent.left
                                anchors.leftMargin: rootObj.s(12)
                                anchors.right: parent.right
                                anchors.rightMargin: rootObj.s(12)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: rootObj.s(16)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(2)
                                    Text {
                                        text: I18n.t("guide.bar.distinct_pills.title")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(13)
                                        color: ThemeBackend.text
                                    }
                                    Text {
                                        text: I18n.t("guide.bar.distinct_pills.desc")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        color: ThemeBackend.subtext0
                                    }
                                }

                                Toggle {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    checked: barTabRoot.distinctPills
                                    accentColor: ThemeBackend.mauve
                                    baseColor: ThemeBackend.surface1
                                    handleColor: ThemeBackend.crust
                                    handleOffColor: ThemeBackend.text
                                    onToggled: function(c) {
                                        barTabRoot.clearPendingGroup();
                                        barTabRoot.distinctPills = c;
                                        barTabRoot.updateBarSettings();
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: widthSectionWrapper
                    Layout.fillWidth: true
                    property bool isOpen: barTabRoot.barStyle !== "fill"
                    clip: true
                    visible: implicitHeight > 0
                    opacity: isOpen ? 1.0 : 0.0
                    implicitHeight: isOpen ? widthInnerCol.implicitHeight : 0

                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: widthInnerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.alpha(ThemeBackend.surface1, 0.2)
                            Layout.topMargin: rootObj.s(5)
                            Layout.bottomMargin: rootObj.s(5)
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rowWidthLayout.implicitHeight + rootObj.s(18)
                            color: "transparent"

                            RowLayout {
                                id: rowWidthLayout
                                anchors.left: parent.left
                                anchors.leftMargin: rootObj.s(12)
                                anchors.right: parent.right
                                anchors.rightMargin: rootObj.s(12)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: rootObj.s(16)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(2)
                                    Text {
                                        text: {
                                            if (barTabRoot.barPosition === "left" || barTabRoot.barPosition === "right") {
                                                let h = I18n.t("guide.bar.height.title");
                                                if (h && h !== "guide.bar.height.title") return h;
                                                let w = I18n.t("guide.bar.width.title");
                                                if (w && w.indexOf("Width") !== -1) return w.replace("Width", "Height");
                                                if (w && w.indexOf("width") !== -1) return w.replace("width", "height");
                                                return w;
                                            }
                                            return I18n.t("guide.bar.width.title");
                                        }
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(13)
                                        color: ThemeBackend.text
                                    }
                                    Text {
                                        text: {
                                            if (barTabRoot.barPosition === "left" || barTabRoot.barPosition === "right") {
                                                let h = I18n.t("guide.bar.height.desc");
                                                if (h && h !== "guide.bar.height.desc") return h;
                                                let w = I18n.t("guide.bar.width.desc");
                                                if (w && w.indexOf("Width") !== -1) return w.replace("Width", "Height");
                                                if (w && w.indexOf("width") !== -1) return w.replace("width", "height");
                                                return w;
                                            }
                                            return I18n.t("guide.bar.width.desc");
                                        }
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        color: ThemeBackend.subtext0
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    spacing: rootObj.s(12)
                                    Layout.rightMargin: rootObj.s(8)

                                    Draggable {
                                        id: barWidthSlider
                                        implicitWidth: rootObj.s(220)
                                        implicitHeight: rootObj.s(18)
                                        from: 5
                                        to: 100
                                        stepSize: 1
                                        defaultValue: 100
                                        showValueBubble: true
                                        valueFormatter: function(v) { return Math.round(v) + "%" }
                                        value: barTabRoot.currentBarWidth
                                        backgroundColor: ThemeBackend.surface0
                                        accentColor: ThemeBackend.mauve
                                        handleColor: ThemeBackend.text
                                        handleBorderColor: ThemeBackend.mantle
                                        onMoved: function(val) {
                                            barTabRoot.clearPendingGroup();
                                            let rounded = Math.round(val);
                                            if (barTabRoot.currentBarWidth !== rounded) {
                                                barTabRoot.currentBarWidth = rounded;
                                                barWidthDebounceTimer.restart();
                                            }
                                        }
                                        onDragFinished: {
                                            barWidthDebounceTimer.stop();
                                            barTabRoot.updateBarSettings();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.2); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rowOpacityLayout.implicitHeight + rootObj.s(18)
                    color: "transparent"

                    RowLayout {
                        id: rowOpacityLayout
                        anchors.left: parent.left
                        anchors.leftMargin: rootObj.s(12)
                        anchors.right: parent.right
                        anchors.rightMargin: rootObj.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: rootObj.s(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text { text: I18n.t("guide.bar.opacity.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                            Text { text: I18n.t("guide.bar.opacity.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: rootObj.s(12)
                            Layout.rightMargin: rootObj.s(8)

                            Draggable {
                                id: barOpacitySlider
                                implicitWidth: rootObj.s(220)
                                implicitHeight: rootObj.s(18)
                                from: 1
                                to: 100
                                stepSize: 1
                                defaultValue: 100
                                showValueBubble: true
                                valueFormatter: function(v) { return Math.round(v) + "%" }
                                value: barTabRoot.currentBarOpacity
                                backgroundColor: ThemeBackend.surface0
                                accentColor: ThemeBackend.mauve
                                handleColor: ThemeBackend.text
                                handleBorderColor: ThemeBackend.mantle
                                onMoved: function(val) {
                                    barTabRoot.clearPendingGroup();
                                    let rounded = Math.round(val);
                                    if (barTabRoot.currentBarOpacity !== rounded) {
                                        barTabRoot.currentBarOpacity = rounded;
                                        barWidthDebounceTimer.restart();
                                    }
                                }
                                onDragFinished: {
                                    barWidthDebounceTimer.stop();
                                    barTabRoot.updateBarSettings();
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.4); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowTimeLayout.implicitHeight + rootObj.s(18)
                        color: "transparent"
                        RowLayout {
                            id: rowTimeLayout
                            anchors.left: parent.left
                            anchors.leftMargin: rootObj.s(12)
                            anchors.right: parent.right
                            anchors.rightMargin: rootObj.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: rootObj.s(16)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text { text: I18n.t("guide.bar.time.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                                Text { text: I18n.t("guide.bar.time.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                            }
                            Input {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitWidth: rootObj.s(140)
                                implicitHeight: rootObj.s(32)
                                text: barTabRoot.timeFormat
                                placeholderText: "HH:mm:ss"
                                baseColor: ThemeBackend.surface0
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: rootObj.s(11)
                                onTextEdited: function(newText) {
                                    barTabRoot.clearPendingGroup();
                                    barTabRoot.timeFormat = newText;
                                    barTabRoot.updateBarSettings();
                                }
                                onAccepted: function(finalText) {
                                    barTabRoot.clearPendingGroup();
                                    barTabRoot.timeFormat = finalText;
                                    barTabRoot.updateBarSettings();
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.2); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowAutohideLayout.implicitHeight + rootObj.s(18)
                        color: "transparent"
                        RowLayout {
                            id: rowAutohideLayout
                            anchors.left: parent.left
                            anchors.leftMargin: rootObj.s(12)
                            anchors.right: parent.right
                            anchors.rightMargin: rootObj.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: rootObj.s(16)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text { text: I18n.t("guide.bar.autohide.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                                Text { text: I18n.t("guide.bar.autohide.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                            }
                            Toggle {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                checked: barTabRoot.autohide
                                accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface1; handleColor: ThemeBackend.crust; handleOffColor: ThemeBackend.text
                                onToggled: function(c) {
                                    barTabRoot.clearPendingGroup();
                                    barTabRoot.autohide = c;
                                    barTabRoot.updateBarSettings();
                                }
                            }
                        }
                    }

                    Item {
                        id: timeoutSectionWrapper
                        Layout.fillWidth: true
                        property bool isOpen: barTabRoot.autohide
                        clip: true
                        visible: implicitHeight > 0
                        opacity: isOpen ? 1.0 : 0.0
                        implicitHeight: isOpen ? timeoutInnerCol.implicitHeight : 0

                        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: timeoutInnerCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                Layout.topMargin: rootObj.s(5)
                                Layout.bottomMargin: rootObj.s(5)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: rowTimeoutLayout.implicitHeight + rootObj.s(18)
                                color: "transparent"

                                RowLayout {
                                    id: rowTimeoutLayout
                                    anchors.left: parent.left
                                    anchors.leftMargin: rootObj.s(12)
                                    anchors.right: parent.right
                                    anchors.rightMargin: rootObj.s(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: rootObj.s(16)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(2)
                                        Text { text: I18n.t("guide.bar.timeout.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                                        Text { text: I18n.t("guide.bar.timeout.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                                    }
                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        spacing: rootObj.s(12)
                                        Layout.rightMargin: rootObj.s(8)

                                        Draggable {
                                            id: timeoutSlider
                                            implicitWidth: rootObj.s(220)
                                            implicitHeight: rootObj.s(18)
                                            from: 250
                                            to: 10000
                                            stepSize: 50
                                            defaultValue: 1000
                                            showValueBubble: true
                                            valueFormatter: function(v) { return Math.round(v) + " ms" }
                                            value: barTabRoot.autohideTimeout
                                            backgroundColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            handleColor: ThemeBackend.text
                                            handleBorderColor: ThemeBackend.mantle
                                            onMoved: function(val) {
                                                barTabRoot.clearPendingGroup();
                                                let rounded = Math.round(val);
                                                if (barTabRoot.autohideTimeout !== rounded) {
                                                    barTabRoot.autohideTimeout = rounded;
                                                    barWidthDebounceTimer.restart();
                                                }
                                            }
                                            onDragFinished: {
                                                barWidthDebounceTimer.stop();
                                                barTabRoot.updateBarSettings();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.4); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowWorkspacesCountLayout.implicitHeight + rootObj.s(18)
                        color: "transparent"

                        RowLayout {
                            id: rowWorkspacesCountLayout
                            anchors.left: parent.left
                            anchors.leftMargin: rootObj.s(12)
                            anchors.right: parent.right
                            anchors.rightMargin: rootObj.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: rootObj.s(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text { text: I18n.t("guide.bar.workspaces.title"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                                Text { text: I18n.t("guide.bar.workspaces.desc"); font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                            }

                            NumberSelector {
                                id: workspaceCountSelector
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitWidth: rootObj.s(140)
                                implicitHeight: rootObj.s(32)
                                from: 2
                                to: 10
                                stepSize: 1
                                decimals: 0
                                value: barTabRoot.workspaceCount
                                baseColor: ThemeBackend.surface0
                                accentColor: ThemeBackend.mauve
                                buttonColor: ThemeBackend.surface1
                                buttonTextColor: ThemeBackend.text
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontFamily: ThemeBackend.fontFamily
                                fontPixelSize: rootObj.s(12)
                                onValueChanged: {
                                    let rounded = Math.round(workspaceCountSelector.value);
                                    if (barTabRoot.workspaceCount !== rounded) {
                                        barTabRoot.clearPendingGroup();
                                        barTabRoot.workspaceCount = rounded;
                                        barTabRoot.updateBarSettings();
                                    }
                                }
                                onTriggered: {
                                    barTabRoot.clearPendingGroup();
                                    barTabRoot.workspaceCount = Math.round(workspaceCountSelector.value);
                                    barTabRoot.updateBarSettings();
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.4); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowWorkspaceGroupsLayout.implicitHeight + rootObj.s(18)
                        color: "transparent"

                        RowLayout {
                            id: rowWorkspaceGroupsLayout
                            anchors.left: parent.left
                            anchors.leftMargin: rootObj.s(12)
                            anchors.right: parent.right
                            anchors.rightMargin: rootObj.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: rootObj.s(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text { text: I18n.t("guide.bar.workspace_groups.title") || "Workspace group per monitor"; font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(13); color: ThemeBackend.text }
                                Text { text: I18n.t("guide.bar.workspace_groups.desc") || "Each bar shows its own monitor's block of workspaces (1-N, N+1-2N, ...)"; font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(11); color: ThemeBackend.subtext0 }
                            }

                            Toggle {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                checked: barTabRoot.workspaceGroupsPerMonitor
                                accentColor: ThemeBackend.mauve
                                baseColor: ThemeBackend.surface1
                                handleColor: ThemeBackend.crust
                                handleOffColor: ThemeBackend.text
                                onToggled: function(c) {
                                    barTabRoot.clearPendingGroup();
                                    barTabRoot.workspaceGroupsPerMonitor = c;
                                    barTabRoot.updateBarSettings();
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.4); Layout.topMargin: rootObj.s(5); Layout.bottomMargin: rootObj.s(5) }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: rootObj.s(4)
                        spacing: rootObj.s(14)

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: rootObj.s(12)
                            Layout.rightMargin: rootObj.s(12)
                            spacing: rootObj.s(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(2)
                                Text {
                                    text: I18n.t("guide.bar.config.title")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(13)
                                    color: ThemeBackend.text
                                }
                                Text {
                                    text: I18n.t("guide.bar.config.desc")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.subtext0
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ClickButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitHeight: rootObj.s(32)
                                buttonText: I18n.t("guide.bar.config.reset")
                                buttonIcon: "↺"
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                cornerRadius: ThemeBackend.borderRadius
                                horizontalPadding: rootObj.s(12)
                                textFontSize: rootObj.s(11)
                                onClicked: function() {
                                    barTabRoot.resetBarSettings();
                                }
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            sourceComponent: dragBoxComp
                            onLoaded: {
                                item.listModel = availableModel;
                                item.lName = "available";
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumHeight: rootObj.s(130)
                            spacing: rootObj.s(16)

                            Loader {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                sourceComponent: dragBoxComp
                                onLoaded: {
                                    item.listModel = leftModel;
                                    item.lName = "left";
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                sourceComponent: dragBoxComp
                                onLoaded: {
                                    item.listModel = centerModel;
                                    item.lName = "center";
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                sourceComponent: dragBoxComp
                                onLoaded: {
                                    item.listModel = rightModel;
                                    item.lName = "right";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
