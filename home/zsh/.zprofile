# Sourced by ly's /etc/ly/setup.sh before start-hyprland runs.

# Hyprland 0.57 puts its main thread on SCHED_RR through rtkit, with
# RLIMIT_RTTIME at 150ms soft / 200ms hard. When that thread sits in one long
# kernel call (HDMI probe, DPMS, memory reclaim), it crosses the hard limit
# and the kernel SIGKILLs the compositor: no core, no log, and start-hyprland
# drops into safe mode. That is what killed it on 10-29, 11-01 and 11-03.
# Upstream: hyprwm/Hyprland discussion #16648, fix in PR #16737 (draft as of
# 2026-11-03). Remove this once a release with that fix ships.
export HYPRLAND_NO_RT=1

export PATH="$HOME/.local/bin:$PATH"
