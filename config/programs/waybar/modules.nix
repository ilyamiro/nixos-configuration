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
  };
}
