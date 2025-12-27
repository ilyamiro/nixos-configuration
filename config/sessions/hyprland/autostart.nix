{
   wayland.windowManager.hyprland.settings = {
      "exec-once" = [
	 "swww-daemon"
	 "eww daemon --config ~/.config/eww/bar"
	 "bash ~/.config/eww/bar/launch_bar.sh"
	 "swww img ${./images/wallpaper_catpuccin.png}"
	 "wl-paste --type text --watch cliphist store" 
	 "wl-paste --type image --watch cliphist store"
	 "rm /tmp/eww* -R"
	 "systemctl --user enable --now easyeffects"
	 "bash ${./scripts/bluetooth_mgr.sh} --daemon"
      ];
   };
}
