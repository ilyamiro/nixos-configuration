{ config, lib, ... }:

{ 
  programs.waybar.settings.main = {
  "battery" = {
	  interval = 3;
	  align = 0;
	  rotate = 0;
	  bat = "BAT0";
	  adapter = "AC0";
	  full-at = 100;
	  design-capacity = false;
	  states = {
		  good = 85;
		  warning = 30;
		  critical = 15;
	  };
	  format = "{icon} {capacity}%";
	  format-charging = " {capacity}%";
	  format-plugged = " {capacity}%";
	  format-alt-click = "click";
	  format-full = "{icon} Full";
	  format-alt = "{icon} {hour}";
	  format-icons = [
		"󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"
	  ];
	  format-time = "{H}h {M}min";
	  tooltip = true;
	  tooltip-format = "{timeTo} {power}w";
  };
    
  "clock" = {
    interval = 1;
    format = " {:%H:%M:%S}";
    format-alt = " {:%H:%M   %Y, %d %B, %A}";
    tooltip-format = "<tt><small>{calendar}</small></tt>";
    calendar = {
        mode = "year";
        mode-mon-col = 3;
        weeks-pos = "right";
        on-scroll = 1;
        format = {
            months = "<span color='#ffead3'><b>{}</b></span>";
            days = "<span color='#ecc6d9'><b>{}</b></span>";
            weeks = "<span color='#99ffdd'><b>W{}</b></span>";
            weekdays = "<span color='#ffcc66'><b>{}</b></span>";
            today = "<span color='#ff6699'><b><u>{}</u></b></span>";
        };
      };
    };

  "hyprland/workspaces" = {
    active-only = false;
    all-outputs = true;
    format = "{icon}";
    show-special = false;
    on-click = "activate";
    on-scroll-up = "hyprctl dispatch workspace e+1";
    on-scroll-down = "hyprctl dispatch workspace e-1";
    persistent-workspaces = {
        "1" = [];
        "2" = [];
        "3" = [];
        "4" = [];
        "5" = [];
        "6" = [];
    };
    format-icons = {
        "1" = "I";
        "2" = "II";
        "3" = "III";
        "4" = "IV";
        "5" = "V";
        "6" = "VI";
        "7" = "VII";
        "8" = "VIII";
        "9" = "IX";
        "10" = "X";
    };
  };

  "custom/playerctl" = {
    format = "<span>{}</span>";
    return-type = "json";
    max-length = 35;
    exec = "playerctl -a metadata --format '{\"text\": \"{{artist}} ~ {{markup_escape(title)}}\", \"tooltip\": \"{{playerName}} : {{markup_escape(title)}}\", \"alt\": \"{{status}}\", \"class\": \"{{status}}\"}' -F";
    on-click-middle = "playerctl play-pause";
    on-click = "playerctl previous";
    on-click-right = "playerctl next";
    # scroll-step = 5.0;
    # on-scroll-up = "~/.config/hypr/scripts/Volume.sh --inc";
    # on-scroll-down = "~/.config/hypr/scripts/Volume.sh --dec";
    # smooth-scrolling-threshold = 1;
};


  };
}
