.pragma library

function getScale(mw, mh, userScale) {
    return (userScale !== undefined && userScale !== null) ? userScale : 1.0;
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getWidgetLauncherEntries(i18n) {
    function tr(key, fallback) {
        if (i18n && typeof i18n.t === "function") {
            let res = i18n.t(key);
            if (res && res !== key) return res;
        }
        return fallback;
    }

    return [
        {
            id: "wallpaper",
            name: tr("widgets.wallpaper.name", "Wallpaper Picker"),
            description: tr("widgets.wallpaper.desc", "Browse and set desktop wallpaper"),
            icon: "preferences-desktop-wallpaper",
            fontIcon: "󰸉"
        },
        {
            id: "network",
            name: tr("widgets.network.name", "Network Settings"),
            description: tr("widgets.network.desc", "Manage WiFi, Ethernet, and network connections"),
            icon: "network-wireless",
            fontIcon: "󰤨"
        },
        {
            id: "volume",
            name: tr("widgets.volume.name", "Volume & Audio"),
            description: tr("widgets.volume.desc", "Manage sound devices and volume levels"),
            icon: "audio-volume-high",
            fontIcon: "󰕾"
        },
        {
            id: "guide",
            name: tr("widgets.guide.name", "Settings"),
            description: tr("widgets.guide.desc", "Serpantinum settings"),
            icon: "help-browser",
            fontIcon: "󰋖"
        },
        {
            id: "calendar",
            name: tr("widgets.calendar.name", "Calendar & Clock"),
            description: tr("widgets.calendar.desc", "View date, time, and schedule"),
            icon: "x-office-calendar",
            fontIcon: "󰸗"
        },
        {
            id: "music",
            name: tr("widgets.music.name", "Media Player"),
            description: tr("widgets.music.desc", "Control music and media playback"),
            icon: "multimedia-audio-player",
            fontIcon: "󰝚"
        },
        {
            id: "system",
            name: tr("widgets.system.name", "System Controls"),
            description: tr("widgets.system.desc", "Performance monitor, power, and quick settings"),
            icon: "preferences-system",
            fontIcon: "󰒓"
        },
        {
            id: "translator",
            name: tr("widgets.translator.name", "Translator"),
            description: tr("widgets.translator.desc", "Instant multi-language translation"),
            icon: "preferences-desktop-locale",
            fontIcon: "󰗊"
        }
    ];
}

function getLayout(name, mx, my, mw, mh, userScale, barPosition) {
    let scale = (userScale !== undefined && userScale !== null) ? userScale : 1.0;
    if (!barPosition) barPosition = "top";

    let base = {
        "network": { 
            w: 720, h: 600, comp: "network/NetworkPopup.qml", 
            pos: { 
                "top": { anchor: "top-right", mt: 52, mr: 4 }, 
                "bottom": { anchor: "bottom-right", mb: 52, mr: 4 }, 
                "left": { anchor: "bottom-left", ml: 52, mb: 4 }, 
                "right": { anchor: "bottom-right", mr: 52, mb: 4 } 
            } 
        },
        "volume": { 
            w: 410, h: 580, comp: "volume/VolumePopup.qml", 
            pos: { 
                "top": { anchor: "top-right", mt: 52, mr: 5 }, 
                "bottom": { anchor: "bottom-right", mb: 52, mr: 5 }, 
                "left": { anchor: "bottom-left", ml: 52, mb: 5 }, 
                "right": { anchor: "bottom-right", mr: 52, mb: 5 } 
            } 
        },
        "guide": { 
            w: 1200, h: 750, comp: "guide/GuidePopup.qml", 
            pos: { 
                "top": { anchor: "center" }, 
                "bottom": { anchor: "center" }, 
                "left": { anchor: "center" }, 
                "right": { anchor: "center" } 
            } 
        },
        "calendar": { 
            w: 1360, h: 510, comp: "calendar/CalendarPopup.qml", 
            pos: { 
                "top": { anchor: "top-center", mt: 52 }, 
                "bottom": { anchor: "bottom-center", mb: 52 }, 
                "left": { anchor: "top-center", mt: 12 }, 
                "right": { anchor: "top-center", mt: 12 } 
            } 
        },
        "wallpaper": { 
            w: "fill", h: 650, comp: "wallpaper/WallpaperPicker.qml", 
            pos: { 
                "top": { anchor: "center-left" }, 
                "bottom": { anchor: "center-left" }, 
                "left": { anchor: "center-left" }, 
                "right": { anchor: "center-left" } 
            } 
        },
        "music": { 
            w: 625, h: 565, comp: "media/MusicPopup.qml", 
            pos: { 
                "top": { anchor: "top-left", mt: 52, ml: 5 }, 
                "bottom": { anchor: "bottom-left", mb: 52, ml: 5 }, 
                "left": { anchor: "top-left", mt: 5, ml: 52 }, 
                "right": { anchor: "top-right", mt: 5, mr: 52 } 
            } 
        },
        "notifications": { 
            w: 500, h: "fill", comp: "notifications/NotificationCenter.qml", 
            pos: { 
                "top": { anchor: "left" }, 
                "bottom": { anchor: "left" }, 
                "left": { anchor: "left" }, 
                "right": { anchor: "left" } 
            } 
        },
        "system": { 
            w: 500, h: "fill", comp: "syspanel/SystemPanel.qml", 
            pos: { 
                "top": { anchor: "right" }, 
                "bottom": { anchor: "right" }, 
                "left": { anchor: "right" }, 
                "right": { anchor: "left" } 
            } 
        },
        "translator": { 
            w: 860, h: 560, comp: "translator/TranslatorPopup.qml", 
            pos: { 
                "top": { anchor: "center" }, 
                "bottom": { anchor: "center" }, 
                "left": { anchor: "center" }, 
                "right": { anchor: "center" } 
            } 
        },
        "hidden": { 
            w: 1, h: 1, comp: "", 
            pos: { 
                "top": { anchor: "hidden" }, 
                "bottom": { anchor: "hidden" }, 
                "left": { anchor: "hidden" }, 
                "right": { anchor: "hidden" } 
            } 
        }
    };

    if (!base[name]) return null;
    let t = base[name];
    let p = t.pos[barPosition] || t.pos["top"];

    let finalW = t.w === "fill" ? mw : s(t.w, scale);
    let finalH = t.h === "fill" ? mh : s(t.h, scale);

    let rx = 0;
    let ry = 0;

    switch (p.anchor) {
        case "center":
            rx = Math.floor((mw / 2) - (finalW / 2));
            ry = Math.floor((mh / 2) - (finalH / 2));
            break;
        case "top-right":
            rx = mw - finalW - s(p.mr || 0, scale);
            ry = s(p.mt || 0, scale);
            break;
        case "bottom-right":
            rx = mw - finalW - s(p.mr || 0, scale);
            ry = mh - finalH - s(p.mb || 0, scale);
            break;
        case "top-left":
            rx = s(p.ml || 0, scale);
            ry = s(p.mt || 0, scale);
            break;
        case "bottom-left":
            rx = s(p.ml || 0, scale);
            ry = mh - finalH - s(p.mb || 0, scale);
            break;
        case "top-center":
            rx = Math.floor((mw / 2) - (finalW / 2));
            ry = s(p.mt || 0, scale);
            break;
        case "bottom-center":
            rx = Math.floor((mw / 2) - (finalW / 2));
            ry = mh - finalH - s(p.mb || 0, scale);
            break;
        case "left":
            rx = s(p.ml || 0, scale);
            ry = Math.floor((mh / 2) - (finalH / 2));
            break;
        case "right":
            rx = mw - finalW - s(p.mr || 0, scale);
            ry = Math.floor((mh / 2) - (finalH / 2));
            break;
        case "center-left":
            rx = s(p.ml || 0, scale);
            ry = Math.floor((mh / 2) - (finalH / 2));
            break;
        case "center-right":
            rx = mw - finalW - s(p.mr || 0, scale);
            ry = Math.floor((mh / 2) - (finalH / 2));
            break;
        case "fill":
            rx = 0;
            ry = 0;
            break;
        case "hidden":
            rx = -5000;
            ry = -5000;
            break;
    }

    return { w: finalW, h: finalH, rx: mx + rx, ry: my + ry, comp: t.comp };
}

function getPopupLayout(mw, mh, userScale) {
    let scale = (userScale !== undefined && userScale !== null) ? userScale : 1.0;
    return {
        w: s(350, scale), marginTop: s(52, scale), marginRight: s(20, scale),
        spacing: s(12, scale), radius: s(14, scale), padding: s(12, scale)
    };
}
