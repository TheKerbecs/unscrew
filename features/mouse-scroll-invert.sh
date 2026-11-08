#!/bin/zsh
# name: Invert mouse scrolling
# description: Mouse wheel scrolls the opposite way of the trackpad. Needs Accessibility permission.
# on: launch, wake
# Usage: mouse-scroll-invert.sh apply|off
helper="${UNSCREW_APP:-/Applications/Unscrew.app}/Contents/MacOS/scroll-invert"

if [[ $1 == off ]]; then
  pkill -f "$helper"
  echo "scroll-invert stopped"
  exit 0
fi

# Already running: nothing to do (apply is re-run on launch/wake).
pgrep -f "$helper" >/dev/null && exit 0

nohup "$helper" >/dev/null 2>&1 &
disown
sleep 1
if ! pgrep -f "$helper" >/dev/null; then
  echo "scroll-invert failed to start (grant Accessibility to Unscrew in System Settings > Privacy & Security > Accessibility)"
  exit 1
fi
echo "scroll-invert running"
