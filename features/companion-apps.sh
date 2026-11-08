#!/bin/zsh
# name: Companion apps
# description: Keep helper apps running (BetterSnapTool, Raycast). Edit the list at the top of this script.
# on: launch, wake
# Usage: companion-apps.sh apply|off
apps=(BetterSnapTool Raycast)

# off: stop relaunching them, leave running apps alone.
[[ $1 == off ]] && exit 0

for app in $apps; do
  pgrep -xq "$app" && continue
  if open -gja "$app" 2>/dev/null; then echo "started $app"; else echo "$app not installed"; fi
done
