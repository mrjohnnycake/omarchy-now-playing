#!/usr/bin/env bash

# Media key handler that works with or without an Omarchy media plugin.
# Tries the shell's "media" IPC target first (keeps OSD and smart player
# selection); if no plugin answers, talks to MPRIS players directly over D-Bus.
#
# Usage: media-key.sh playPause|next|previous|sourceSwitch|sourceSwitchPrevious

action="${1:-}"
case "$action" in
  playPause | next | previous | sourceSwitch | sourceSwitchPrevious) ;;
  *)
    echo "Usage: $(basename "$0") playPause|next|previous|sourceSwitch|sourceSwitchPrevious" >&2
    exit 1
    ;;
esac

# --- 1. Omarchy shell plugin ---
if reply=$(omarchy-shell media "$action" 2>/dev/null) && [[ $reply != "unhandled" ]]; then
  exit 0
fi

# --- 2. Direct MPRIS fallback ---
mpris_path=/org/mpris/MediaPlayer2
mpris_player=org.mpris.MediaPlayer2.Player

mapfile -t players < <(busctl --user list --no-legend 2>/dev/null |
  awk '$1 ~ /^org\.mpris\.MediaPlayer2\./ && $1 !~ /playerctld/ {print $1}')
(( ${#players[@]} > 0 )) || exit 0

status_of() {
  busctl --user get-property "$1" "$mpris_path" "$mpris_player" PlaybackStatus 2>/dev/null |
    awk -F'"' '{print $2}'
}

call() {
  busctl --user call "$1" "$mpris_path" "$mpris_player" "$2" >/dev/null 2>&1
}

# Index of the first player in the given state, or -1.
index_with_status() {
  local i
  for i in "${!players[@]}"; do
    [[ $(status_of "${players[$i]}") == "$1" ]] && { echo "$i"; return; }
  done
  echo -1
}

playing=$(index_with_status Playing)

case "$action" in
  playPause | next | previous)
    target=$playing
    (( target >= 0 )) || target=$(index_with_status Paused)
    (( target >= 0 )) || target=0
    case "$action" in
      playPause) method=PlayPause ;;
      next) method=Next ;;
      previous) method=Previous ;;
    esac
    call "${players[$target]}" "$method"
    ;;
  sourceSwitch | sourceSwitchPrevious)
    (( ${#players[@]} > 1 )) || exit 0
    step=1
    [[ $action == sourceSwitchPrevious ]] && step=-1
    current=$playing
    (( current >= 0 )) || current=0
    next_index=$(( (current + step + ${#players[@]}) % ${#players[@]} ))
    (( playing >= 0 )) && call "${players[$playing]}" Pause
    call "${players[$next_index]}" Play
    ;;
esac
