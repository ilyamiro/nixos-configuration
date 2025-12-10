{ pkgs, config, ... }:

{
  home.packages = with pkgs; [ 
    jq
    socat 
    pamixer 
    brightnessctl
    acpi
    iw
  ];

  xdg.configFile."eww".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/config/programs/eww/my-eww-config/eww";
}
