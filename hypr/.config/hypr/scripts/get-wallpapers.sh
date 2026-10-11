#!/bin/bash
# Downloads the wallpaper set (from wallhaven.cc) into ~/Pictures/Wallpapers,
# where wallpaper-cycle.sh and hyprlock.conf look for them.
# Safe to re-run: files that are already there are skipped.

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

# wallhaven id + extension (the full-size URL needs both)
WALLPAPERS=(
    2e6wgx.jpg   # snowy log cabin, lit window (also the lock screen)
    gwmo13.jpg   # lakeside cabin in snow at dusk
    9mq26d.jpg   # illustrated misty mountain lake
    4dp2g4.jpg   # foggy blue mountains
    rrpp6m.png   # misty forest lake
    g8p1od.jpg   # snowy cabin at night in fog
    m3vzdy.png   # snowy cabin with a warm window
    vpywv3.jpg   # dark forest cabin
    jxgmjy.jpg   # deep teal lake at night
    jxqw8w.png   # red cabin by a green lake
)

mkdir -p "$WALLPAPER_DIR"
for file in "${WALLPAPERS[@]}"; do
    id=${file%.*}
    dest="$WALLPAPER_DIR/wallhaven-$file"
    if [[ -f $dest ]]; then
        echo "have  wallhaven-$file"
        continue
    fi
    if curl -fsSL -o "$dest" "https://w.wallhaven.cc/full/${id:0:2}/wallhaven-$file"; then
        echo "got   wallhaven-$file"
    else
        rm -f "$dest"
        echo "FAILED wallhaven-$file" >&2
    fi
done
