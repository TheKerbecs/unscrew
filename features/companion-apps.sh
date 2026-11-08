#!/bin/zsh
# name: Companion apps
# description: Starts these apps on launch and wake if they are not running.
# on: launch, wake
# setting: apps | Apps | BetterSnapTool, Raycast
# Usage: companion-apps.sh apply|off
setopt extended_glob
apps=(${(s:,:)${UNSCREW_APPS-BetterSnapTool, Raycast}})

# off: stop relaunching them, leave running apps alone.
[[ $1 == off ]] && exit 0

for app in $apps; do
  app=${${app##[[:space:]]#}%%[[:space:]]#}; [[ -z $app ]] && continue
  pgrep -xq "$app" && continue
  if open -gja "$app" 2>/dev/null; then echo "started $app"; else echo "$app not installed"; fi
done
