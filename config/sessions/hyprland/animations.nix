{ lib, config, ... }:
{
   wayland.windowManager.hyprland.settings = {
      animations = {
        enabled = "yes";
        bezier = ["myBezier, 0.05, 0.9, 0.1, 1.05"];
        animation = [
          "windows, 1, 5, myBezier, slide"
          "windowsOut, 1, 5, myBezier, slide"
          "layers, 1, 5, myBezier, fade"
          "layersIn, 1, 5, myBezier, slide top"
          "layersOut, 1, 5, myBezier, slide bottom"
          "fade, 1, 5, myBezier"
          "workspaces, 1, 5, myBezier, slide"
          "specialWorkspaceIn, 1, 5, myBezier, slide bottom"
          "specialWorkspaceOut, 1, 5, myBezier, slide top"
        ];
      };
    };
}
