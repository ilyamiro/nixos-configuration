{ config, pkgs, ... }:

{
   wayland.windowManager.hyprland.settings = {
      "$mainMod" = "SUPER";
      "$terminal" = "kitty";
      bindm = [
         "$mainMod, mouse:272, movewindow"
	 "$mainMod, mouse:273, resizewindow"
      ];
      binde = [
        "$mainMod&SHIFT_L, left, resizeactive,-50 0"
	"$mainMod&SHIFT_L, right, resizeactive,50 0"
	"$mainMod&SHIFT_L, up, resizeactive,0 -50"
	"$mainMod&SHIFT_L, down, resizeactive,0 50"
      ];
      
      bindl = [
         "SHIFT_L, ALT_L, exec, hyprctl switchxkblayout main next"
         "ALT_L, SHIFT_L, exec, hyprctl switchxkblayout main prev"
	 "$mainMod, SPACE, exec, playerctl play-pause"
	 ", xf86AudioMicMute, exec, ${./scripts/volume.sh} --toggle-mic"
	 ", xf86audiomute, exec, ${./scripts/volume.sh} --toggle"
	 ", XF86MonBrightnessDown, exec, ${./scripts/brightness.sh} --dec"
  	 ", XF86MonBrightnessUp, exec, ${./scripts/brightness.sh} --inc"
	 ", Print, exec, ${./scripts/screenshot.sh}"
      ];
      bindel = [
         ", xf86audiolowervolume, exec, ${./scripts/volume.sh} --dec"
	 ", xf86audioraisevolume, exec, ${./scripts/volume.sh} --inc"
	 "$mainMod, L, exec, hyprlock"	
      ];
      bind =
      [	
	 #"$mainMod, D, exec, bash ~/.config/eww/dashboard/launch_dashboard"
	 "$mainMod&SHIFT_L, R, exec, bash ~/.config/eww/bar/launch_bar.sh"
	 "$mainMod, D, exec, bash ${./scripts/rofi_show.sh} drun"
	 "$mainMod, S, exec, bash ~/.config/eww/dashboard/launch_dashboard.sh"
	 "CTRL, TAB, exec, bash ${./scripts/rofi_show.sh} window"
	 "$mainMod, C, exec, bash ${./scripts/rofi_clipboard.sh}"
	 "$mainMod, M, exec, bash ${./scripts/monitors.sh}"
	 "$mainMod&SHIFT_L, P, exec, ${./scripts/power-profiles.sh}"
	 "$mainMod&SHIFT_L, F, togglefloating,"
	 # "$mainMod, S, exec, bash ${./scripts/toggle_control_center.sh}"
	 "$mainMod&SHIFT_L, S, exec, bash ${./scripts/search_bar.sh}"
         "$mainMod, Q, exec, bash ~/.config/eww/bar/scripts/toggle_music.sh"
	 "$mainMod, B, exec, bash ~/.config/eww/bar/scripts/toggle_bt_popup.sh"
         "$mainMod, F, exec, firefox"
         "$mainMod, E, exec, nautilus"
         "$mainMod, T, exec, Telegram"
	 "$mainMod, O, exec, obsidian"
         "$mainMod, RETURN, exec, $terminal"

         "ALT, F4, killactive"

	 "$mainMod&CTRL, left, movewindow, l"
	 "$mainMod&CTRL, right, movewindow, r"
	 "$mainMod&CTRL, up, movewindow, u"
	 "$mainMod&CTRL, down, movewindow, d"

	 "$mainMod, left, movefocus, l"
	 "$mainMod, right, movefocus, r"
	 "$mainMod, up, movefocus, u"
	 "$mainMod, down, movefocus, d"

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

