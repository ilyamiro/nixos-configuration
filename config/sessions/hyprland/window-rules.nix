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
  windowrulev2 = [
    "float, class:^(music_vis)$"
    "move 12 720, class:^(music_vis)$"
    "size 700 350, class:^(music_vis)$"
    
    "noborder, class:^(music_vis)$"
    "noshadow, class:^(music_vis)$"
    "pin, class:^(music_vis)$"
    
    "noinitialfocus, class:^(music_vis)$"

    "immediate, class:^(cs2)$"
    "keepaspectratio, class:^(cs2)$"


  ];
};
}
