#!/bin/zsh
# BLHeliSuite dla macOS – buduje aplikację ze źródeł i podmienia starą wersję.
#
#   ./build_app.sh               kompilacja (release) + testy + nowa build/BLHeliSuite.app
#   ./build_app.sh --no-tests    bez testów (szybciej)
#   ./build_app.sh --install     dodatkowo zainstaluj w /Applications
#   ./build_app.sh --open        uruchom aplikację po zbudowaniu
#   ./build_app.sh --rollback    wróć do poprzedniej wersji (ponownie: z powrotem do nowszej)
#
# Stara aplikacja jest podmieniana dopiero wtedy, gdy kompilacja i testy się udadzą.
# Poprzednia wersja zostaje w build/.previous/. Kopie w /Applications i ~/Applications
# są aktualizowane automatycznie. Folder oryginalnego BLHeliSuite (Windows) można podać
# w zmiennej BLHELISUITE_WINDOWS (domyślnie ../BLHeliSuite).
#
# Pełne logi: build/build.log (kompilacja), build/selftest.log (testy).
set -e
setopt pipefail

RUN_TESTS=1 INSTALL=0 OPEN=0 ROLLBACK=0
for arg in "$@"; do
  case $arg in
    --no-tests) RUN_TESTS=0 ;;
    --install)  INSTALL=1 ;;
    --open)     OPEN=1 ;;
    --rollback) ROLLBACK=1 ;;
    -h|--help)  sed -n '2,13p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) print -u2 "Nieznana opcja: $arg (pomoc: $0 --help)"; exit 2 ;;
  esac
done

cd "${0:A:h}"
ROOT=$PWD
ORIG=${BLHELISUITE_WINDOWS:-$ROOT/../BLHeliSuite}
OUT=$ROOT/build
APP=$OUT/BLHeliSuite.app
PREV=$OUT/.previous/BLHeliSuite.app
STAGE=$OUT/.staging
BUNDLE_ID=org.blheli.BLHeliSuiteMac
SHORT_VERSION=16.7.14.9.0.2
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
INSTALL_DIRS=(${=BLHELISUITE_APPS_DIRS:-/Applications $HOME/Applications})
SWAPPED=0

step() { print "\n==> $1" }

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true }

version_of() { print "$(plist_value "$1" CFBundleShortVersionString) (build $(plist_value "$1" CFBundleVersion))" }

register() { if [[ -x $LSREGISTER ]]; then "$LSREGISTER" -f "$1" || true; fi }

finish() {
  local st=$1
  rm -rf "$STAGE"
  if (( st != 0 )); then
    if (( SWAPPED )); then
      print -u2 "\n✗ Błąd (kod $st) po podmianie – nowa aplikacja jest już w $APP."
    else
      print -u2 "\n✗ Nie udało się (kod $st). Stara aplikacja nie została zmieniona."
    fi
  fi
}
trap 'finish $?' EXIT

installed_copies() {
  local d
  for d in $INSTALL_DIRS; do
    if [[ $(plist_value "$d/BLHeliSuite.app" CFBundleIdentifier) == $BUNDLE_ID ]]; then print -r -- "$d/BLHeliSuite.app"; fi
  done
}

# Kopie zainstalowane poza build/ – tylko ta aplikacja (sprawdzany identyfikator pakietu).
update_installed() {
  local d t tmp old
  local -a targets
  for d in $INSTALL_DIRS; do
    t=$d/BLHeliSuite.app
    [[ -d $t ]] || continue
    if [[ $(plist_value "$t" CFBundleIdentifier) == $BUNDLE_ID ]]; then
      targets+=("$t")
    else
      print "Pomijam $t – to inna aplikacja."
    fi
  done
  if (( INSTALL )) && [[ ! -e $INSTALL_DIRS[1]/BLHeliSuite.app ]]; then
    targets+=("$INSTALL_DIRS[1]/BLHeliSuite.app")
  fi
  for t in $targets; do
    tmp=${t:h}/.BLHeliSuite.app.new
    old=${t:h}/.BLHeliSuite.app.old
    rm -rf "$tmp" "$old"
    if ditto "$APP" "$tmp" && { [[ ! -e $t ]] || mv "$t" "$old" } && mv "$tmp" "$t"; then
      rm -rf "$old"
      register "$t"
      print "Zaktualizowano: $t"
    else
      rm -rf "$tmp"
      [[ -e $t || ! -e $old ]] || mv "$old" "$t"
      print -u2 "Nie udało się zaktualizować $t (brak uprawnień?)."
    fi
  done
}

running_note() {
  if pgrep -f "BLHeliSuite.app/Contents/MacOS/BLHeliSuite" >/dev/null 2>&1; then
    print "\nUwaga: BLHeliSuite jest uruchomiony – zamknij go i otwórz ponownie, aby używać tej wersji."
  fi
}

if (( ROLLBACK )); then
  [[ -d $PREV ]] || { print -u2 "Brak poprzedniej wersji ($PREV)."; exit 1 }
  [[ ! -e $OUT/.rollback ]] || { print -u2 "Pozostałość przerwanego --rollback: $OUT/.rollback – sprawdź ją ręcznie."; exit 1 }
  if [[ -d $APP ]]; then mv "$APP" "$OUT/.rollback"; fi
  mv "$PREV" "$APP"
  if [[ -d $OUT/.rollback ]]; then mv "$OUT/.rollback" "$PREV"; fi
  SWAPPED=1
  register "$APP"
  update_installed
  print "\n✓ Przywrócono: $APP – $(version_of "$APP")"
  if [[ -d $PREV ]]; then print "  Ponowne --rollback wraca do $(version_of "$PREV")."; fi
  running_note
  exit 0
