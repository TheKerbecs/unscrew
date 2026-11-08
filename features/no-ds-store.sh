#!/bin/zsh
# name: No .DS_Store on shares and drives
# description: Finder stops writing .DS_Store files on network shares and USB drives. macOS has no switch for internal disks.
# on: launch
# Usage: no-ds-store.sh apply|off
changed=0
for k in DSDontWriteNetworkStores DSDontWriteUSBStores; do
  if [[ $1 == off ]]; then
    defaults read com.apple.desktopservices $k >/dev/null 2>&1 && { defaults delete com.apple.desktopservices $k; changed=1; }
  else
    [[ $(defaults read com.apple.desktopservices $k 2>/dev/null) == 1 ]] || { defaults write com.apple.desktopservices $k -bool true; changed=1; }
  fi
done
(( changed )) && { killall Finder 2>/dev/null; echo ".DS_Store on shares/USB: $([[ $1 == off ]] && echo allowed || echo blocked)"; }
exit 0
