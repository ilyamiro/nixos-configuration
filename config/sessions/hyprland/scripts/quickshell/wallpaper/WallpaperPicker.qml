import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Qt.labs.folderlistmodel
import QtMultimedia
import Quickshell
import Quickshell.Io
import "../" 

Item {
    id: window
    width: Screen.width

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    MatugenColors { id: _theme }

    property string widgetArg: ""
    property string targetWallName: ""
    property bool initialFocusSet: false
    property int visibleItemCount: -1
    property int scrollAccum: 0
    property real scrollThreshold: window.s(300)

    property string currentFilter: "All"
    property string _lastFilter: "All"
    property string searchQuery: ""
    property bool isOnlineSearch: false
    property bool isSearchPaused: false
    property bool hasSearched: false
    property var colorMap: ({})
    property int cacheVersion: 0 
    
    property bool isDownloadingWallpaper: false
    property string currentDownloadName: ""
    
    property bool isApplying: false
    property bool isMonitorSelectorOpen: false
    
    Timer {
        id: applyUnlockTimer
        interval: 250
        onTriggered: window.isApplying = false
    }
    
    property bool isStartup: localFolderModel.status === FolderListModel.Loading || srcModel.status === FolderListModel.Loading
    property bool isReady: visible && localFolderModel.status === FolderListModel.Ready
    property bool isSearchActive: window.currentFilter === "Search" && window.hasSearched && searchFolderModel.status === FolderListModel.Loading
    
    property string lastSearchName: ""
    property bool isModelChanging: false
    property bool searchIndexRestored: false
    
    property bool isScrollingBlocked: window.currentFilter === "Search" && window.hasSearched && window.isSearchActive && !window.isSearchPaused
    property bool jumpToLastOnFilterChange: false

    readonly property var filterData: [
        { name: "All", hex: "", label: "All" },
        { name: "Video", hex: "", label: "Vid" },
        { name: "Red", hex: "#FF4500", label: "" },
        { name: "Orange", hex: "#FFA500", label: "" },
        { name: "Yellow", hex: "#FFD700", label: "" },
        { name: "Green", hex: "#32CD32", label: "" },
        { name: "Blue", hex: "#1E90FF", label: "" },
        { name: "Purple", hex: "#8A2BE2", label: "" },
        { name: "Pink", hex: "#FF69B4", label: "" },
        { name: "Monochrome", hex: "#A9A9A9", label: "" },
        { name: "Search", hex: "", label: "Search" } 
    ]

    ListModel { id: monitorModel }

    Process {
        id: monitorProc
        command: ["sh", "-c", "export PATH=$PATH:/usr/bin:/usr/local/bin:/run/current-system/sw/bin && hyprctl monitors -j"]
        running: false
        
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("[MonitorSync] Process finished. Reading stdout directly.");
                let response = this.text; 
                
                if (response && response.trim().length > 0) {
                    try {
                        var monitors = JSON.parse(response);
                        console.log("[MonitorSync] JSON parsed successfully. Found " + monitors.length + " monitors.");
                        
                        monitorModel.clear();
                        for (var i = 0; i < monitors.length; i++) {
                            monitorModel.append({ "name": monitors[i].name, "selected": true });
                            console.log("[MonitorSync] -> Injected: " + monitors[i].name);
                        }
                    } catch(e) {
                        console.log("[MonitorSync] ERROR parsing JSON: " + e);
                        console.log("[MonitorSync] RAW TEXT DUMP: " + response);
                    }
                } else {
                    console.log("[MonitorSync] ERROR: stdout was empty.");
                }
            }
        }
    }

    function loadMonitors() {
        console.log("[MonitorSync] Starting native hyprctl process...");
        monitorProc.running = true;
    }

    function getMonitorOutputs() {
        if (monitorModel.count <= 1) return "all"; 
        
        let selected = [];
        for (let i = 0; i < monitorModel.count; i++) {
            if (monitorModel.get(i).selected) {
                selected.push(monitorModel.get(i).name);
            }
        }
        
        if (selected.length === 0) return "none";
        if (selected.length === monitorModel.count) return "all";
        
        return selected.join(",");
    }

    function applyWallpaper(safeFileName, isVideo) {
        if (!safeFileName || window.isApplying) return;
        
        let outputs = window.getMonitorOutputs();
        if (outputs === "none") return;
        
        window.isApplying = true;
        applyUnlockTimer.restart();
        
        window.targetWallName = safeFileName;
        let cleanName = window.getCleanName(safeFileName);
        let reloadScript = Qt.resolvedUrl("matugen_reload.sh").toString();
        
        if (reloadScript.startsWith("file://")) {
            reloadScript = decodeURIComponent(reloadScript.substring(7));
        }

        const escapeBash = (str) => String(str).replace(/(["\\$`])/g, '\\$1');
        const randomTransition = window.transitions[Math.floor(Math.random() * window.transitions.length)];
        const escOutputs = escapeBash(outputs);
        
        const logFile = "/tmp/qs_awww_debug.log";
        
        if (window.currentFilter === "Search" && window.hasSearched) {
            let alreadyExists = window.isDownloaded(safeFileName);
            let destFile = window.srcDir + "/" + safeFileName;
            let finalThumb = decodeURIComponent(window.thumbDir.replace("file://", "")) + "/" + safeFileName;
            let tempThumb = decodeURIComponent(window.searchDir.replace("file://", "")) + "/" + safeFileName;
            let mapFile = Quickshell.env("HOME") + "/.cache/wallpaper_picker/search_map.txt";

            if (alreadyExists) {
                const applyScript = `
                    export DEST_FILE="${escapeBash(destFile)}"
                    export FINAL_THUMB="${escapeBash(finalThumb)}"
                    export RELOAD_SCRIPT="${escapeBash(reloadScript)}"
                    export TARGET_MONITORS="${escOutputs}"
                    
                    cp "$DEST_FILE" /tmp/lock_bg.png || true
                    pkill mpvpaper || true
                    
                    echo "" >> ${logFile}
                    echo "[$(date +'%H:%M:%S.%3N')] APPLYING CACHED SEARCH: $DEST_FILE TO $TARGET_MONITORS" >> ${logFile}
                    
                    if [ "$TARGET_MONITORS" = "all" ]; then
                        awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                    else
                        awww img -o "$TARGET_MONITORS" "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                    fi
                    
                    ( matugen image "$FINAL_THUMB" || true; bash "$RELOAD_SCRIPT" || true ) &
                `;
                Quickshell.execDetached(["bash", "-c", applyScript]);
            } else {
                window.isDownloadingWallpaper = true;
                window.currentDownloadName = safeFileName;

                const downloadScript = `
                    export SAFE_NAME="${escapeBash(safeFileName)}"
                    export DEST_FILE="${escapeBash(destFile)}"
                    export FINAL_THUMB="${escapeBash(finalThumb)}"
                    export TEMP_THUMB="${escapeBash(tempThumb)}"
                    export RELOAD_SCRIPT="${escapeBash(reloadScript)}"
                    export MAP_FILE="${escapeBash(mapFile)}"
                    export TARGET_MONITORS="${escOutputs}"
                    
                    URL=$(awk -F'|' -v fname="$SAFE_NAME" '$1 == fname {print $2; exit}' "$MAP_FILE")
                    if [ -n "$URL" ]; then
                        curl -s -L -A "Mozilla/5.0" "$URL" -o "$DEST_FILE.tmp"
                        
                        if file "$DEST_FILE.tmp" | grep -iq "webp"; then
                            magick "$DEST_FILE.tmp" "$DEST_FILE"
                            rm -f "$DEST_FILE.tmp"
                        else
                            mv "$DEST_FILE.tmp" "$DEST_FILE"
                        fi
                        
                        cp "$TEMP_THUMB" "$FINAL_THUMB"
                        magick "$DEST_FILE" -resize x420 -quality 70 "$FINAL_THUMB" || true
                        
                        cp "$DEST_FILE" /tmp/lock_bg.png || true
                        pkill mpvpaper || true
                        
                        echo "" >> ${logFile}
                        echo "[$(date +'%H:%M:%S.%3N')] APPLYING NEW DOWNLOAD: $DEST_FILE TO $TARGET_MONITORS" >> ${logFile}
                        
                        if [ "$TARGET_MONITORS" = "all" ]; then
                            awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                        else
                            awww img -o "$TARGET_MONITORS" "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                        fi
                        
                        ( matugen image "$FINAL_THUMB" || true; bash "$RELOAD_SCRIPT" || true ) &
                    fi
                `;
                Quickshell.execDetached(["bash", "-c", downloadScript]);
            }
            return;
        }

        const originalFile = window.srcDir + "/" + cleanName;
        const thumbFile = Quickshell.env("HOME") + "/.cache/wallpaper_picker/thumbs/" + safeFileName;
        
        const escOriginal = escapeBash(originalFile);
        const escThumb = escapeBash(thumbFile);
        const escReload = escapeBash(reloadScript);

        let wallpaperCmd = "";
        
        if (isVideo) {
            wallpaperCmd = `
                echo "" >> ${logFile}
                echo "[$(date +'%H:%M:%S.%3N')] APPLYING LOCAL VIDEO: ${escOriginal} TO ${escOutputs}" >> ${logFile}
                
                if [ "${escOutputs}" = "all" ]; then
                    mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' '*' "${escOriginal}" >> ${logFile} 2>&1 &
                else
                    IFS=',' read -ra MON_ARR <<< "${escOutputs}"
                    for mon in "\${MON_ARR[@]}"; do
                        mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' "\$mon" "${escOriginal}" >> ${logFile} 2>&1 &
                    done
                fi
            `;
        } else {
            wallpaperCmd = `
                echo "" >> ${logFile}
                echo "[$(date +'%H:%M:%S.%3N')] APPLYING LOCAL IMAGE: ${escOriginal} TO ${escOutputs}" >> ${logFile}
                
                if [ "${escOutputs}" = "all" ]; then
                    awww img "${escOriginal}" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                else
                    awww img -o "${escOutputs}" "${escOriginal}" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >> ${logFile} 2>&1 &
                fi
            `;
        }

        const fullScript = `
            cp "${isVideo ? escThumb : escOriginal}" /tmp/lock_bg.png || true
            pkill mpvpaper || true
            
            ${wallpaperCmd}
            ( matugen image "${escThumb}" || true; bash "${escReload}" || true ) &
        `;
        Quickshell.execDetached(["bash", "-c", fullScript]);
    }
    
    Settings {
        id: searchState
        category: "QS_WallpaperPicker"
        property string query: ""
        property bool searched: false
        property string lastName: ""
    }

    onIsSearchPausedChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + (isSearchPaused ? "pause" : "run") + "' > /tmp/ddg_search_control"]);
    }

    onVisibleChanged: {
        if (!visible) {
            window.initialFocusSet = false;
            window.searchIndexRestored = false;
            window.isApplying = false;
            window.isMonitorSelectorOpen = false;
            
            if (window.hasSearched) {
                window.isSearchPaused = true;
            }
        } else {
            window.isFilterAnimating = true;
            filterAnimationTimer.restart();

            if (window.currentFilter !== "Search") {
                window.applyFilters(true);
            } else if (window.hasSearched) {
                window.searchIndexRestored = false;
                window.isSearchPaused = true;
                window.trySearchFocus();
                window.syncSearchModel();
            }
        }
    }

    property bool isLoading: localFolderModel.status === FolderListModel.Loading || 
                             srcModel.status === FolderListModel.Loading ||
                             (window.currentFilter === "Search" && searchFolderModel.status === FolderListModel.Loading)

    property bool showSpinner: window.isDownloadingWallpaper || 
                               (window.currentFilter === "Search" && window.hasSearched && !window.isSearchPaused) || 
                               (window.currentFilter !== "Search" && window.isLoading)

    property string currentNotification: {
        if (window.isDownloadingWallpaper) return "Downloading wallpaper...";

        if (window.currentFilter === "Search") {
            if (!window.hasSearched) return "Type something to search...";
            if (window.isSearchPaused) return "Search Paused";
            if (window.visibleItemCount === 0) return "Searching DDG (FHD+)...";
            return "Generating thumbnails...";
        }

        if (isLoading) return "Generating thumbnails...";
        if (window.visibleItemCount === 0) return "No wallpapers found";
        
        if (window.currentFilter === "All") return "";
        if (window.currentFilter === "Video") return "Videos";
        
        return window.currentFilter;
    }
    
    property bool showNotification: !window.isStartup && currentNotification !== ""

    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);
        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    function isDownloaded(name) {
        if (!name) return false;
        for (let i = 0; i < srcModel.count; i++) {
            if (srcModel.get(i, "fileName") === name) return true;
        }
        return false;
    }

    onWidgetArgChanged: {
        if (widgetArg !== "") {
            targetWallName = widgetArg;
            initialFocusSet = false;
            tryFocus();
        }
    }

    function executeFocusRestore(targetIndex, isSearchRestore, requirePositioning) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        
        if (targetIndex !== -1 && targetIndex < targetModel.count) {
            window.isModelChanging = true;
            
            if (requirePositioning) {
                view.forceLayout();
                view.positionViewAtIndex(targetIndex, ListView.Center);
            }
            
            view.currentIndex = targetIndex;
            
            if (isSearchRestore) {
                window.searchIndexRestored = true;
            }
            
            window.isModelChanging = false;
            window.initialFocusSet = true;
        } else if (isSearchRestore) {
            window.searchIndexRestored = true;
        }
    }

    function tryFocus() {
        if (initialFocusSet) return;

        if (localProxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);

            if (cleanTarget !== "") {
                for (let i = 0; i < localProxyModel.count; i++) {
                    let fname = localProxyModel.get(i).fileName || "";
                    if (window.getCleanName(fname) === cleanTarget) {
                        foundIndex = i;
                        break;
                    }
                }
            }

            let finalIndex = foundIndex !== -1 ? foundIndex : 0;
            window.executeFocusRestore(finalIndex, false, true);
        }
    }
    
    function trySearchFocus() {
        if (window.searchIndexRestored || searchProxyModel.count === 0) return;

        if (window.lastSearchName === "") {
             window.searchIndexRestored = true;
             return;
        }

        for (let i = 0; i < searchProxyModel.count; i++) {
            let fname = searchProxyModel.get(i).fileName || "";
            if (fname === window.lastSearchName) {
                window.executeFocusRestore(i, true, true);
                return;
            }
        }
        
        if (searchFolderModel.status === FolderListModel.Ready && searchProxyModel.count === searchFolderModel.count) {
             window.searchIndexRestored = true;
        }
    }

    function getModelForFilter(filter) {
        return filter === "Search" ? searchProxyModel : localProxyModel;
    }

    function updateVisibleCount() {
        let targetModel = window.getModelForFilter(window.currentFilter);
        
        if (!targetModel || targetModel.count === 0) {
            window.visibleItemCount = 0;
            return;
        }
        let count = 0;
        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                count++;
            }
        }
        window.visibleItemCount = count;
    }

    function triggerOnlineSearch() {
        if (searchInput.text.trim() === "") return;
        
        window.isModelChanging = true;
        searchProxyModel.clear();
        window.lastSearchName = "";
        searchState.lastName = "";
        
        if (window.currentFilter === "Search") {
            view.currentIndex = 0;
            view.positionViewAtIndex(0, ListView.Center);
        }
        window.isModelChanging = false;

        window.searchIndexRestored = true;
        window.isOnlineSearch = true;
        window.hasSearched = true;
        
        window.visibleItemCount = 0;
        
        searchState.searched = true;
        searchState.query = searchInput.text.trim();
        
        window.isSearchPaused = false;
        window.searchQuery = searchInput.text.trim();
        
        let rawSearchDir = decodeURIComponent(window.searchDir.replace(/^file:\/\//, ""));
        let scriptPath = decodeURIComponent(Qt.resolvedUrl("ddg_search.sh").toString().replace(/^file:\/\//, ""));
        
        const cmd = `
            exec > /tmp/qs_ddg_run.log 2>&1
            echo "=== QML Shell Handoff Successful ==="
            export PATH=$PATH:/run/current-system/sw/bin
            
            echo "Gracefully stopping old processes..."
            echo 'stop' > /tmp/ddg_search_control
            
            for p in $(pgrep -f ddg_search.sh); do
                if [ "$p" != "$$" ] && [ "$p" != "$BASHPID" ]; then
                    kill -9 $p 2>/dev/null || true
                fi
            done
            pkill -f "[g]et_ddg_links.py" || true
            sleep 0.2
            
            echo "Clearing old cache..."
            rm -rf "${rawSearchDir}"/* || true
            rm -f "${rawSearchDir}/../search_map.txt" || true
            
            echo "Setting control state back to run..."
            echo 'run' > /tmp/ddg_search_control
            
            echo "Executing new search pipeline..."
            bash "${scriptPath}" "${window.searchQuery}" &
        `;
        
        Quickshell.execDetached(["bash", "-c", cmd]);
        
        searchInput.focus = false;
        view.forceActiveFocus();
    }

    readonly property string homeDir: "file://" + Quickshell.env("HOME")
    readonly property string thumbDir: homeDir + "/.cache/wallpaper_picker/thumbs"
    readonly property string searchDir: homeDir + "/.cache/wallpaper_picker/search_thumbs"
    readonly property string srcDir: {
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "") 
        ? dir 
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }

    readonly property var transitions: ["simple", "fade", "left", "right", "top", "bottom", "wipe", "grow", "center", "outer", "random", "wave"]

    readonly property real itemWidth: window.s(400)
    readonly property real itemHeight: window.s(420)
    readonly property real borderWidth: window.s(3)
    readonly property real spacing: window.s(10)
    readonly property real skewFactor: -0.35

    Timer {
        id: scrollThrottle
        interval: 150
    }

    property bool isFilterAnimating: false
    Timer {
        id: filterAnimationTimer
        interval: 800
        onTriggered: window.isFilterAnimating = false
    }

    property bool isItemAnimating: false
    Timer {
        id: itemAnimationTimer
        interval: 500
        onTriggered: window.isItemAnimating = false
    }

    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";
        
        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";

        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;

        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";

        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let d = max - min;
        
        let h = 0;
        let s = max === 0 ? 0 : d / max;
        let v = max;

        if (max !== min) {
            if (max === r) {
                h = (g - b) / d + (g < b ? 6 : 0);
            } else if (max === g) {
                h = (b - r) / d + 2;
            } else {
                h = (r - g) / d + 4;
            }
            h /= 6;
        }
        h = h * 360;

        if (s < 0.05 || v < 0.08) return "Monochrome";

        if (h >= 345 || h < 15) return "Red";
        if (h >= 15 && h < 45) return "Orange";
        if (h >= 45 && h < 75) return "Yellow";
        if (h >= 75 && h < 165) return "Green";
        if (h >= 165 && h < 260) return "Blue";
        if (h >= 260 && h < 315) return "Purple";
        if (h >= 315 && h < 345) return "Pink";

        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        if (filter === "Search") return true;

        if (filter === "All") return true;
        if (filter === "Video") return isVid;
        
        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";
        
        return window.getHexBucket(hexColor) === filter;
    }

    FolderListModel {
        id: markerModel
        folder: "file://" + Quickshell.env("HOME") + "/.cache/wallpaper_picker/colors_markers"
        showDirs: false
        nameFilters: ["*_HEX_*"]
        
        onCountChanged: window.processMarkers()
        onStatusChanged: {
            if (status === FolderListModel.Ready) window.processMarkers()
        }
    }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        
        onCountChanged: {
            if (window.isDownloadingWallpaper && window.isDownloaded(window.currentDownloadName)) {
                window.isDownloadingWallpaper = false;
            }
        }
    }

    function processMarkers() {
        let newMap = {};
        for (let i = 0; i < markerModel.count; i++) {
            let markerName = markerModel.get(i, "fileName") || "";
            if (!markerName) continue;
            
            let splitIdx = markerName.lastIndexOf("_HEX_");
            if (splitIdx !== -1) {
                let fName = markerName.substring(0, splitIdx);
                let hexCode = markerName.substring(splitIdx + 5);
                newMap[fName] = "#" + hexCode;
            }
        }
        window.colorMap = newMap;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    function triggerColorExtraction() {
        const extractScript = `
            COLOR_DIR="$HOME/.cache/wallpaper_picker/colors_markers"
            THUMBS="$HOME/.cache/wallpaper_picker/thumbs"
            CSV="$HOME/.cache/wallpaper_picker/colors.csv"
            
            mkdir -p "$COLOR_DIR"
            
            if [ -f "$CSV" ]; then
                while IFS=, read -r fname hexcode; do
                    cleanhex=$(echo "$hexcode" | tr -d '\r#' | cut -c 1-6)
                    if [ -n "$cleanhex" ] && [ -n "$fname" ]; then
                        touch "$COLOR_DIR/$fname""_HEX_$cleanhex" 2>/dev/null
                    fi
                done < "$CSV"
                mv "$CSV" "$CSV.bak" 2>/dev/null
            fi
            
            if command -v magick &> /dev/null; then CMD="magick"; else CMD="convert"; fi
            
            for file in "$THUMBS"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    found=0
                    for marker in "$COLOR_DIR/$filename"_HEX_*; do
                        if [ -e "$marker" ]; then found=1; break; fi
                    done
                    
                    if [ $found -eq 0 ]; then
                        hex=$($CMD "$file" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$hex" ]; then
                            touch "$COLOR_DIR/$filename""_HEX_$hex"
                        fi
                    fi
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", extractScript]);
    }

    function stepToNextValidIndex(direction) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) return;
        
        let start = view.currentIndex;
        let found = -1;

        if (direction === 1) {
            for (let i = start + 1; i < targetModel.count; i++) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        } else {
            for (let i = start - 1; i >= 0; i--) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        }

        if (found !== -1) {
            view.currentIndex = found;
            return;
        }

        let filterOrder = ["All", "Video", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Monochrome"];
        let currentFilterIdx = filterOrder.indexOf(window.currentFilter);

        if (currentFilterIdx === -1) {
            let current = start;
            for (let i = 0; i < targetModel.count; i++) {
                current = (current + direction + targetModel.count) % targetModel.count;
                let fname = targetModel.get(current).fileName || "";
                let isVid = fname.startsWith("000_");
                
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    view.currentIndex = current;
                    return;
                }
            }
            return;
        }

        let nextFilterIdx = currentFilterIdx + direction;

        if (nextFilterIdx >= 0 && nextFilterIdx < filterOrder.length) {
            window.jumpToLastOnFilterChange = (direction === -1);
            window.currentFilter = filterOrder[nextFilterIdx];
        }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) {
                currentIdx = i;
                break;
            }
        }
        
        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters(forceSnap) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        
        if (!targetModel || targetModel.count === 0) {
            window.updateVisibleCount();
            return;
        }

        if (window.currentFilter === "Search") {
            window.updateVisibleCount();
            return;
        }

        let firstValidIndex = -1;
        let lastValidIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        let targetIndex = -1;

        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) {
                    firstValidIndex = i;
                }
                lastValidIndex = i;
                
                if (cleanTarget !== "" && window.getCleanName(fname) === cleanTarget) {
                    targetIndex = i;
                }
            }
        }

        let indexToFocus = -1;

        if (targetIndex !== -1) {
             indexToFocus = targetIndex;
        } else if (window.jumpToLastOnFilterChange && lastValidIndex !== -1) {
            indexToFocus = lastValidIndex;
        } else if (firstValidIndex !== -1) {
            indexToFocus = firstValidIndex;
        }

        window.jumpToLastOnFilterChange = false;
        
        if (indexToFocus !== -1) {
            window.executeFocusRestore(indexToFocus, false, forceSnap === true);
        }
        
        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        window.isFilterAnimating = true;
        filterAnimationTimer.restart();
        window.isModelChanging = true;
        let returningFromSearch = (window._lastFilter === "Search" && window.currentFilter !== "Search");
        window._lastFilter = window.currentFilter;
        
        if (returningFromSearch) {
             window.searchIndexRestored = false;
        }
        
        Qt.callLater(() => {
            view.forceActiveFocus();

            if (window.currentFilter === "Search") {
                if (window.hasSearched) {
                    window.searchIndexRestored = false;
                    window.trySearchFocus();
                }
            } else {
                window.applyFilters(returningFromSearch);
            }
            window.isModelChanging = false;
        });
    }

    Shortcut { 
        sequence: "Left"; 
        enabled: !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(-1) 
    }
    Shortcut { 
        sequence: "Right"; 
        enabled: !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(1) 
    }
    
    Shortcut { 
        sequence: "Return"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: { 
            let targetModel = window.getModelForFilter(window.currentFilter);
            if (view.currentIndex >= 0 && view.currentIndex < targetModel.count) {
                let fname = targetModel.get(view.currentIndex).fileName;
                if (fname) {
                    let isVid = String(fname).startsWith("000_");
                    window.applyWallpaper(String(fname), isVid);
                }
            }
        } 
    }
    
    Shortcut { sequence: "Escape"; enabled: !window.isApplying; onActivated: { if (window.currentFilter === "Search") { window.currentFilter = "All"; } } }
    Shortcut { sequence: "Tab"; enabled: !window.isApplying; onActivated: window.cycleFilter(1) }
    Shortcut { sequence: "Backtab"; enabled: !window.isApplying; onActivated: window.cycleFilter(-1) }

    ListModel { id: localProxyModel }
    ListModel { id: searchProxyModel }
    
    readonly property var activeModel: window.currentFilter === "Search" ? searchProxyModel : localProxyModel

    FolderListModel {
        id: localFolderModel
        folder: window.thumbDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name
        
        onCountChanged: window.syncLocalModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncLocalModel() }
    }

    function syncLocalModel() {
        let startIdx = localProxyModel.count;
        let endIdx = localFolderModel.count;
        
        if (endIdx < startIdx) {
            window.isModelChanging = true;
            localProxyModel.clear();
            startIdx = 0;
            window.isModelChanging = false;
        }

        let batch = [];
        for (let i = startIdx; i < endIdx; i++) {
            let fn = localFolderModel.get(i, "fileName");
            let fu = localFolderModel.get(i, "fileUrl");
            if (fn !== undefined) {
                batch.push({ "fileName": fn, "fileUrl": String(fu) });
            }
        }
        
        if (batch.length > 0) {
            localProxyModel.append(batch);
        }

        if (window.currentFilter !== "Search") window.updateVisibleCount();
        
        if (!window.initialFocusSet && window.currentFilter !== "Search" && localProxyModel.count > 0) {
            window.tryFocus();
        }
    }

    function syncSearchModel() {
        let startIdx = searchProxyModel.count;
        let endIdx = searchFolderModel.count;
        
        if (endIdx < startIdx) {
            window.isModelChanging = true;
            searchProxyModel.clear();
            startIdx = 0;
            window.isModelChanging = false;
        }

        let batch = [];
        for (let i = startIdx; i < endIdx; i++) {
            let fn = searchFolderModel.get(i, "fileName");
            let fu = searchFolderModel.get(i, "fileUrl");
            if (fn !== undefined) {
                batch.push({ "fileName": fn, "fileUrl": String(fu) });
            }
        }
        
        if (batch.length > 0) {
            searchProxyModel.append(batch);
        }

        if (window.currentFilter === "Search") window.updateVisibleCount();

        if (window.currentFilter === "Search" && window.hasSearched) {
            if (!window.searchIndexRestored) {
                window.trySearchFocus();
            }
            
            if (window.isScrollingBlocked && startIdx === 0 && searchProxyModel.count > 0 && window.lastSearchName === "") {
                view.forceLayout();
                view.currentIndex = 0;
                view.positionViewAtIndex(0, ListView.Center);
            }
        }
    }
    FolderListModel {
        id: searchFolderModel
        folder: window.searchDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name
        
        onFolderChanged: {
            window.isModelChanging = true;
            searchProxyModel.clear()
            window.isModelChanging = false;
        }
        
        onCountChanged: window.syncSearchModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncSearchModel() }
    }

     
    ListView {
        id: view
        anchors.fill: parent
        
        opacity: window.isReady ? 1.0 : 0.0
        anchors.margins: window.isReady ? 0 : window.s(40)
        
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }
        Behavior on anchors.margins { NumberAnimation { duration: 700; easing.type: Easing.OutExpo } }

        spacing: 0
        orientation: ListView.Horizontal
        clip: false

        interactive: !window.isScrollingBlocked && !window.isApplying
        cacheBuffer: 2000

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2)
        preferredHighlightEnd: (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2)
        
        highlightMoveDuration: window.initialFocusSet ? 500 : 0
        focus: true
        
        onCurrentIndexChanged: {
            window.isItemAnimating = true;
            itemAnimationTimer.restart();

            if (view.model !== searchProxyModel || window.currentFilter !== "Search") return;
            
            if (!window.isModelChanging && window.hasSearched && window.searchIndexRestored) {
                if (currentIndex >= 0 && currentIndex < searchProxyModel.count) {
                    let fname = searchProxyModel.get(currentIndex).fileName;
                    if (fname !== undefined && fname !== "") {
                        window.lastSearchName = String(fname);
                        searchState.lastName = String(fname);
                    }
                }
            }
        }
        
        add: Transition {
            enabled: window.initialFocusSet
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 400; easing.type: Easing.OutBack }
            }
        }
        addDisplaced: Transition {
            enabled: window.initialFocusSet
            NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutCubic }
        }

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }

        model: window.activeModel

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton

            onWheel: (wheel) => {
                if (window.isScrollingBlocked || window.isApplying) {
                    wheel.accepted = true;
                    return;
                }

                if (scrollThrottle.running) {
                   wheel.accepted = true
                   return
                }

                let dx = wheel.angleDelta.x
                let dy = wheel.angleDelta.y
                let delta = Math.abs(dx) > Math.abs(dy) ? dx : dy

                scrollAccum += delta

                if (Math.abs(scrollAccum) >= scrollThreshold) {
                    window.stepToNextValidIndex(scrollAccum > 0 ? -1 : 1)
                    scrollAccum = 0
                    scrollThrottle.start()
                }

                wheel.accepted = true
            }        
        }

        delegate: Item {
            id: delegateRoot
            
            readonly property string safeFileName: fileName !== undefined ? String(fileName) : ""
            
            readonly property bool isCurrent: ListView.isCurrentItem && !window.isScrollingBlocked
            readonly property bool isFakeSelected: window.isScrollingBlocked && index === 0
            readonly property bool isVisuallyEnlarged: isCurrent || isFakeSelected
            
            readonly property bool isVideo: safeFileName.startsWith("000_")
            readonly property bool matchesFilter: window.checkItemMatchesFilter(safeFileName, isVideo, window.cacheVersion, window.currentFilter)
            
            readonly property real targetWidth: isVisuallyEnlarged ? (window.itemWidth * 1.5) : (window.itemWidth * 0.5)
            readonly property real targetHeight: isVisuallyEnlarged ? (window.itemHeight + window.s(30)) : window.itemHeight
            
            property bool isPlayingVideo: false

            Timer {
                id: videoPlayTimer
                interval: 250
                running: delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo && !window.isScrollingBlocked && !window.isFilterAnimating && !window.isItemAnimating
                onTriggered: {
                    if (delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo) {
                        delegateRoot.isPlayingVideo = true;
                        previewPlayer.play();
                    }
                }
            }

            onIsVisuallyEnlargedChanged: {
                if (!isVisuallyEnlarged) {
                    isPlayingVideo = false;
                    videoPlayTimer.stop();
                    previewPlayer.stop();
                }
            }
            
            width: matchesFilter ? (targetWidth + window.spacing) : 0
            visible: width > 0.1 || opacity > 0.01
            opacity: matchesFilter ? (isVisuallyEnlarged ? 1.0 : 0.6) : 0.0
            
            scale: matchesFilter ? 1.0 : 0.5

            height: matchesFilter ? targetHeight : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: window.s(15)

            z: isVisuallyEnlarged ? 10 : 1
            
            Behavior on scale { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on width { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on height { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

            Item {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: ((window.itemHeight - height) / 2) * window.skewFactor
                
                width: parent.width > 0 ? parent.width * (targetWidth / (targetWidth + window.spacing)) : 0
                height: parent.height

                transform: Matrix4x4 {
                    property real s: window.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
                
                MouseArea {
                    anchors.fill: parent
                    enabled: delegateRoot.matchesFilter && !window.isScrollingBlocked && !window.isApplying
                    onClicked: {
                        view.currentIndex = index
                        window.applyWallpaper(delegateRoot.safeFileName, delegateRoot.isVideo)
                    }
                }

                Image {
                    anchors.fill: parent
                    source: fileUrl !== undefined ? fileUrl : ""
                    sourceSize: Qt.size(1, 1)
                    fillMode: Image.Stretch
                    visible: true
                    asynchronous: true
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: window.borderWidth
                    Rectangle { anchors.fill: parent; color: _theme.base }
                    clip: true

                    Image {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: window.s(-50)
                        width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                        height: window.itemHeight + window.s(30)
                        fillMode: Image.PreserveAspectCrop
                        source: fileUrl !== undefined ? fileUrl : ""
                        asynchronous: true

                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    
                    MediaPlayer {
                        id: previewPlayer
                        source: delegateRoot.isPlayingVideo ? "file://" + window.srcDir + "/" + window.getCleanName(delegateRoot.safeFileName) : ""
                        audioOutput: AudioOutput { muted: true }
                        videoOutput: previewOutput
                        loops: MediaPlayer.Infinite
                    }

                    VideoOutput {
                        id: previewOutput
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: window.s(-50)
                        width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                        height: window.itemHeight + window.s(30)
                        fillMode: VideoOutput.PreserveAspectCrop
                        visible: delegateRoot.isPlayingVideo && previewPlayer.playbackState === MediaPlayer.PlayingState

                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    
                    Rectangle {
                        visible: delegateRoot.isVideo && (!delegateRoot.isPlayingVideo || previewPlayer.playbackState !== MediaPlayer.PlayingState)
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: window.s(10)
                        width: window.s(32)
                        height: window.s(32)
                        radius: window.s(6)
                        color: Qt.rgba(_theme.base.r, _theme.base.g, _theme.base.b, 0.6)
                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                        
                        Canvas {
                            anchors.fill: parent
                            anchors.margins: window.s(8)
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.93);
                                ctx.beginPath();
                                ctx.moveTo(s(4), 0);
                                ctx.lineTo(s(14), s(8));
                                ctx.lineTo(s(4), s(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: filterBarBackground
        anchors.top: parent.top
        
        anchors.topMargin: window.isReady ? window.s(40) : window.s(-100)
        opacity: window.isReady ? 1.0 : 0.0
        Behavior on anchors.topMargin { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        anchors.horizontalCenter: parent.horizontalCenter
        z: 20
        height: window.s(56)
        width: filterRow.width + window.s(24)
        radius: window.s(14)
        
        color: Qt.rgba(_theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.90)
        border.color: _theme.surface2
        border.width: 1

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: window.s(12)

            Rectangle {
                id: notifDrawer
                height: window.s(44)
                property real paddingLeft: window.showSpinner ? window.s(40) : window.s(16)
                property real targetWidth: window.showNotification ? Math.min(notifTextDrawer.implicitWidth + paddingLeft + window.s(20), window.s(300)) : 0
                width: targetWidth
                visible: width > 0.1
                radius: window.s(10)
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                
                color: window.showNotification ? _theme.surface2 : "transparent"
                border.color: window.showNotification ? _theme.surface1 : "transparent"
                border.width: 1

                Behavior on width { 
                    NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } 
                }
                Behavior on color { ColorAnimation { duration: 400 } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                Item {
                    visible: window.showSpinner
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: notifSpinner
                        width: window.s(14)
                        height: window.s(14)
                        anchors.centerIn: parent
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            var s = window.s;
                            ctx.reset();
                            ctx.lineWidth = s(2);
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.3);
                            ctx.beginPath();
                            ctx.arc(s(7), s(7), s(5), 0, Math.PI * 2);
                            ctx.stroke();
                            
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.9);
                            ctx.beginPath();
                            ctx.arc(s(7), s(7), s(5), 0, Math.PI * 0.5);
                            ctx.stroke();
                        }
                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: 800
                            running: window.showSpinner && window.showNotification
                        }
                    }
                }

                Text {
                    id: notifTextDrawer
                    anchors.left: parent.left
                    anchors.leftMargin: window.showSpinner ? window.s(40) : window.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, window.s(300) - anchors.leftMargin - window.s(16))
                    text: window.currentNotification
                    
                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(14)
                    font.bold: true
                    elide: Text.ElideRight

                    opacity: window.showNotification ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                    Behavior on anchors.leftMargin { 
                        NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } 
                    }
                }
            }

            Rectangle {
                id: monitorDrawer
                visible: monitorModel.count > 1
                height: window.s(44)
                
                property real expandedWidth: window.s(44) + monitorListRow.width + window.s(8)
                width: visible ? (window.isMonitorSelectorOpen ? expandedWidth : window.s(44)) : 0
                
                radius: window.s(10)
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                
                color: window.isMonitorSelectorOpen ? _theme.surface2 : "transparent"
                border.color: window.isMonitorSelectorOpen ? _theme.text : _theme.surface1
                border.width: window.isMonitorSelectorOpen ? window.s(2) : 1
                
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400 } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                MouseArea {
                    id: monitorIconMouse
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isMonitorSelectorOpen = !window.isMonitorSelectorOpen
                }

                Canvas {
                    id: monitorIcon
                    width: window.s(18)
                    height: window.s(18)
                    anchors.centerIn: monitorIconMouse
                    property string activeColor: window.isMonitorSelectorOpen ? _theme.text : (monitorIconMouse.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var s = window.s;
                        ctx.reset();
                        ctx.lineWidth = s(2);
                        ctx.strokeStyle = activeColor;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";
                        
                        ctx.beginPath();
                        ctx.rect(s(2), s(3), s(14), s(9));
                        ctx.stroke();
                        
                        ctx.beginPath();
                        ctx.moveTo(s(9), s(12));
                        ctx.lineTo(s(9), s(16));
                        ctx.moveTo(s(5), s(16));
                        ctx.lineTo(s(13), s(16));
                        ctx.stroke();
                    }
                }

                Row {
                    id: monitorListRow
                    anchors.left: monitorIconMouse.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: window.s(8)
                    
                    opacity: window.isMonitorSelectorOpen ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Repeater {
                        model: monitorModel
                        delegate: Item {
                            width: monitorText.contentWidth + window.s(16)
                            height: window.s(32)
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: window.s(6)
                                color: model.selected ? _theme.text : _theme.surface1
                                border.color: model.selected ? _theme.text : _theme.surface2
                                border.width: 1
                                
                                Behavior on color { ColorAnimation { duration: 250 } }
                                Behavior on border.color { ColorAnimation { duration: 250 } }
                                
                                Text {
                                    id: monitorText
                                    text: model.name
                                    anchors.centerIn: parent
                                    color: model.selected ? _theme.base : _theme.text
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(12)
                                    font.bold: model.selected
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: window.isMonitorSelectorOpen && !window.isApplying
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (model.selected) {
                                        let activeCount = 0;
                                        for (let i = 0; i < monitorModel.count; i++) {
                                            if (monitorModel.get(i).selected) activeCount++;
                                        }
                                        if (activeCount > 1) {
                                            monitorModel.setProperty(index, "selected", false);
                                        }
                                    } else {
                                        monitorModel.setProperty(index, "selected", true);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: window.filterData

                delegate: Item {
                    visible: modelData.name !== "Search"
                    width: !visible ? 0 : ((modelData.name === "Video" || modelData.name === "All") ? window.s(44) : (modelData.hex === "" ? filterText.contentWidth + window.s(24) : window.s(36)))
                    height: !visible ? 0 : window.s(36)
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: window.s(10)
                        color: modelData.hex === "" 
                                ? (window.currentFilter === modelData.name ? _theme.surface2 : "transparent") 
                                : modelData.hex
                        
                        border.color: window.currentFilter === modelData.name ? _theme.text : _theme.surface1
                        border.width: window.currentFilter === modelData.name ? window.s(2) : 1
                        scale: window.currentFilter === modelData.name ? 1.15 : (filterMouse.containsMouse ? 1.08 : 1.0)
                        
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Text {
                            id: filterText
                            visible: modelData.hex === "" && modelData.name !== "Video" && modelData.name !== "All"
                            text: modelData.label
                            anchors.centerIn: parent
                            color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(14)
                            font.bold: window.currentFilter === modelData.name
                            Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                        }

                        Canvas {
                            visible: modelData.name === "Video"
                            width: window.s(14); height: window.s(16)
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: window.s(2)
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.beginPath();
                                ctx.moveTo(0, 0);
                                ctx.lineTo(s(14), s(8));
                                ctx.lineTo(0, s(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }

                        Canvas {
                            visible: modelData.name === "All"
                            width: window.s(14); height: window.s(14)
                            anchors.centerIn: parent
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.fillRect(0, 0, s(6), s(6));
                                ctx.fillRect(s(8), 0, s(6), s(6));
                                ctx.fillRect(0, s(8), s(6), s(6));
                                ctx.fillRect(s(8), s(8), s(6), s(6));
                            }
                        }
                    }

                    MouseArea {
                        id: filterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: window.currentFilter = modelData.name
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Rectangle {
                id: searchControlBtn
                visible: window.currentFilter === "Search" && window.hasSearched
                width: visible ? window.s(44) : 0
                height: window.s(44)
                radius: window.s(10)
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                color: window.isSearchPaused ? _theme.surface2 : "transparent"
                border.color: window.isSearchPaused ? _theme.text : _theme.surface1
                border.width: window.isSearchPaused ? window.s(2) : 1
                
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                
                MouseArea {
                    id: scMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isSearchPaused = !window.isSearchPaused
                }
                
                Canvas {
                    width: window.s(44); height: window.s(44)
                    anchors.centerIn: parent
                    property bool paused: window.isSearchPaused
                    property string activeColor: paused ? _theme.text : (scMouse.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    onPausedChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()
                    
                    onPaint: {
                        var ctx = getContext("2d");
                        var s = window.s;
                        ctx.reset();
                        ctx.fillStyle = activeColor;
                        if (!paused) {
                            ctx.fillRect(s(15), s(14), s(4), s(16));
                            ctx.fillRect(s(25), s(14), s(4), s(16));
                        } else {
                            ctx.beginPath();
                            ctx.moveTo(s(16), s(12));
                            ctx.lineTo(s(32), s(22));
                            ctx.lineTo(s(16), s(32));
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }
            }

            Rectangle {
                id: searchBox
                height: window.s(44)
                width: window.currentFilter === "Search" ? window.s(360) : window.s(44)
                radius: window.s(10)
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                
                color: window.currentFilter === "Search" ? Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.8) : "transparent"
                border.color: window.currentFilter === "Search" ? _theme.text : _theme.surface1
                border.width: window.currentFilter === "Search" ? window.s(2) : 1
                
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                MouseArea {
                    id: searchMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.currentFilter !== "Search") {
                            window.currentFilter = "Search"
                        } else {
                            window.currentFilter = "All"
                        }
                    }
                }

                Canvas {
                    id: searchIcon
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.leftMargin: window.currentFilter === "Search" ? window.s(5) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                    property string activeColor: window.currentFilter === "Search" ? _theme.text : (searchMouseArea.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var s = window.s;
                        ctx.reset();
                        ctx.lineWidth = s(3);
                        ctx.strokeStyle = activeColor;
                        ctx.beginPath();
                        ctx.arc(s(18), s(18), s(7), 0, Math.PI * 2);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(s(23), s(23));
                        ctx.lineTo(s(31), s(31));
                        ctx.stroke();
                    }
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchIcon.right
                    anchors.right: submitBtn.left
                    anchors.rightMargin: window.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    
                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                    
                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(16)
                    clip: true
                    
                    onTextEdited: {
                        window.hasSearched = false;
                        searchState.searched = false;
                    }
                    
                    onAccepted: {
                        window.triggerOnlineSearch();
                        searchInput.focus = false;
                        view.forceActiveFocus();
                    }
                }

                Rectangle {
                    id: submitBtn
                    width: window.s(32)
                    height: window.s(32)
                    radius: window.s(8)
                    anchors.right: parent.right
                    anchors.rightMargin: window.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    
                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

                    color: submitMouseArea.containsMouse ? _theme.surface1 : "transparent"
                    border.color: submitMouseArea.containsMouse ? _theme.text : _theme.surface2
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 300 } }

                    MouseArea {
                        id: submitMouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: {
                            window.triggerOnlineSearch();
                        }
                    }

                    Canvas {
                        width: window.s(16)
                        height: window.s(16)
                        anchors.centerIn: parent
                        property string activeColor: submitMouseArea.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                        onActiveColorChanged: requestPaint()
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()
                        
                        onPaint: {
                            var ctx = getContext("2d");
                            var s = window.s;
                            ctx.reset();
                            ctx.lineWidth = s(2);
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.strokeStyle = activeColor;
                            
                            ctx.beginPath();
                            ctx.moveTo(s(2), s(8));
                            ctx.lineTo(s(14), s(8));
                            ctx.moveTo(s(9), s(3));
                            ctx.lineTo(s(14), s(8));
                            ctx.lineTo(s(9), s(13));
                            ctx.stroke();
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", "mkdir -p '" + decodeURIComponent(window.searchDir.replace("file://", "")) + "'"]);
        
        window.loadMonitors();

        if (searchState.searched) {
            searchInput.text = searchState.query;
            window.searchQuery = searchState.query;
            window.hasSearched = true;
            window.lastSearchName = searchState.lastName;
            window.isSearchPaused = true;
        }

        view.forceActiveFocus();
        window.processMarkers();
        window.triggerColorExtraction();
    }

    Component.onDestruction: {
        if (window.hasSearched) {
            searchState.query = searchInput.text;
            searchState.searched = window.hasSearched;
            searchState.lastName = window.lastSearchName;
            
            Quickshell.execDetached(["bash", "-c", "echo 'pause' > /tmp/ddg_search_control"]);
        } else {
            Quickshell.execDetached(["bash", "-c", "echo 'stop' > /tmp/ddg_search_control; for p in $(pgrep -f ddg_search.sh); do if [ \"$p\" != \"$$\" ] && [ \"$p\" != \"$BASHPID\" ]; then kill -9 $p 2>/dev/null || true; fi; done; pkill -f '[g]et_ddg_links.py'"]);
        }
    }
}
