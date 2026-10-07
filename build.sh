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
swiftc -O -swift-version 5 main.swift Settings.swift Diagnostics.swift Stats.swift Updater.swift -o build/Carita

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Carita "$APP/Contents/MacOS/Carita"
cp Carita.icns "$APP/Contents/Resources/Carita.icns"
{ printf '<!doctype html>\n<html lang="es"><head><meta charset="utf-8">\n'; cat face.html; } > "$APP/Contents/Resources/face.html"
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
  <key>CFBundleIdentifier</key><string>com.bajovelo.carita</string>
  <key>CFBundleExecutable</key><string>Carita</string>
  <key>CFBundleIconFile</key><string>Carita</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
touch "$APP"   # para que el Finder pille el icono nuevo
echo "✅ $APP"
