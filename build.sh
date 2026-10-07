#!/bin/bash
# Compila Carita y monta build/Carita.app (no instala nada).
# Lo usan install.sh y la build de GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Falta el compilador de Swift. Instala las Command Line Tools con:"
  echo "  xcode-select --install"
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Carita.app"

echo "🔨 Compilando Carita $VERSION ($BUILD_NUMBER)…"
mkdir -p build
swiftc -O -swift-version 5 main.swift Creature.swift Sofa.swift Voice.swift Settings.swift Diagnostics.swift Stats.swift Updater.swift -o build/Carita

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Carita "$APP/Contents/MacOS/Carita"
cp Carita.icns "$APP/Contents/Resources/Carita.icns"
{ printf '<!doctype html>\n<html lang="es"><head><meta charset="utf-8">\n'; cat face.html; } > "$APP/Contents/Resources/face.html"
# textos de permisos de macOS en español e inglés (el resto de la app los traduce ella: T(es, en))
mkdir -p "$APP/Contents/Resources/es.lproj" "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/es.lproj/InfoPlist.strings" <<'STR'
"NSMicrophoneUsageDescription" = "Para oírte cuando mantienes el atajo de hablar.";
"NSSpeechRecognitionUsageDescription" = "Para entender lo que le dices (en tu Mac, sin internet) y escribirlo en la terminal.";
"NSAppleEventsUsageDescription" = "Para traer al frente la pestaña de Terminal de cada sesión de Claude Code.";
STR
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'STR'
"NSMicrophoneUsageDescription" = "To hear you while you hold the talk shortcut.";
"NSSpeechRecognitionUsageDescription" = "To understand what you say (on your Mac, offline) and type it into the terminal.";
"NSAppleEventsUsageDescription" = "To bring each Claude Code session's Terminal tab to the front.";
STR
# los scripts de los hooks viajan dentro de la app (para poder reinstalarlos desde ella)
# con la versión estampada, para que la app sepa si los de ~/.carita están al día
sed "s/^# versión: dev$/# versión: $VERSION/" hook.sh > "$APP/Contents/Resources/hook.sh"
sed "s/^VERSION = \"dev\"/VERSION = \"$VERSION\"/" carita.py > "$APP/Contents/Resources/carita.py"
chmod +x "$APP/Contents/Resources/hook.sh"
cp hooks.py "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Carita</string>
  <key>CFBundleDisplayName</key><string>Carita</string>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleLocalizations</key><array><string>es</string><string>en</string></array>
  <key>CFBundleIdentifier</key><string>io.github.isrart.carita</string>
  <key>CFBundleExecutable</key><string>Carita</string>
  <key>CFBundleIconFile</key><string>Carita</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Para oírte cuando mantienes el atajo de hablar.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Para entender lo que le dices (en tu Mac, sin internet) y escribirlo en la terminal.</string>
  <key>NSAppleEventsUsageDescription</key><string>Para traer al frente la pestaña de Terminal de cada sesión de Claude Code.</string>
</dict>
</plist>
PLIST
# Firma: con el certificado propio si está (así macOS no olvida los permisos de micrófono y
# accesibilidad al actualizar); si no, ad hoc. En GitHub Actions el llavero lo crea el workflow.
KC="${CARITA_KEYCHAIN:-$HOME/Library/Keychains/carita-firma.keychain-db}"
KCPASS_FILE="${CARITA_KEYCHAIN_PASS_FILE:-$HOME/.config/carita/keychain.pass}"
IDENTITY="Carita (firma propia)"
if [ -f "$KC" ] && [ -f "$KCPASS_FILE" ] && security unlock-keychain -p "$(cat "$KCPASS_FILE")" "$KC" 2>/dev/null \
   && codesign --force --deep --keychain "$KC" -s "$IDENTITY" "$APP" 2>/dev/null; then
  echo "🔏 Firmada con «${IDENTITY}»"
else
  codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
  echo "🔏 Firma ad hoc (no está el certificado propio)"
fi
touch "$APP"   # para que el Finder pille el icono nuevo
echo "✅ $APP"
