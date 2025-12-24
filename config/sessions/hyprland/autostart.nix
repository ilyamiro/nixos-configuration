{
   wayland.windowManager.hyprland.settings = {
      "exec-once" = [
	 "swww-daemon"
	 "eww daemon --config ~/.config/eww/bar"
	 "bash ~/.config/eww/bar/launch_bar.sh"
	 "swww img ${./images/wallpaper4.jpg}"
	 "wl-paste --type text --watch cliphist store" 
	 "wl-paste --type image --watch cliphist store"
	 "rm /tmp/eww* -R"
	 "systemctl --user enable --now easyeffects"
      ];
   };
}
