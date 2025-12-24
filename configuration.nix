# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  # Imports
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      <home-manager/nixos>
    ];

  # System packages
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget 
    taskwarrior3
    git 
    neovim
    python311
    ffmpeg
    python314
    adw-gtk3
    (wrapFirefox (pkgs.firefox-unwrapped.override { pipewireSupport = true; }) {})
    telegram-desktop
    kitty
    libreoffice-qt
    hunspell
    hunspellDicts.ru_RU
    hunspellDicts.en_US
    obsidian
    obs-studio
    gnome-themes-extra
    fastfetch
    gnome-shell-extensions
    grim
    playerctl
    xdg-desktop-portal-gtk
    eww
    gnome-tweaks
    pkgsCross.mingwW64.stdenv.cc
    wmctrl
    bottles
    qbittorrent
    power-profiles-daemon
  ];

  environment.pathsToLink = [ "/share/gsettings-schemas" ]; # <-- Add this line!

  # User accounts and security
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ilyamiro = {
    isNormalUser = true;
    description = "ilyamiro";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
    useDefaultShell = true;
    shell = pkgs.zsh;
  };    

  users.defaultUserShell = pkgs.zsh;
  system.userActivationScripts.zshrc = "touch .zshrc";

  security.sudo.extraRules = [
    {
      users = [ "ilyamiro" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Program configurations
  programs.zsh.enable = true;

  # Install firefox.
  programs.firefox.enable = true;

  programs.dconf.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Home manager
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true; 
  
  # Import your home.nix HERE instead
  home-manager.users.ilyamiro = {
    imports = [ ./home.nix ];
  };

  # Desktop environment, window managers and theme
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  
  # Hyprland
  programs.hyprland.enable = true;
  
  # XDG Portals
  xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-wlr ]; # Or xdg-desktop-portal-gtk for GNOME/KDE
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us,ru";
    variant = "";
  };

  # Qt Theming
  qt = {
    enable = true;
    style = "adwaita-dark";
    platformTheme = "gnome";
  };

  # Fonts
  fonts.packages = with pkgs; [
    udev-gothic-nf
    noto-fonts
    liberation_ttf
  ];

  # Flatpak
  services.flatpak.enable = true;

  # Environment Variables
  environment.variables.XDG_DATA_DIRS = lib.mkForce "/home/your_user/.nix-profile/share:/run/current-system/sw/share";

  # Networking and time
  networking.hostName = "ilyamiro"; # Define your hostname.
  
  # Enable networking
  networking.networkmanager.enable = true;
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Set your time zone.
  time.timeZone = "Europe/Copenhagen";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Audio and system services
  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Power Management Services
  services.power-profiles-daemon.enable = true; 

  # Nix settings and maintenance
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Experimental features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # Bootloader and kernel
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel Packages and Optimization
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "amd_pstate=active" "tsc=reliable" "asus_wmi"]; 
  hardware.cpu.amd.updateMicrocode = true;
  powerManagement.cpuFreqGovernor = "schedutil";

  system.stateVersion = "25.11"; 

}
