{ config, lib, ... }:

{
wayland.windowManager.hyprland.settings = {
  layerrule = [
    "noanim, ^(volume_osd)$"
    "noanim, ^(brightness_osd)$"
    "noanim, ^(music_win)$"
    "noanim, hyprpicker"
    "noanim, selection"
  ];
};
}
