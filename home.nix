{ config, pkgs, ... }:

{
  imports = [
    # programs
    ./config/programs/zsh/default.nix
    ./config/programs/neovim/default.nix
    ./config/programs/waybar/default.nix

    # sessions
    ./config/sessions/hyprland/default.nix
  ]; 

  home.username = "ilyamiro";
  home.homeDirectory = "/home/ilyamiro";
  home.stateVersion = "25.11"; 
  
  
  dconf = {
      enable = true;
      settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
    };

  gtk = { 
    enable = true;
    theme = { 
      name = "Adwaita"; 
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
    QT_QPA_PLATFORMTHEME = "qt6ct";
  };
  
  programs.home-manager.enable = true;
}

