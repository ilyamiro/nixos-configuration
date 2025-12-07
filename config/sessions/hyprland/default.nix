{ config, pkgs, lib, ... }:

{
  imports = [
    ./binds.nix
    ./autostart.nix
    ./animations.nix
    ./monitors.nix
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
      gaps_in = 4;
      gaps_out = 6;
      float_gaps = 6;
      resize_on_border = true;
      extend_border_grab_area = 30;

    };
    decoration = {
      rounding = 4;
      active_opacity = 1.0;
      inactive_opacity = 1.0;
      blur = {
        enabled = false;
      };
      shadow = {
        enabled = false;
      };
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
    misc = {
      font_family = "JetBrains Mono";
    };
  };

  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
