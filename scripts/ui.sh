#!/bin/sh
# Guarded UI driver for verifying app tickets headlessly.
# Every key-sending command first checks that Aeris is the frontmost app and aborts
# otherwise, so keystrokes can never land in Terminal or another app.
#   ui.sh launch [file]   build bundle (debug), open it (optionally with file), wait
#   ui.sh keys "text"     type text into Aeris
#   ui.sh key <k> [mods]  one key/shortcut, e.g. `ui.sh key s command`, `ui.sh key return`
#   ui.sh menu <m> <item> [sub]  click a menu item, e.g. `ui.sh menu File Save`
#   ui.sh button <name>   click a button in the front window's sheet, e.g. `ui.sh button Revert`
#   ui.sh shot <out.png>  screenshot of the Aeris main window
#   ui.sh quit            quit Aeris (pkill fallback)
set -eu
cd "$(dirname "$0")/.."
TOOLS=.build/ui-tools

front() {
  osascript -e 'tell application "System Events" to set frontmost of first process whose name is "AerisEditor" to true' >/dev/null 2>&1 || true
  sleep 0.3
  f=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
  [ "$f" = AerisEditor ] || { echo "ui.sh: frontmost is '$f', not Aeris — refusing to send keys" >&2; exit 3; }
}

quit() { osascript -e 'tell application "Aeris" to quit' >/dev/null 2>&1 || true; sleep 1; pkill -x AerisEditor 2>/dev/null || true; }

case ${1:-} in
  launch)
    quit
    # No state restoration between runs: stale windows would skew what we verify.
    rm -rf "$HOME/Library/Saved Application State/com.aeris.editor.savedState"
    scripts/bundle.sh debug >/dev/null
    # AERIS_LIBRARY_FILE (when set) points the app at an isolated library file.
    if [ -n "${AERIS_LIBRARY_FILE:-}" ]; then
      if [ -n "${2:-}" ]; then open --env "AERIS_LIBRARY_FILE=$AERIS_LIBRARY_FILE" -a "$PWD/build/Aeris Writer.app" "$2"
      else open --env "AERIS_LIBRARY_FILE=$AERIS_LIBRARY_FILE" "build/Aeris Writer.app"; fi
    elif [ -n "${2:-}" ]; then open -a "$PWD/build/Aeris Writer.app" "$2"; else open "build/Aeris Writer.app"; fi
    sleep 3; pgrep -x AerisEditor >/dev/null || { echo "ui.sh: app not running" >&2; exit 1; } ;;
  keys) front; osascript -e "tell application \"System Events\" to keystroke \"$2\"" ;;
  key)
    front
    case $2 in return) k='key code 36' ;; tab) k='key code 48' ;; escape) k='key code 53' ;;
      down) k='key code 125' ;; up) k='key code 126' ;; right) k='key code 124' ;; left) k='key code 123' ;; *) k="keystroke \"$2\"" ;; esac
    [ -n "${3:-}" ] && k="$k using {$3 down}"
    osascript -e "tell application \"System Events\" to $k" ;;
  menu)
    front
    p='process "AerisEditor"'; m="menu bar item \"$2\" of menu bar 1 of $p"
    if [ -n "${4:-}" ]; then i="menu item \"$4\" of menu 1 of menu item \"$3\" of menu 1 of $m"
    else i="menu item \"$3\" of menu 1 of $m"; fi
    osascript -e "tell application \"System Events\" to click $i" >/dev/null ;;
  button)
    front
    osascript -e "tell application \"System Events\" to click button \"$2\" of sheet 1 of window 1 of process \"AerisEditor\"" >/dev/null ;;
  shot)
    mkdir -p "$TOOLS"
    [ -x "$TOOLS/winid" ] || swiftc -O scripts/tools/winid.swift -o "$TOOLS/winid" 2>/dev/null
    wid=$("$TOOLS/winid"); [ -n "$wid" ] || { echo "ui.sh: no Aeris window" >&2; exit 1; }
    screencapture -x -o -l "$wid" "$2"; echo "$2" ;;
  quit) quit ;;
  *) sed -n '2,11p' "$0"; exit 64 ;;
esac
