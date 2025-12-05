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
      gaps_in = 2;
      gaps_out = 4;
    };
    decoration = {
      rounding = 4;
      inactive_opacity = 0.8; 
    };
    input = {
      kb_layout = "us, ru";
      kb_variant = "";
      kb_model = "";
      kb_rules = "";
      touchpad = {
        natural_scroll = true;
      };
    };
  };

  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
