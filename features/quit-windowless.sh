#!/bin/zsh
# name: Quit apps without windows
# description: Quits apps that have had no open window for a while. Never quits the app in front or the ones you keep.
# interval: 30
# setting: minutes | Quit after (minutes) | 3
# setting: keep | Keep running | Finder, Tailscale, Music, Spotify, Mail, Messages, Discord, Calendar
# Usage: quit-windowless.sh apply|off
state=~/Library/Caches/Unscrew/windowless.json
[[ $1 == off ]] && { rm -f $state; exit 0; }
[[ ${UNSCREW_MINUTES:-3} == <->(|.<->) ]] || { echo "not a number of minutes: $UNSCREW_MINUTES"; exit 1; }
mkdir -p ${state:h}

STATE=$(cat $state 2>/dev/null || echo '{}') MINUTES=${UNSCREW_MINUTES:-3} KEEP=${UNSCREW_KEEP-"Finder, Tailscale, Music, Spotify, Mail, Messages, Discord, Calendar"} \
osascript -l JavaScript <<'JS' > $state.out
ObjC.import('AppKit')
const env = $.NSProcessInfo.processInfo.environment
const get = k => env.objectForKey(k).js
const since = JSON.parse(get('STATE'))           // bundle id -> ms when first seen without windows
const limit = parseFloat(get('MINUTES')) * 60000
const keep = get('KEEP').split(',').map(s => s.trim().toLowerCase()).filter(Boolean)
const now = Date.now(), next = {}, log = []
const front = $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier
const se = Application('System Events')
let blind = false
for (const app of $.NSWorkspace.sharedWorkspace.runningApplications.js) {
  if (app.activationPolicy != 0 || app.terminated) continue          // only regular Dock apps
  const id = app.bundleIdentifier.js, name = app.localizedName.js
  if (!id || app.processIdentifier == front) continue
  if (keep.includes(name.toLowerCase()) || keep.includes(id.toLowerCase())) continue
  // Accessibility also sees minimized windows and windows on other Spaces.
  let count
  try { count = se.processes.whose({ unixId: app.processIdentifier })()[0].windows().length }
  catch (e) { blind = true; continue }                                 // unknown: never quit
  if (count > 0) continue
  next[id] = since[id] || now
  if (now - next[id] >= limit) { app.terminate; log.push(`quit ${name}`); delete next[id] }
}
if (blind) log.push('could not read some windows (grant Unscrew Accessibility)')
JSON.stringify({ state: next, log })
JS
python3 -c '
import json, sys
r = json.load(open(sys.argv[1] + ".out"))
json.dump(r["state"], open(sys.argv[1], "w"))
print("\n".join(r["log"]))' $state
rm -f $state.out
