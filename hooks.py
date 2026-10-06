"""Añade o quita los hooks de Carita en ~/.claude/settings.json sin tocar lo demás.

Uso: python3 hooks.py install | uninstall | status

status no toca nada: imprime en JSON cuántos hooks de Carita hay y cuántos debería haber.
"""
import json
import os
import shutil
import sys

SETTINGS = os.path.expanduser("~/.claude/settings.json")
HOOK = os.path.expanduser("~/.carita/hook.sh")
MARK = "/.carita/hook.sh"

# evento -> [(matcher, estado)]
PLAN = {
    "SessionStart": [(None, "hello")],
    "UserPromptSubmit": [(None, "prompt")],
    "PreToolUse": [
        ("Read|Grep|Glob|LS|NotebookRead", "reading"),
        ("Edit|MultiEdit|Write|NotebookEdit", "writing"),
        ("^Bash$", "bashpre"),
        ("BashOutput|KillShell", "running"),
        ("WebSearch|WebFetch", "browsing"),
        ("Task|Agent", "delegating"),
    ],
    "PostToolUse": [("*", "post")],
    "Notification": [(None, "asking")],
    "Stop": [(None, "done")],
    "SessionEnd": [(None, "bye")],
}


def strip_ours(hooks):
    """Quita cualquier hook de Carita que ya hubiera (para reinstalar limpio)."""
    for event in list(hooks.keys()):
        groups = []
        for group in hooks.get(event) or []:
            kept = [h for h in group.get("hooks", []) if MARK not in str(h.get("command", ""))]
            if kept:
                g = dict(group)
                g["hooks"] = kept
                groups.append(g)
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]


def status():
    """Qué hooks de Carita hay en settings.json comparado con PLAN."""
    hooks = {}
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            text = f.read().strip()
        hooks = (json.loads(text) if text else {}).get("hooks") or {}
        ok = True
    except FileNotFoundError:
        ok = True
    except Exception:
        ok = False
    expected = [(event, state) for event, items in PLAN.items() for _, state in items]
    present = []
    for event, groups in hooks.items():
        for group in groups or []:
            for h in group.get("hooks", []):
                cmd = str(h.get("command", ""))
                if MARK in cmd:
                    present.append((event, cmd.rsplit(" ", 1)[-1]))
    missing = [f"{e} {s}" for e, s in expected if (e, s) not in present]
    print(json.dumps({"esperados": len(expected), "instalados": len(present),
                      "faltan": missing, "settings_legible": ok}, ensure_ascii=False))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "install"
    if mode == "status":
        status()
        return
    data = {}
    if os.path.exists(SETTINGS):
        with open(SETTINGS, encoding="utf-8") as f:
            text = f.read().strip()
        data = json.loads(text) if text else {}
        backup = SETTINGS + ".antes-de-carita"
        if not os.path.exists(backup):
            shutil.copy(SETTINGS, backup)
    else:
        os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)

    hooks = data.get("hooks") or {}
    strip_ours(hooks)

    if mode == "install":
        for event, items in PLAN.items():
            for matcher, state in items:
                group = {"hooks": [{"type": "command", "command": f'"{HOOK}" {state}', "timeout": 5}]}
                if matcher:
                    group = {"matcher": matcher, **group}
                hooks.setdefault(event, []).append(group)

    if hooks:
        data["hooks"] = hooks
    else:
        data.pop("hooks", None)

    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(("Hooks instalados en " if mode == "install" else "Hooks quitados de ") + SETTINGS)


if __name__ == "__main__":
    main()
