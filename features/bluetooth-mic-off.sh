#!/bin/zsh
# name: Bluetooth mic off
# description: Bluetooth headsets keep high quality sound: their mic is never the input, the built-in mic is used instead.
# on: launch, wake
# Usage: bluetooth-mic-off.sh apply|off
helper="$HOME/Applications/Unscrew.app/Contents/MacOS/mic-guard"

if [[ $1 == off ]]; then
  pkill -f "$helper"
  echo "mic-guard stopped"
  exit 0
fi

# Already running: nothing to do (apply is re-run on launch/wake).
pgrep -f "$helper" >/dev/null && exit 0

nohup "$helper" >/dev/null 2>&1 &
disown
sleep 1
if ! pgrep -f "$helper" >/dev/null; then
  echo "mic-guard failed to start ($helper missing?)"
  exit 1
fi
echo "mic-guard running"
