{ config, pkgs, lib, ... }:

{
  imports = [
    ./hypridle.nix 
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = ''
      source = /etc/nixos/config/sessions/hyprland/hyprland.conf
    '';
  };

  home.packages = with pkgs; [
    rofi
    pavucontrol
    fortune
    wl-screenrec
    alsa-utils
    awww
    networkmanager_dmenu
    wl-clipboard
    fd
    qt6.qtmultimedia
    qt6.qt5compat
    qt6.qtwebsockets
    qt6.qtwebengine
    ripgrep
    gtk3
    cava
    cliphist
    tree
    jq
    socat 
    pamixer 
    brightnessctl
    acpi
    iw
    bluez
    libnotify
    networkmanager
    lm_sensors
    bc
    pulseaudio
    ladspaPlugins
    ladspa-sdk
    imagemagick
  ];

  home.sessionVariables.NIXOS_OZONE_WL = "1";

  home.file.".config/hypr/scripts".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/config/sessions/hyprland/scripts";	
  home.activation.copyHyprConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.rsync}/bin/rsync -a --update /etc/nixos/config/sessions/hyprland/config/ $HOME/.config/hypr/config/
      chmod -R u+w $HOME/.config/hypr/config
  '';
}