fi

if ! xcrun --find swift >/dev/null 2>&1; then
  print -u2 "Brak kompilatora Swift. Zainstaluj narzędzia Apple poleceniem: xcode-select --install"
  exit 1
fi

step "Baza firmware"
if [[ -f Resources/FirmwareDB.bin ]]; then
  print "Resources/FirmwareDB.bin – OK"
else
  [[ -d $ORIG ]] || { print -u2 "Brak Resources/FirmwareDB.bin i folderu $ORIG (zmienna BLHELISUITE_WINDOWS)."; exit 1 }
  python3 -I Tools/build_firmware_db.py "$ORIG" Resources/FirmwareDB.bin
fi

step "Kompilacja (release)"
mkdir -p "$OUT"
print "Trwa kompilacja… (pierwsza może potrwać kilka minut)"
if swift build -c release > "$OUT/build.log" 2>&1; then
  WARNINGS=$(grep -c "warning:" "$OUT/build.log" || true)
  print "$(grep -E "^Build complete" "$OUT/build.log" | tail -n 1)  ostrzeżenia: $WARNINGS (build/build.log)"
else
  grep -E "error:" -A 3 "$OUT/build.log" | head -n 60 >&2 || tail -n 30 "$OUT/build.log" >&2
  print -u2 "Kompilacja nie powiodła się – pełny wynik: build/build.log"
  exit 1
fi
BIN=$(swift build -c release --show-bin-path)

if (( RUN_TESTS )); then
  step "Testy"
  if BLHELI_FIRMWARE_DB=$ROOT/Resources/FirmwareDB.bin "$BIN/blheli-selftest" > "$OUT/selftest.log" 2>&1; then
    tail -n 1 "$OUT/selftest.log"
  else
    grep "✗" "$OUT/selftest.log" | head -n 20 >&2 || true
    tail -n 1 "$OUT/selftest.log" >&2
    print -u2 "Testy nie przeszły – pełny wynik: build/selftest.log"
    exit 1
  fi
fi

step "Pakiet aplikacji"
rm -rf "$STAGE"
NEW=$STAGE/BLHeliSuite.app
mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources"
cp "$BIN/BLHeliSuite" "$BIN/blheli-cli" "$NEW/Contents/MacOS/"
cp Resources/FirmwareDB.bin "$NEW/Contents/Resources/"
MANUALS=("$ORIG"/Manuals/*.(pdf|xls)(N))
if (( ${#MANUALS} )); then
  mkdir -p "$NEW/Contents/Resources/Manuals"
  cp "${MANUALS[@]}" "$NEW/Contents/Resources/Manuals/"
fi
if [[ -d $ORIG/Interfaces ]]; then
  (cd "$ORIG/Interfaces" && find . -iname '*.hex' -print0 | while IFS= read -r -d '' f; do
     mkdir -p "$NEW/Contents/Resources/Interfaces/${f:h}"
     cp "$f" "$NEW/Contents/Resources/Interfaces/$f"
   done)
else
  print "Uwaga: brak $ORIG/Interfaces – zakładka Make Interfaces nie będzie miała plików Arduino."
fi

ICON=$ROOT/.build/AppIcon.icns
if [[ ! -f $ICON || Tools/make_icon.swift -nt $ICON ]]; then
  ICONTMP=$(mktemp -d)
  swiftc -O -o "$ICONTMP/make_icon" Tools/make_icon.swift
  "$ICONTMP/make_icon" "$ICONTMP/icon.png"
  mkdir -p "$ICONTMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONTMP/icon.png" --out "$ICONTMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ICONTMP/icon.png" --out "$ICONTMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns -o "$ICON" "$ICONTMP/AppIcon.iconset"
  rm -rf "$ICONTMP"
fi
cp "$ICON" "$NEW/Contents/Resources/AppIcon.icns"

BUILD=$(date +%Y%m%d.%H%M%S)
cat > "$NEW/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>BLHeliSuite</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>BLHeliSuite</string>
  <key>CFBundleDisplayName</key><string>BLHeliSuite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>BLHeliSuite (c) 4712 – macOS port</string>
</dict>
</plist>
EOF

SIGN_OUT=$(codesign --force --deep --sign - "$NEW" 2>&1) || { print -u2 "$SIGN_OUT"; exit 1 }
codesign --verify --deep --strict "$NEW"
print "Podpis (ad-hoc) – OK"

step "Podmiana aplikacji"
mkdir -p "${PREV:h}"
if [[ -d $APP ]]; then
  rm -rf "$PREV"
  mv "$APP" "$PREV"
fi
mv "$NEW" "$APP"
SWAPPED=1
register "$APP"
print "Zaktualizowano: $APP"
update_installed

print "\n✓ Gotowe w $((SECONDS / 60)) min $((SECONDS % 60)) s – $(version_of "$APP")"
if [[ -d $PREV ]]; then
  print "  Poprzednia wersja $(version_of "$PREV") jest w build/.previous (powrót: ./build_app.sh --rollback)."
fi
running_note

if (( OPEN )); then
  TARGETS=("${(@f)$(installed_copies)}")
  open "${TARGETS[1]:-$APP}"
fi
