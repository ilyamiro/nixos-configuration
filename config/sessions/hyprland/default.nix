{ config, pkgs, lib, ... }:

{
  imports = [
    ./binds.nix
    ./autostart.nix
    ./animations.nix
    ./monitors.nix

    ./window-rules.nix
  ];

  wayland.windowManager.hyprland.enable = true;

  home.packages = with pkgs; [
    waybar
    rofi
    pavucontrol
    fortune
    alsa-utils
    swww
    networkmanager_dmenu
    wl-clipboard
    hyprshot
    fd 
    ripgrep
    gtk3
    cava
    cliphist
  ];

  wayland.windowManager.hyprland.settings = {
    general = {
      border_size = 0;
      gaps_in = 4;
      gaps_out = 4;
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
      accel_profile = "flat";
    };
    misc = {
      font_family = "JetBrains Mono";
    };
  };

  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
