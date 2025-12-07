{ config, pkgs, ... }:

{
   wayland.windowManager.hyprland.settings = {
      "$mainMod" = "SUPER";
      "$terminal" = "kitty";
      bindl = [
         "ALT, Shift_L, exec, hyprctl switchxkblayout main next"
         "Shift_L, ALT, exec, hyprctl switchxkblayout main next"
      ];
      bind =
      [
         "$mainMod, F, exec, firefox"
         "$mainMod, E, exec, nautilus"
         "$mainMod, T, exec, flatpak run org.telegram.desktop"
         "$mainMod, RETURN, exec, $terminal"

         "ALT, F4, killactive"

         "$mainMod, 1, workspace, 1"
         "$mainMod, 2, workspace, 2"
         "$mainMod, 3, workspace, 3"
         "$mainMod, 4, workspace, 4"
         "$mainMod, 5, workspace, 5"
         "$mainMod, 6, workspace, 6"
         "$mainMod, 7, workspace, 7"
         "$mainMod, 8, workspace, 8"
         "$mainMod, 9, workspace, 9"
         "$mainMod, 0, workspace, 10"

         # Move to workspace
         "$mainMod SHIFT, 1, movetoworkspace, 1"
         "$mainMod SHIFT, 2, movetoworkspace, 2"
         "$mainMod SHIFT, 3, movetoworkspace, 3"
         "$mainMod SHIFT, 4, movetoworkspace, 4"
         "$mainMod SHIFT, 5, movetoworkspace, 5"
         "$mainMod SHIFT, 6, movetoworkspace, 6"
         "$mainMod SHIFT, 7, movetoworkspace, 7"
         "$mainMod SHIFT, 8, movetoworkspace, 8"
         "$mainMod SHIFT, 9, movetoworkspace, 9"
         "$mainMod SHIFT, 0, movetoworkspace, 10"
     ]; 
  };

}

