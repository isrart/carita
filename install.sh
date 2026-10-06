#!/bin/bash
# Compila Carita, la instala en ~/Applications y conecta los hooks de Claude Code.
set -euo pipefail
cd "$(dirname "$0")"

bash build.sh

DEST="$HOME/Applications/Carita.app"
echo "📦 Instalando en ~/Applications…"
pkill -x Carita 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/Carita.app "$DEST"

echo "🪝 Conectando los hooks de Claude Code…"
mkdir -p "$HOME/.carita"
cp hook.sh "$HOME/.carita/hook.sh"
cp carita.py "$HOME/.carita/carita.py"
rm -f "$HOME/.carita/resumen.py"
chmod +x "$HOME/.carita/hook.sh"
python3 hooks.py install

echo "👋 Abriendo Carita…"
open "$DEST"
echo
echo "Listo. Carita está abajo a la derecha. Arrástrala donde quieras; clic derecho para opciones."
echo "Te leerá un resumen de cada respuesta. Para que calle: clic encima. Para desactivarlo: clic derecho."
echo "Las sesiones de Claude Code que ya tengas abiertas no la verán: abre una nueva."
