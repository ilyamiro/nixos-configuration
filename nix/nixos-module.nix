{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.serpantinum;
in
{
  options.programs.serpantinum = {
    enable = mkEnableOption "system-level support for the Serpantinum desktop shell";
  };

  config = mkIf cfg.enable {
    networking.networkmanager.enable = mkDefault true;
    hardware.bluetooth.enable = mkDefault true;
    hardware.i2c.enable = mkDefault true;
    services.power-profiles-daemon.enable = mkDefault true;
    security.rtkit.enable = mkDefault true;

    services.pipewire = {
      enable = mkDefault true;
      alsa.enable = mkDefault true;
      alsa.support32Bit = mkDefault true;
      pulse.enable = mkDefault true;
    };

    fonts.packages = [ pkgs.nerd-fonts.iosevka ];
  };
}
