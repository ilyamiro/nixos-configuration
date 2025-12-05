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

    shellAliases = {
      edit = "sudo -E nvim";
      gitavail = "ssh-add $HOME/Life/Важное/recovery_keys/GitHub/github_remote_keys/key";
      update = "sudo nixos-rebuild switch";
      stop = "shutdown now";
      edconf = "sudo -E nvim /etc/nixos/configuration.nix";
    };

    oh-my-zsh = {
        enable = true;
        plugins = [
          "git"                
        ];
        theme = "robbyrussell";
      };
  };

}

