{ pkgs, config, lib, ... }:

{ 
  xdg.configFile."rofi".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/config/programs/rofi";
}
