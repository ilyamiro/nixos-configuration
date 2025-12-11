{ config, pkgs, ... }:

{
  imports = [
    # programs
    ./config/programs/zsh/default.nix
    ./config/programs/neovim/default.nix
    ./config/programs/waybar/default.nix
    ./config/programs/eww/default.nix

    # sessions
    ./config/sessions/hyprland/default.nix
  ]; 

  home.username = "ilyamiro";
  home.homeDirectory = "/home/ilyamiro";
  home.stateVersion = "25.11"; 
  
  
  
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };
  
  gtk = {
    gtk3 = {
      extraConfig = {
        gtk-application-prefer-dark-theme=1;
      };
  
    };
    gtk4 = {
      extraConfig = {
        gtk-application-prefer-dark-theme=1;
      };
  
    };
    enable = true;
    theme = { 
      name = "Adwaita-dark"; 
      package = pkgs.gnome-themes-extra;
    }; 
    iconTheme = { 
      name = "Adwaita"; 
      package = pkgs.gnome-themes-extra; 
    }; 
    cursorTheme = { 
      name = "Adwaita"; 
      package = pkgs.gnome-themes-extra; 
    };
  };

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "gtk3";
  };
  
  programs.home-manager.enable = true;



  fonts.fontconfig.enable = true; 
  
  home.file = {
    ".local/share/fonts/eww-fonts" = {
      source = config/programs/eww/my-eww-config/fonts; 
      recursive = true;
    };
  };

}

