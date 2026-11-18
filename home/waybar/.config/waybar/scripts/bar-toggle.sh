#!/bin/bash
# Show / hide the top bar (SUPER + SHIFT + SPACE), like Omarchy's
# "Toggle top bar". SIGUSR1 makes waybar hide or show itself; hidden, it
# gives its space back to the windows.
"${0%/*}/bar-signal" USR1   # not a bare pkill: see bar-signal
