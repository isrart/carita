#!/bin/sh
# Lo llama Claude Code en cada evento. Apunta el estado; la app Carita lo lee.
# Importante: no imprimir nada (en UserPromptSubmit la salida se añadiría al contexto).
dir="$HOME/.carita"
py=/usr/bin/python3
helper="$dir/carita.py"
mkdir -p "$dir" 2>/dev/null

ev="$1"
input=$(cat 2>/dev/null)
state="$ev"

# después de una herramienta: si fue Bash, miramos si era un deploy
if [ "$ev" = "post" ]; then
  state=thinking
  case "$input" in
    *'"tool_name":"Bash"'*|*'"tool_name": "Bash"'*) ev=bashpost ;;
  esac
fi

case "$ev" in
  hello|prompt|done|bashpre|bashpost)
    out=""
    if [ -x "$py" ] && [ -f "$helper" ]; then
      out=$(printf '%s' "$input" | "$py" "$helper" "$ev" 2>/dev/null)
    fi
    if [ -n "$out" ]; then
      state="$out"
    else
      case "$ev" in prompt) state=thinking ;; bashpre) state=running ;; bashpost) state=thinking ;; esac
    fi
    ;;
esac

# qué app ejecuta Claude Code (para traerla al frente cuando Carita te llama)
if [ "$ev" = "hello" ] || [ "$ev" = "prompt" ]; then
  [ -n "${__CFBundleIdentifier:-}" ] && printf '%s' "$__CFBundleIdentifier" > "$dir/term" 2>/dev/null
fi

printf '%s' "$state" > "$dir/state.$$" 2>/dev/null && mv -f "$dir/state.$$" "$dir/state" 2>/dev/null
exit 0
