pragma Singleton
import QtQuick
import Quickshell

Item {
    id: root

    signal geometryChanged(string monitor, string widgetId, real x, real y, real w, real h, real opacity, real rotation)
    signal opacityChanged(string monitor, string widgetId, real opacity)
    signal rotationChanged(string monitor, string widgetId, real rotation)
    signal variantChanged(string monitor, string widgetId, string variant)
    signal imagePathChanged(string monitor, string widgetId, string imagePath)
    signal widgetAdded(string monitor, string widgetId, string type, real x, real y, real w, real h, real opacity, string imagePath, real rotation)
    signal widgetRemoved(string monitor, string widgetId)
    signal widgetsCleared(string monitor)
    signal bringToFrontRequested(string monitor, string widgetId)
    signal redactModeChanged(string monitor, bool active)

    function setGeometry(monitor: string, widgetId: string, x: real, y: real, w: real, h: real, opacity: real, rotation: real): void {
        root.geometryChanged(monitor, widgetId, x, y, w, h, opacity, rotation);
    }

    function setOpacity(monitor: string, widgetId: string, opacity: real): void {
        root.opacityChanged(monitor, widgetId, opacity);
    }

    function setRotation(monitor: string, widgetId: string, rotation: real): void {
        root.rotationChanged(monitor, widgetId, rotation);
    }

    function setVariant(monitor: string, widgetId: string, variant: string): void {
        root.variantChanged(monitor, widgetId, variant);
    }

    function setImagePath(monitor: string, widgetId: string, imagePath: string): void {
        root.imagePathChanged(monitor, widgetId, imagePath);
    }

    function addWidget(monitor: string, widgetId: string, type: string, x: real, y: real, w: real, h: real, opacity: real, imagePath: string, rotation: real): void {
        root.widgetAdded(monitor, widgetId, type, x, y, w, h, opacity, imagePath, rotation);
    }

    function removeWidget(monitor: string, widgetId: string): void {
        root.widgetRemoved(monitor, widgetId);
    }

    function clearWidgets(monitor: string): void {
        root.widgetsCleared(monitor);
    }

    function bringToFront(monitor: string, widgetId: string): void {
        root.bringToFrontRequested(monitor, widgetId);
    }

    function setRedactMode(monitor: string, active: bool): void {
        root.redactModeChanged(monitor, active);
    }
}
