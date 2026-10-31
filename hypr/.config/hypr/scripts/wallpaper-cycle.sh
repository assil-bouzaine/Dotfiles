#!/bin/bash
# Directory containing your wallpapers
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

# Array of valid transitions (per awww docs)
TRANSITIONS=(
    "simple"
    "wipe"
    "wave"
    "grow"
    "center"
    "any"
    "outer"
    "random"
    "left"
    "right"
    "top"
    "bottom"
)

# Start awww-daemon if not running
if ! pgrep -x "awww-daemon" > /dev/null; then
    awww-daemon &
    sleep 0.5
fi

# Get list of images
mapfile -t IMAGES < <(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | shuf | head -n 15)

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "No images found in $WALLPAPER_DIR"
    exit 1
fi

# Cycle through wallpapers indefinitely
while true; do
    for img in "${IMAGES[@]}"; do
        # Pick a random transition
        TRANSITION="${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}"

        # Transition step: lower = smoother (range 1-255, ~20 is a nice middle ground)
        STEP=$((RANDOM % 40 + 10))

        # Random FPS between 30-60
        FPS=$((RANDOM % 31 + 30))

        awww img "$img" \
            --transition-type "$TRANSITION" \
            --transition-step "$STEP" \
            --transition-fps "$FPS" \
            --transition-angle "$((RANDOM % 360))"

        # Wait before switching
        sleep 600 # 10 min: transitions are CPU-rendered on both screens
    done

    # Reshuffle after cycling through all images
    mapfile -t IMAGES < <(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | shuf | head -n 15)
done
