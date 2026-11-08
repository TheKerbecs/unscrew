#!/bin/zsh
# name: Finder shows everything
# description: File extensions, hidden files, path bar and status bar always on. Off restores the macOS defaults.
# on: launch
# Usage: finder-show-all.sh apply|off
keys=("NSGlobalDomain AppleShowAllExtensions" "com.apple.finder AppleShowAllFiles" "com.apple.finder ShowPathbar" "com.apple.finder ShowStatusBar")
changed=0
for k in $keys; do
  if [[ $1 == off ]]; then
    defaults read ${=k} >/dev/null 2>&1 && { defaults delete ${=k}; changed=1; }
  else
    [[ $(defaults read ${=k} 2>/dev/null) == 1 ]] || { defaults write ${=k} -bool true; changed=1; }
  fi
done
# Finder only picks the change up after a restart.
(( changed )) && { killall Finder 2>/dev/null; echo "Finder settings ${1}: restarted Finder"; }
exit 0
