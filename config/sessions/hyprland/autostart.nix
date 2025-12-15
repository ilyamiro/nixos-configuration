{
   wayland.windowManager.hyprland.settings = {
      "exec-once" = [
	 "swww-daemon"
         "swww img ./images/wallpaper_catpuccin.png"
	 "bash ~/.config/eww/bar/launch_bar.sh"
	 "wl-paste --type text --watch cliphist store" 
	 "wl-paste --type image --watch cliphist store"
      ];
   };
}
