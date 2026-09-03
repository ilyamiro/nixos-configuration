pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: controller

    signal setIndexRequested(var screen, string index)
    signal showSystemUsageRequested(var screen)

    function targetScreen(screen) {
        if (screen) return screen;
        if (Quickshell.cursorScreen) return Quickshell.cursorScreen;
        return Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function setIndex(index, screen) {
        let target = targetScreen(screen);
        if (target) controller.setIndexRequested(target, index);
    }

    function showSystemUsage(screen) {
        let target = targetScreen(screen);
        if (target) controller.showSystemUsageRequested(target);
    }

    IpcHandler {
        target: "floating"

        function setIndex(index: string) {
            controller.setIndex(index, null);
        }

        function showSystemUsage() {
            controller.showSystemUsage(null);
        }

        function forceReload() {
            Quickshell.reload(true)
        }
    }
}
