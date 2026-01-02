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
    papers
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
    jdk8
    steam-run
  ];

  environment.pathsToLink = [ "/share/gsettings-schemas" ];

  # User accounts and security
  users.users.ilyamiro = {
    isNormalUser = true;
    description = "ilyamiro";
    extraGroups = [ "networkmanager" "wheel" "video" ]; # Added "video" group
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
    remotePlay.openFirewall = true; 
    dedicatedServer.openFirewall = true; 
  };
  programs.gamemode.enable = true;

  # Home manager
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true; 
  
  home-manager.users.ilyamiro = {
    imports = [ ./home.nix ];
  };

  # Desktop environment, window managers and theme
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  
  # Hyprland
  programs.hyprland.enable = true;
  
  # XDG Portals
  xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-wlr ]; 
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
  # FIX: Changed 'your_user' to 'ilyamiro' to match your actual username
  environment.variables.XDG_DATA_DIRS = lib.mkForce "/home/ilyamiro/.nix-profile/share:/run/current-system/sw/share";

  # Networking and time
  networking.hostName = "ilyamiro"; 
  
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false; 
  };
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
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  boot.kernelModules = [ "tcp_bbr" ]; # FIX: Network Congestion Control (Helps with packet jitter)
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.wmem_max" = 1073741824;
    "net.core.rmem_max" = 1073741824;
    "net.ipv4.tcp_rmem" = "4096 87380 1073741824";
    "net.ipv4.tcp_wmem" = "4096 87380 1073741824";
  };

  # FIX: Force CPU to run at max clock speed to prevent frame-time jitter
  powerManagement.cpuFreqGovernor = "performance";

  # ==========================================
  # GPU / GRAPHICS CONFIGURATION (ADDED)
  # ==========================================

  # Enable OpenGL/Vulkan (renamed to hardware.graphics in 24.11+)
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Required for Steam/CS2
  };

  # Load NVIDIA Drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption after suspend/wake.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures.
    # We set to false here for maximum stability on the mobile 3050.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Select the stable driver version
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # PRIME CONFIGURATION (Hybrid Graphics)
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      # Bus IDs derived from your lspci output
      # NVIDIA: 01:00.0 -> PCI:1:0:0
      # AMD: 04:00.0 -> PCI:4:0:0
      nvidiaBusId = "PCI:1:0:0";
      amdgpuBusId = "PCI:4:0:0";
    };
  };

  system.stateVersion = "25.11"; 
}
