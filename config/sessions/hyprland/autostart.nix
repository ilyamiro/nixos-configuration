{
   wayland.windowManager.hyprland.settings = {
      "exec-once" = [
	 "swww-daemon"
	 "eww daemon --config ~/.config/eww/bar"
         "swww img ./images/wallpaper2.png"
	 "bash ~/.config/eww/bar/launch_bar.sh"
	 "wl-paste --type text --watch cliphist store" 
	 "wl-paste --type image --watch cliphist store"
	 "rm /tmp/eww* -R"
	 "systemctl --user enable --now easyeffects"
      ];
   };
}
