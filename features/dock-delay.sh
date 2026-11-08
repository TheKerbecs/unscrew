#!/bin/zsh
# name: Dock show delay
# description: How long the auto-hidden Dock waits before it slides in, and how long the slide takes. Empty = macOS default.
# on: launch
# setting: delay | Delay (seconds) |
# setting: speed | Slide (seconds) |
# Usage: dock-delay.sh apply|off
changed=0
# set_key <key> <value>: empty value (or off) deletes the key, which restores the macOS default.
set_key() {
  local cur=$(defaults read com.apple.dock $1 2>/dev/null)
  if [[ -z $2 ]]; then
    [[ -n $cur ]] && { defaults delete com.apple.dock $1; changed=1; }
  elif [[ -z $cur ]] || (( cur != $2 )); then
    defaults write com.apple.dock $1 -float $2; changed=1
  fi
}
# Reject bad input before touching anything.
for v in "$UNSCREW_DELAY" "$UNSCREW_SPEED"; do
  [[ -z $v || $v == <->(|.<->) || $v == .<-> ]] || { echo "not a number of seconds: $v"; exit 1; }
done
if [[ $1 == off ]]; then set_key autohide-delay ""; set_key autohide-time-modifier ""
else set_key autohide-delay "$UNSCREW_DELAY"; set_key autohide-time-modifier "$UNSCREW_SPEED"; fi
(( changed )) && { killall Dock 2>/dev/null; echo "Dock: delay ${UNSCREW_DELAY:-default}, slide ${UNSCREW_SPEED:-default}$([[ $1 == off ]] && echo ' (reset)')"; }
exit 0
