{ config, pkgs, lib, ... }:



{
  imports = [
    ./binds.nix
  ];

  wayland.windowManager.hyprland.enable = true;

  home.packages = with pkgs; [
    waybar
    rofi
    pavucontrol
  ];

  wayland.windowManager.hyprland.settings = {
    general = {
      border_size = 0;
      gaps_in = 3;
      gaps_out = 6;
    };
    input = {
      touchpad = {
        natural_scroll = true;
      };
    };
  };

  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
