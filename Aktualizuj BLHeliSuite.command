#!/bin/zsh
# Dwuklik w Finderze: kompiluje BLHeliSuite ze źródeł (z testami) i podmienia starą
# aplikację – build/BLHeliSuite.app oraz kopię w /Applications, jeśli tam jest.
# Opcje (np. --no-tests, --install, --rollback): ./build_app.sh --help
DIR=${0:A:h}
"$DIR/build_app.sh" "$@"
st=$?
if [[ -t 0 ]]; then
  print ""
  if (( st == 0 )); then
    read -s -k 1 "key?Naciśnij O, aby uruchomić BLHeliSuite, lub inny klawisz, aby zamknąć… "
    print ""
    if [[ $key == [oO] ]]; then
      # zainstalowana kopia (Programy), a jeśli jej nie ma – build/BLHeliSuite.app
      target="$DIR/build/BLHeliSuite.app"
      for d in ${=BLHELISUITE_APPS_DIRS:-/Applications $HOME/Applications}; do
        if [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$d/BLHeliSuite.app/Contents/Info.plist" 2>/dev/null) == org.blheli.BLHeliSuiteMac ]]; then
          target="$d/BLHeliSuite.app"
          break
        fi
      done
      open "$target"
    fi
  else
    read -s -k 1 "?Naciśnij dowolny klawisz, aby zamknąć… "
    print ""
  fi
fi
exit $st
