#!/bin/bash
# Show / hide the top bar (SUPER + SHIFT + SPACE), like Omarchy's
# "Toggle top bar". SIGUSR1 makes waybar hide or show itself; hidden, it
# gives its space back to the windows.
pkill -USR1 -x waybar
