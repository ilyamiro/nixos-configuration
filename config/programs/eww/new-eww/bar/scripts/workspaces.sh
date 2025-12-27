#!/bin/bash

# Configuration: How many workspaces do you want to show?
SEQ_END=8

print_workspaces() {
    # Get raw data
    spaces=$(hyprctl workspaces -j)
    active=$(hyprctl activeworkspace -j | jq '.id')

    # Generate the JSON
    echo "$spaces" | jq --argjson a "$active" --arg end "$SEQ_END" -c '
        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        # Iterate from 1 to SEQ_END
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            # Determine state: active -> occupied -> empty
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )
    '
}

# Print initial state
print_workspaces

# Listen to Hyprland socket
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
    case "$line" in
        workspace*|createwindow*|closewindow*|movewindow*)
            print_workspaces
            ;;
    esac
done
