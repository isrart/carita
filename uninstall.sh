#!/bin/bash
# Quita Carita y sus hooks. Tu ~/.claude/settings.json conserva todo lo demás.
set -euo pipefail
cd "$(dirname "$0")"
pkill -x Carita 2>/dev/null || true
python3 hooks.py uninstall
rm -rf "$HOME/Applications/Carita.app" "$HOME/.carita"
defaults delete io.github.isrart.carita >/dev/null 2>&1 || true
defaults delete com.bajovelo.carita >/dev/null 2>&1 || true   # identidad antigua (hasta la 1.13)
echo "Carita desinstalada. ¡Adiós! 👋"
