"""Ayudante de los hooks de Carita. Lo llama hook.sh con el evento y el JSON del hook por stdin.

  hello / prompt -> mira en qué proyecto estás y elige disfraz (~/.carita/costume)
  done           -> resume tu última respuesta para leerla en voz alta (~/.carita/say)
  bashpre        -> ¿es un deploy? ("deploying") si no, "running"
  bashpost       -> ¿el deploy salió bien? ("shipped") si no, "thinking"

En prompt, done y deploys apunta además una línea en ~/.carita/historial.jsonl
(para las estadísticas de la app; nada sale del Mac).

Imprime solo el estado final (hook.sh lo recoge); nunca falla.
"""
import json
import os
import re
import sys
import time

VERSION = "dev"   # build.sh pone aquí la versión de la app
DIR = os.environ.get("CARITA_DIR") or os.path.expanduser("~/.carita")
SESSIONS = os.path.join(DIR, "sesiones")
MAX_VOICE = 260   # caracteres que dice en voz alta (unas 2-3 frases)
MAX_BUBBLE = 90   # caracteres en el bocadillo


def last_answer(path):
    """Último bloque de texto de Claude en el turno actual."""
    texts = []
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("isSidechain"):
                continue
            kind = e.get("type")
            msg = e.get("message") or {}
            content = msg.get("content")
            if kind == "user":
                is_prompt = isinstance(content, str) or (
                    isinstance(content, list)
                    and any(isinstance(b, dict) and b.get("type") == "text" for b in content)
                )
                if is_prompt and not e.get("isMeta"):
                    texts = []  # empieza un turno nuevo
            elif kind == "assistant" and isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                        texts.append(b["text"])
    return texts[-1] if texts else ""


def clean_inline(s):
    def code(m):
        c = m.group(1).strip()
        if "/" in c:
            c = c.rstrip("/").split("/")[-1]  # una ruta se queda en su último trozo
        return "" if len(c) > 30 else c
    s = re.sub(r"`([^`]*)`", code, s)
    s = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"https?://\S+", "", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = re.sub(r"(\*\*|__|\*|~~)", "", s)
    s = re.sub(r"[\U0001F000-\U0001FAFF☀-➿️‍]", "", s)
    s = re.sub(r"\s+([,.;:!?])", r"\1", s)
    return re.sub(r"\s{2,}", " ", s).strip()


