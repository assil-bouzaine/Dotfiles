#!/bin/bash
# Status line: folder name + caveman badge, context window (bar,
# percent, tokens used / window size), then 5h / weekly rate limits drawn as
# mini bars with time-to-reset. (Before context was added:
# statusline-command.sh.bak-2026-11-17; old token version: .bak-2026-11-08)
input=$(cat)
# Snapshot for Telegram alerts: agent-notify reads limits + context size from it
# for the usage footer (~/.dotfiles/docs/agent-notify.md). Keep this.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -n "$sid" ]; then
  snap=~/.cache/agent-usage/claude; mkdir -p "$snap"
  printf '%s' "$input" > "$snap/$sid.tmp" && mv "$snap/$sid.tmp" "$snap/$sid.json"
fi

E=$'\033'; R="$E[0m"; DIM="$E[2m"; BOLD="$E[1m"
ACCENT="$E[38;5;173m"   # Claude orange
SEP=" ${DIM}│${R} "

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
name=$(basename "$cwd"); [ "$cwd" = "$HOME" ] && name="~"
printf '%s' "${ACCENT}${BOLD}󰉋 ${name}${R}"
badge=$(printf '%s' "$input" | bash "$HOME/.claude/hooks/caveman-statusline.sh" 2>/dev/null)
[ -n "$badge" ] && printf ' %s' "$badge"

# Color by usage: green <50, yellow <80, red >=80
pct_color() {
  local p=$1
  if   [ "$p" -ge 80 ]; then printf '%s' "$E[38;5;203m"
  elif [ "$p" -ge 50 ]; then printf '%s' "$E[38;5;221m"
  else                       printf '%s' "$E[38;5;114m"
  fi
}

# 8-cell bar: ▰ filled, ▱ empty
bar() {
  local p=$1 n=8 f
  f=$(( (p * n + 50) / 100 )); [ "$f" -gt "$n" ] && f=$n
  local c; c=$(pct_color "$p")
  printf '%s' "$c"; for ((i=0; i<f; i++)); do printf '▰'; done
  printf '%s' "$R$DIM"; for ((i=f; i<n; i++)); do printf '▱'; done
  printf '%s' "$R"
}

# Time until a unix-epoch reset, e.g. "2h13m" or "3d4h"
until_reset() {
  local secs=$(( $1 - $(date +%s) ))
  [ "$secs" -le 0 ] && return
  local d=$((secs/86400)) h=$((secs%86400/3600)) m=$((secs%3600/60))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else                      printf '%dm' "$m"
  fi
}

# One limit segment: label, bar, percent, reset countdown
limit() {
  local label=$1 pct=$2 reset=$3 p t
  [ "$pct" = "-" ] && return
  p=$(printf '%.0f' "$pct")
  printf '%s' "$SEP${DIM}${label}${R} $(bar "$p") $(pct_color "$p")${p}%${R}"
  if [ "$reset" != "-" ] && t=$(until_reset "${reset%.*}") && [ -n "$t" ]; then
    printf ' %s' "${DIM}󰑐 ${t}${R}"
  fi
}

# Human-readable token count: 1234 -> 1.2k, 332237 -> 332k, 1000000 -> 1M
fmt_tokens() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then
    if [ $((n % 1000000)) -eq 0 ]; then printf '%dM' $((n / 1000000))
    else printf '%d.%dM' $((n / 1000000)) $((n % 1000000 / 100000)); fi
  elif [ "$n" -ge 100000 ]; then printf '%dk' $((n / 1000))
  elif [ "$n" -ge 1000 ];   then printf '%d.%dk' $((n / 1000)) $((n % 1000 / 100))
  else                           printf '%d' "$n"
  fi
}

# Context window: what is in the window now (last request's input,
# cache reads and writes included) against its size.
read -r model ctxp ctxsize ctxused < <(printf '%s' "$input" | jq -r '
  [ (.model.display_name // "" | gsub(" "; " ")),
    (.context_window.used_percentage // "-"),
    (.context_window.context_window_size // 0),
    ((.context_window.current_usage // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
  ] | map(tostring) | @tsv')
if [ "$ctxp" != "-" ]; then
  p=$(printf '%.0f' "$ctxp")
  printf '%s' "$SEP${DIM}ctx${R} $(bar "$p") $(pct_color "$p")${p}%${R}"
  [ "${ctxsize:-0}" -gt 0 ] && printf ' %s' "${DIM}$(fmt_tokens "$ctxused")/$(fmt_tokens "$ctxsize")${R}"
fi

# Rate limits (Pro/Max only, present after the first response)
read -r p5 r5 p7 r7 < <(printf '%s' "$input" | jq -r '[.rate_limits.five_hour.used_percentage // "", .rate_limits.five_hour.resets_at // "", .rate_limits.seven_day.used_percentage // "", .rate_limits.seven_day.resets_at // ""] | map(tostring | if . == "" then "-" else . end) | @tsv')
limit "5h" "$p5" "$r5"
limit "wk" "$p7" "$r7"
printf '\n'
