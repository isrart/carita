#!/bin/sh
# Lo llama Claude Code en cada evento. Apunta el estado; la app Carita lo lee.
# Importante: no imprimir nada (en UserPromptSubmit la salida se añadiría al contexto).
# versión: dev
dir="${CARITA_DIR:-$HOME/.carita}"
py=/usr/bin/python3
helper="$dir/carita.py"
mkdir -p "$dir/sesiones" 2>/dev/null

ev="$1"
input=$(cat 2>/dev/null)
state="$ev"

# cada sesión de Claude Code tiene su bicho: el id viene en el JSON
sid=$(printf '%s' "$input" | grep -o '"session_id" *: *"[A-Za-z0-9_-]*"' | head -n 1 | sed 's/.*"\([A-Za-z0-9_-]*\)"$/\1/')

# después de una herramienta: si fue Bash, miramos si era un deploy
if [ "$ev" = "post" ]; then
  state=thinking
  case "$input" in
    *'"tool_name":"Bash"'*|*'"tool_name": "Bash"'*) ev=bashpost ;;
  esac
fi

# la pestaña de la terminal donde corre esta sesión (para escribir en ella o traerla al frente)
tty_of_claude() {
  p=$PPID; i=0
  while [ $i -lt 5 ] && [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
    case "$t" in
      ""|"??") p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') ;;
      *) printf '%s' "$t"; return ;;
    esac
    i=$((i + 1))
  done
}

# sesión sin ficha (p. ej., abierta antes de instalar esta versión): se hace una vez
if [ -n "$sid" ] && [ ! -f "$dir/sesiones/$sid.info" ] && [ -x "$py" ] && [ -f "$helper" ]; then
  printf '%s' "$input" | CARITA_DIR="$dir" CARITA_TTY="$(tty_of_claude)" CARITA_TERM="${__CFBundleIdentifier:-}" \
    "$py" "$helper" info >/dev/null 2>&1
fi

case "$ev" in
  hello|prompt|done|bashpre|bashpost)
    out=""
    if [ -x "$py" ] && [ -f "$helper" ]; then
      ctty=""
      if [ "$ev" = "hello" ] || [ "$ev" = "prompt" ]; then ctty=$(tty_of_claude); fi
      out=$(printf '%s' "$input" | CARITA_DIR="$dir" CARITA_TTY="$ctty" CARITA_TERM="${__CFBundleIdentifier:-}" \
            "$py" "$helper" "$ev" 2>/dev/null)
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

# con sesión, a su archivo (su bicho); sin sesión (pruebas, versiones viejas de Claude Code), al general
if [ -n "$sid" ]; then out_state="$dir/sesiones/$sid.state"; else out_state="$dir/state"; fi
printf '%s' "$state" > "$out_state.$$" 2>/dev/null && mv -f "$out_state.$$" "$out_state" 2>/dev/null
exit 0