def summarize(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    chunks, total = [], 0
    for para in re.split(r"\n\s*\n", text):
        lines = [l.strip() for l in para.splitlines() if l.strip()]
        lines = [l for l in lines if not l.startswith("|") and not re.fullmatch(r"[-=*_ ]{3,}", l)]
        if not lines or all(re.match(r"#{1,6}\s", l) for l in lines):
            continue  # tablas, separadores y títulos sueltos no se leen
        parts = []
        for l in lines:
            l = re.sub(r"^#{1,6}\s+", "", l)
            l = re.sub(r"^([-*+•]|\d+[.)])\s+", "", l)
            l = re.sub(r"^>\s?", "", l)
            l = clean_inline(l)
            if not l:
                continue
            if l[-1] not in ".!?…:":
                l += "."
            parts.append(l)
        if not parts:
            continue
        chunk = " ".join(parts)
        chunks.append(chunk)
        total += len(chunk)
        if total >= MAX_VOICE:
            break

    sentences = re.split(r"(?<=[.!?…:])\s+", " ".join(chunks))
    voice = ""
    for s in sentences:
        if not s:
            continue
        if voice and len(voice) + len(s) + 1 > MAX_VOICE:
            break
        voice = (voice + " " + s).strip()
    voice = shorten(voice, MAX_VOICE + 40)
    if voice.endswith(":"):
        voice = voice[:-1] + "."
    first = sentences[0] if sentences and sentences[0] else voice
    bubble = shorten(first.rstrip(":") , MAX_BUBBLE)
    return voice, bubble


def shorten(s, limit):
    if len(s) <= limit:
        return s
    cut = s[:limit].rsplit(" ", 1)[0].rstrip(",;:")
    return cut + "…"


DEPLOY = re.compile(
    r"\bgit\s+push\b|\bdeploy\b|\bvercel\b[^|;&]*--prod|\bsupabase\s+db\s+push\b|\bwrangler\s+publish\b"
)
FAILED = ("error:", "fatal:", "[rejected]", "failed", "permission denied", "could not",
          "everything up-to-date", "command not found")


def is_deploy(command):
    return bool(command) and "--dry-run" not in command and bool(DEPLOY.search(command))


def deploy_ok(response):
    if isinstance(response, dict):
        if response.get("interrupted") or response.get("is_error"):
            return False
        text = " ".join(str(response.get(k, "")) for k in ("stdout", "stderr", "output", "error"))
    else:
        text = str(response or "")
    text = text.lower()
    return not any(m in text for m in FAILED)


def project_root(cwd):
    d = os.path.abspath(cwd)
    for _ in range(8):
        if os.path.isfile(os.path.join(d, ".carita")) or any(
                os.path.exists(os.path.join(d, f)) for f in ("package.json", ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.path.abspath(cwd)


# Disfraces por tipo de proyecto (todo es Bajovelo): boina siempre, y en la mano
# algo distinto según el subproyecto. Palabras clave en la ruta de la carpeta, en orden:
# la primera regla que encaja gana. Se pueden cambiar en Ajustes (~/.carita/config.json).
RULES = [
    ("vinotrivia", ("trivia", "quiz", "preguntas", "denominacion")),
    ("vinoreels", ("reel", "insta", "video", "redes", "social")),
    ("vinorecursos", ("recurso", "resource", "guia", "ficha", "descarga")),
    ("vinoblog", ("blog", "articulo")),
    ("vino", ("bajovelo", "vino", "wine", "sommelier")),
]


# La forma del bicho (variaciones de Carita, todas naranjas), igual que los disfraces: la primera que encaja.
SHAPES = ("redondita", "alubia", "gotita", "mandarina", "pelusita")
SHAPE_RULES = [
    ("pelusita", ("claude", "agent", "mcp", "skill", "prompt")),
    ("mandarina", ("blog", "reel", "insta", "video", "redes", "social", "articulo")),
    ("alubia", ("app", "api", "swift", "ios", "web", "carita", "code", "dev", "backend", "frontend")),
    ("gotita", ("notas", "apuntes", "scratch", "prueba", "test", "tmp", "sandbox")),
    ("redondita", ("bajovelo", "vino")),
]


def rules_from_config(key, field, default):
    try:
        with open(os.path.join(DIR, "config.json"), encoding="utf-8") as f:
            rules = json.load(f).get(key)
        if not isinstance(rules, list):
            return default
        return [(str(r[field]), tuple(str(w).lower() for w in r["palabras"] if str(w).strip())) for r in rules]
    except Exception:
        return default


def pick_shape(cwd):
    root = project_root(cwd)
    override = os.path.join(root, ".carita")
    if os.path.isfile(override):   # en .carita también vale una forma: «alubia», «blog mandarina»…
        with open(override, encoding="utf-8", errors="ignore") as f:
            for word in f.read().lower().split():
                if word in SHAPES:
                    return word
    path = " ".join((root, os.path.abspath(cwd))).lower()
    for shape, words in rules_from_config("formas", "forma", SHAPE_RULES):
        if any(w in path for w in words):
            return shape
    return "redondita"


def costume_rules():
    """Las reglas de config.json si están bien; si no, las de serie."""
    try:
        with open(os.path.join(DIR, "config.json"), encoding="utf-8") as f:
            rules = json.load(f).get("disfraces")
        out = [(str(r["disfraz"]), tuple(str(w).lower() for w in r["palabras"] if str(w).strip()))
               for r in rules]
        return out if isinstance(rules, list) else RULES
    except Exception:
        return RULES


SHORT = {"blog": "vinoblog", "recursos": "vinorecursos", "trivia": "vinotrivia", "reels": "vinoreels",
         "bajovelo": "vino", "vino": "vino", "none": "none"}


def pick_costume(cwd):
    root = project_root(cwd)
    override = os.path.join(root, ".carita")
    if os.path.isfile(override):
        with open(override, encoding="utf-8", errors="ignore") as f:
            words = [w for w in f.read().lower().split() if w not in SHAPES] or ["none"]
            word = re.sub(r"[^a-z]", "", words[0])
        return SHORT.get(word, word or "none")
    name = ""
    try:
        with open(os.path.join(root, "package.json"), encoding="utf-8") as f:
            name = str(json.load(f).get("name", ""))
    except Exception:
        pass
    path = " ".join((name, root, os.path.abspath(cwd))).lower()
    for costume, words in costume_rules():
        if any(w in path for w in words):
            return costume
    return "none"


def write(name, content):
    os.makedirs(DIR, exist_ok=True)
    path = os.path.join(DIR, name)
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == content:
                return  # sin cambios: no despertar a la app
    except OSError:
        pass
    tmp = path + ".%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)


def log_event(ev, cwd):
    """Una línea en el historial: {"t", "ev", "proyecto", "disfraz"}. Append de una línea, rápido."""
    if not cwd:
        return
    line = json.dumps({"t": round(time.time(), 1), "ev": ev,
                       "proyecto": os.path.basename(project_root(cwd)) or "?",
                       "disfraz": pick_costume(cwd)}, ensure_ascii=False)
    os.makedirs(DIR, exist_ok=True)
    with open(os.path.join(DIR, "historial.jsonl"), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def session_id(data):
    sid = re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("session_id") or ""))
    return sid or None


def write_atomic(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)


def write_info(data):
    """Ficha de la sesión para la app: carpeta, proyecto, disfraz y pestaña de la terminal."""
    sid, cwd = session_id(data), data.get("cwd")
    if not sid or not cwd:
        return
    info = {"cwd": cwd, "proyecto": os.path.basename(project_root(cwd)) or "?",
            "disfraz": pick_costume(cwd), "forma": pick_shape(cwd), "tty": os.environ.get("CARITA_TTY", ""),
            "term": os.environ.get("CARITA_TERM", "")}
    path = os.path.join(SESSIONS, sid + ".info")
    try:
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
        if not info["tty"]:
            info["tty"] = old.get("tty", "")   # no perder la pestaña si esta vez no se pudo saber
        if old == info:
            return  # sin cambios: no despertar a la app
    except Exception:
        pass
    write_atomic(path, json.dumps(info, ensure_ascii=False))


def summary(data):
    text = data.get("last_assistant_message") or ""
    path = data.get("transcript_path")
    if not text and path and os.path.exists(path):
        for _ in range(4):  # el último mensaje puede tardar un pelín en escribirse
            text = last_answer(path)
            if text:
                break
            time.sleep(0.15)
    if not text:
        return
    voice, bubble = summarize(text)
    if voice:
        sid = session_id(data)
        path = os.path.join(SESSIONS, sid + ".say") if sid else os.path.join(DIR, "say")
        write_atomic(path, json.dumps({"voice": voice, "bubble": bubble}, ensure_ascii=False))


def main():
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    fallback = {"hello": "hello", "prompt": "thinking", "done": "done",
                "bashpre": "running", "bashpost": "thinking"}.get(event, "")
    state = fallback
    cwd = data.get("cwd")
    try:
        if event in ("hello", "prompt") and cwd:
            write("costume", pick_costume(cwd))
            write("shape", pick_shape(cwd))
            write_info(data)
        elif event == "info":
            write_info(data)
            state = ""
        elif event == "done":
            summary(data)
        elif event == "bashpre":
            if is_deploy((data.get("tool_input") or {}).get("command", "")):
                state = "deploying"
        elif event == "bashpost":
            if is_deploy((data.get("tool_input") or {}).get("command", "")):
                if deploy_ok(data.get("tool_response")):
                    state = "shipped"
                    log_event("shipped", cwd)
                else:
                    log_event("deploy_fallido", cwd)
    except Exception:
        state = fallback
    try:
        if event in ("prompt", "done"):
            log_event(event, cwd)
    except Exception:
        pass
    sys.stdout.write(state)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
