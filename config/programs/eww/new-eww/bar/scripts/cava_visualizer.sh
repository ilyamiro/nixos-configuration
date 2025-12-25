#!/usr/bin/env bash

# CONFIGURATION
# ----------------------------------
# Window is 700px wide. 
# 40 bars * (12px width + 5px space) = 680px (approx)
bar_count=20
bar_width=20
bar_spacing=10
height=190
width=$((bar_count * (bar_width + bar_spacing)))

# Colors (Catppuccin Mocha)
color_bottom="#89b4fa" # Blue
color_top="#cba6f7"    # Mauve

# Path definitions
cava_config="/tmp/cava_config_svg"
svg_file_0="/dev/shm/cava_0.svg"
svg_file_1="/dev/shm/cava_1.svg"

# --- CLEANUP FUNCTION ---
cleanup() {
    rm -f "$cava_config" "$svg_file_0" "$svg_file_1"
}
trap cleanup EXIT

# Cava Config
echo "
[general]
framerate = 60
bars = $bar_count
[input]
method = pulse
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = $height
" > "$cava_config"

# STATE VARIABLE
# We toggle this between 0 and 1
counter=0

# READ CAVA OUTPUT
cava -p "$cava_config" | sed -u 's/;/ /g' | while read -r line; do
    
    # Toggle file path
    counter=$((1 - counter))
    if [ "$counter" -eq 0 ]; then
        output_svg="$svg_file_0"
    else
        output_svg="$svg_file_1"
    fi

    # Start SVG
    svg_content="<svg width='${width}' height='${height}' xmlns='http://www.w3.org/2000/svg'>"
    
    # Gradient Definition
    svg_content="${svg_content}<defs><linearGradient id='grad' x1='0%' y1='100%' x2='0%' y2='0%'><stop offset='0%' style='stop-color:${color_bottom};stop-opacity:1' /><stop offset='100%' style='stop-color:${color_top};stop-opacity:1' /></linearGradient></defs>"

    x=0
    # Loop through the numbers in the line
    for val in $line; do
        # Sanity check to prevent negative heights if Cava glitches
        if [ "$val" -gt 0 ]; then
            # Calculate Y position (flip coordinate system)
            y=$((height - val))
            # Draw Rectangle (rx=4 for rounded corners)
            svg_content="${svg_content}<rect x='${x}' y='${y}' width='${bar_width}' height='${val}' fill='url(#grad)' rx='4' />"
        fi
        x=$((x + bar_width + bar_spacing))
    done

    svg_content="${svg_content}</svg>"

    # Write to RAM
    echo "$svg_content" > "$output_svg"
    
    # Output the CLEAN path (Eww sees path change _0 -> _1 and updates)
    echo "$output_svg"
done
