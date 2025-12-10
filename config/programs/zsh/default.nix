{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history.size = 10000;
    history.path = "$HOME/.zsh_history";
    history.ignoreAllDups = true;

    initContent = ''
    cd() {
      builtin cd $@ &&
      ls
    } 
    '';

    shellAliases = {
      edit = "sudo -E nvim";
      gitavail = "ssh-add $HOME/Life/Важное/recovery_keys/GitHub/github_remote_keys/key";
      update = "sudo nixos-rebuild switch";
      stop = "shutdown now";
      edconf = "sudo -E nvim /etc/nixos/configuration.nix";
      out = "loginctl terminate-user ilyamiro";
    };
    
    
    oh-my-zsh = {
        enable = true;
        plugins = [
          "git"                
        ];
        theme = "robbyrussell";
      };
    };

  home.sessionVariables = {
      hypr = "/etc/nixos/config/sessions/hyprland/";  
      programs = "/etc/nixos/config/programs";
    };


}



