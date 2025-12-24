{ pkgs, config, lib, ... }:

{
  xdg.configFile."hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/config/sessions/hyprland/hyprlock/hyprlock.conf";
  xdg.configFile."hypr/hyprlock/scripts".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/config/sessions/hyprland/hyprlock/scripts";

}
