{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules.nix
  ];
  programs.waybar.enable = true;

  programs.waybar.settings.main = {
    layer = "top";
    position = "top";
    exclusive = true;
    passthrough = false;
    gtk-layer-shell = true;
    margin-left = 6;
    margin-right = 6;
    margin-top = 2;

    modules-left = [
      "battery"
      # "clock"
      # "custom/swaync"
      # "hyprland/workspaces"
      # "custom/playerctl"
    ];
    modules-center = [
      # "hyprland/window"
    ];
    modules-right = [
      #"tray"
      #"backlight"
      #"group/audio"
      #"custom/keyboard"
      #"custom/power"
    ];

  };
}
