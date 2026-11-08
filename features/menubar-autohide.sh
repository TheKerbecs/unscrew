#!/bin/zsh
# name: Menu bar auto-hide
# description: Hide the menu bar while an external display is connected, always show it otherwise. Stretches windows into the freed space.
# on: launch, displays, wake
# Usage: menubar-autohide.sh apply|off

# Moves window top edges, bottom edges stay put. Modes:
#   hide     after hiding: windows sitting below where the bar was grow up to the top
#   preshow  before showing: windows at the top shrink down by the bar height, so macOS
#            does not push them down whole (which would add height every cycle)
#   show     after showing: anything still under the bar shrinks down out from under it
fit_windows() {
  MODE=$1 osascript -l JavaScript <<'EOF'
ObjC.import('AppKit'); ObjC.import('CoreGraphics')
const mode = $.NSProcessInfo.processInfo.environment.objectForKey('MODE').js
// Real menu bar heights come from the window server's "Menubar" windows (present even
// while hidden). NSStatusBar thickness and visibleFrame are wrong for a second screen.
const bars = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0)))
  .filter(w => w.kCGWindowOwnerName === 'Window Server' && w.kCGWindowName === 'Menubar').map(w => w.kCGWindowBounds)
const mainH = $.NSScreen.screens.js[0].frame.size.height
// Screens in top-left global coordinates, like System Events uses.
const screens = $.NSScreen.screens.js.map(s => {
  const f = s.frame, top = mainH - (f.origin.y + f.size.height)
  const left = f.origin.x, right = left + f.size.width
  const notch = s.safeAreaInsets.top                      // stays reserved even when hidden
  const bar = Math.max(notch, ...bars.filter(b => b.X >= left && b.X < right).map(b => b.Height))
  return { left, right, top, bottom: top + f.size.height, hiddenTop: top + notch, shownTop: top + bar }
})
const SLACK = 10   // a window starting this far below the bar still counts as "at the top"
const moved = []
let failure = '', readable = 0
const se = Application('System Events')
for (const p of se.processes.whose({ backgroundOnly: false })()) {
  let wins = []
  try { wins = p.windows(); readable++ } catch (e) { failure = failure || String(e); continue }
  for (const w of wins) {
    try {
      const [x, y] = w.position(), [width, height] = w.size()
      const cx = x + width / 2
      const s = screens.find(s => cx >= s.left && cx < s.right && y >= s.top - 5 && y < s.bottom)
      if (!s || height < 100) continue
      if (mode === 'hide' && y > s.hiddenTop && y <= s.shownTop + SLACK) {
        const d = y - s.hiddenTop
        w.position = [x, s.hiddenTop]; w.size = [width, height + d]   // move first, then grow
      } else if (mode === 'preshow' && Math.abs(y - s.hiddenTop) <= 2 && s.shownTop > s.hiddenTop) {
        const d = s.shownTop - y
        w.size = [width, height - d]; w.position = [x, s.shownTop]     // shrink first, then move
      } else if (mode === 'show' && y < s.shownTop) {
        const d = s.shownTop - y
        w.size = [width, height - d]; w.position = [x, s.shownTop]     // shrink first, then move
      } else continue
      moved.push(p.name())
    } catch (e) {}
  }
}
// No permission shows up as every window access failing: say so instead of staying silent.
[moved.length ? `fitted ${moved.length} windows (${[...new Set(moved)].join(', ')})` : '',
 failure && !readable ? `could not fit windows: ${failure} (grant Unscrew Accessibility)` : ''].filter(Boolean).join('\n')
EOF
}

set_autohide() {
  [[ $(osascript -e 'tell application "System Events" to tell dock preferences to get autohide menu bar') == $1 ]] && return
  [[ $1 == false ]] && fit_windows preshow
  osascript -e "tell application \"System Events\" to tell dock preferences to set autohide menu bar to $1"
  echo "autohide menu bar -> $1"
  sleep 1.5   # let macOS settle the new layout first
  [[ $1 == true ]] && fit_windows hide || fit_windows show
}

if [[ $1 == off ]]; then set_autohide false; exit; fi
# Clamshell-safe: any display that is not the internal panel counts as external.
info=$(system_profiler SPDisplaysDataType)
(( $(grep -c "Resolution:" <<<"$info") > $(grep -c "Connection Type: Internal" <<<"$info") )) && set_autohide true || set_autohide false
