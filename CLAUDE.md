# Carita

App de macOS que pone cara a Claude Code: un bichito flotante que reacciona a lo que hace Claude Code en la terminal (leer, escribir, ejecutar, deploys, pedir permiso…), lee en voz alta un resumen de cada respuesta y se disfraza según el subproyecto de Bajovelo. Es de uso personal de Isra (macOS, trabaja con Vue/Astro/Supabase, todo bajo el paraguas Bajovelo).

**Idioma:** todo lo que ve u oye el usuario (textos, menús, frases, README) va en español de España, tono cercano y gamberro. Los comentarios del código también en español.

## Cómo está montada

```
Claude Code ──hooks──▶ ~/.carita/hook.sh <evento>
                         ├─ carita.py (solo para hello, prompt, done, Bash pre/post y la ficha de una sesión nueva)
                         └─ escribe ~/.carita/sesiones/<session_id>.{state, say, info}
                            (sin session_id: ~/.carita/{state, say}; además costume y term)
Carita.app ── lee esos archivos ──▶ un bicho (Creature: panel + WKWebView con face.html) por sesión
```

| Archivo | Qué es |
|---|---|
| `main.swift` | La app (AppKit, sin Xcode). Panel flotante transparente con un `WKWebView`, capa `DragView` para arrastrar y hacer clic, bocadillo nativo (`BubbleView` en su propio panel), voz (`AVSpeechSynthesizer`), viaje hasta el ratón, menú contextual. |
| `Creature.swift` | Un bicho: su panel, su cara (`WKWebView`), su bocadillo, su viaje, la mirada y la sesión que representa (`SessionInfo` de `<id>.info`: carpeta, proyecto, disfraz, tty y app de terminal). `AppDelegate` reparte las sesiones (`adopt`, `retire`, como mucho 4). |
| `Sofa.swift` | El sofá: `SofaView` lo dibuja en dos paneles (respaldo detrás de los bichos, cojín y brazos delante) y `Sofa` coloca las plazas. `AppDelegate.sofaTick()` sienta a los que llevan un rato quietos (`isResting`) y `arrangeSofa()` ordena las capas. En la cara, `carita.sit(bool)`. |
| `Voice.swift` | Hablarle: `Listener` (micrófono + `SFSpeechRecognizer` es-ES en el Mac, resultados parciales) y `Typist` (trae al frente la pestaña de Terminal por su tty con AppleScript, pega con ⌘V simulado —necesita Accesibilidad— y devuelve el portapapeles). El atajo usa pulsar y soltar de Carbon (`HotKeys`, id 3). |
| `Settings.swift` | `Config` (`~/.carita/config.json`, única fuente de verdad; migra lo que había en `UserDefaults`), `ConfigStore` (guarda y recarga si se edita a mano) y la ventana de Ajustes en SwiftUI. |
| `Diagnostics.swift` | Ventana de diagnóstico (semáforos, reinstalar hooks, probar, copiar informe) y `Scripts`: copia `hook.sh`/`carita.py` de la app a `~/.carita` (también al arrancar si no coinciden). |
| `Stats.swift` | Historial (`~/.carita/historial.jsonl`, rotación a `historial-resumen.json`) y ventana de estadísticas con Swift Charts. |
| `Updater.swift` | Buscar actualizaciones (API de Releases de GitHub, repo público) y actualizar con un clic: descarga con `URLSession`, `ditto`, verifica firma y versión, sustituye la app y la relanza. |
| `face.html` | El personaje: SVG + CSS + JS. Sirve a la vez de **demo en el navegador** (sin `window.webkit`) y de cara dentro de la app (`html.app`). API global `window.carita`: `set(state)`, `poke()`, `look(x,y)`, `reply(text)`, `talking(bool)`, `costume(name)`, `travel(dir)`, `mask(bool)`, `say(text)`, `hidden(bool)`, `config({nombre, breakAfter, maskAfter, breakGap, frases})`. |
| `hook.sh` | Lo ejecuta Claude Code en cada evento. Lee el JSON por stdin, decide el estado y lo escribe de forma atómica. |
| `carita.py` | Ayudante de los hooks: elige disfraz por la ruta del proyecto, detecta deploys en Bash y si salieron bien, y resume la última respuesta (desde `transcript_path`) para la voz. Imprime solo el estado final. |
| `hooks.py` | Añade/quita los hooks de Carita en `~/.claude/settings.json` sin tocar lo demás (`install` / `uninstall`; `status` solo consulta). Idempotente. |
| `build.sh` | Compila y monta `build/Carita.app` (versión desde `VERSION`, que también estampa en las copias de `hook.sh` y `carita.py` de dentro de la app). |
| `install.sh` / `uninstall.sh` | Instalan/desinstalan app + hooks. |
| `Carita.icns` | Icono. |

### Estados (`~/.carita/state`)
`hello, thinking, reading, writing, running, deploying, shipped, browsing, delegating, asking, done, bye` llegan de los hooks. `idle, sleepy, sleeping, stretch, poke` los decide `face.html`. Cada estado está en el objeto `S` de `face.html` (ojos, boca, cejas, si habla, `lock`, `after`) y sus frases en `FRASES` (variantes `…Vino` para Bajovelo).

### Disfraces (`~/.carita/costume`)
`none, vino, vinoblog, vinorecursos, vinotrivia, vinoreels`. Los elige `pick_costume()` en `carita.py` por palabras en la ruta (reglas `disfraces` de `config.json`, o `RULES` de serie); un archivo `.carita` en la raíz del proyecto lo fuerza. En `face.html`, `data-costume` y `data-cbase="vino"` (boina siempre en Bajovelo).

## Reglas que no se pueden romper

- **`hook.sh` nunca imprime nada por stdout y siempre sale con 0.** En `UserPromptSubmit` la salida se añadiría al contexto de Claude; un código 2 en `Stop` bloquearía a Claude.
- **Los hooks tienen que ser rápidos** (se ejecutan en cada herramienta). Python solo donde hace falta.
- **`hooks.py` no puede perder configuración del usuario.** Solo toca entradas cuyo comando contiene `/.carita/hook.sh`, y guarda copia la primera vez.
- **Geometría sincronizada:** el `viewBox` de la app (`-20 -24 240 224` en `face.html`) y `VB_X`, `VB_Y`, `VB_W`, `baseSize` en `main.swift` deben coincidir. De ahí salen el área clicable (elipse centrada en 100,112), la posición del bocadillo y hacia dónde miran los ojos. El panel de cada bicho mide eso más `labelHeight` por debajo (la etiqueta con el proyecto): las cuentas se hacen desde arriba (`frame.maxY`).
- **Solo el bicho recibe clics:** el panel cambia `ignoresMouseEvents` según el ratón esté o no sobre el cuerpo. No romperlo con ventanas nuevas.
- **Nada sale del Mac** salvo lo que se pida explícitamente (p. ej., buscar actualizaciones).
- **Ajustes solo en `config.json`**, nunca en `UserDefaults` (salvo la posición de la ventana, que guarda AppKit). Cualquier cambio pasa por `store.c` y se aplica en `configChanged(from:)`.
- Swift: modo `-swift-version 5`, macOS 13+, sin dependencias externas. Archivos: `main.swift`, `Creature.swift`, `Sofa.swift`, `Voice.swift`, `Settings.swift`, `Diagnostics.swift`, `Stats.swift` y `Updater.swift` (si se añade otro, actualizar `build.sh`). Evitar closures `@Sendable` que toquen estado del main actor: usar `Timer` con selector, como el resto del código.

## Cómo probar

- **Cara:** abre `face.html` en el navegador; los botones de la demo recorren todos los estados y disfraces.
- **App:** `./build.sh && open build/Carita.app` (o `bash install.sh` para instalarla de verdad). Clic derecho → «Probar expresión».
- **Aislada:** `open -n --env CARITA_DIR=/carpeta build/Carita.app` usa otra carpeta en vez de `~/.carita` (los hooks también respetan `CARITA_DIR`): sirve para simular sesiones con `echo '{"session_id":"a1","cwd":"…"}' | CARITA_DIR=/carpeta /carpeta/hook.sh hello` sin que lleguen las reales.
- **Registro:** `open --env CARITA_LOG=/tmp/carita.log build/Carita.app` apunta cada llamada a la cara, la voz, el bocadillo, no molestar y los atajos.
- **Capturas de las ventanas:** `open --env CARITA_SNAPSHOT=/carpeta build/Carita.app` abre Ajustes, Diagnóstico y Estadísticas, las guarda como PNG y las cierra (no hace falta permiso de grabación de pantalla).
- **Hooks sin Claude Code:**
  ```bash
  echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | ~/.carita/hook.sh bashpre; cat ~/.carita/state   # deploying
  echo '{"cwd":"'$HOME'/Proyectos/bajovelo/blog"}' | ~/.carita/hook.sh prompt; cat ~/.carita/costume      # vinoblog
  ```
- Tras tocar `hooks.py`, compara `~/.claude/settings.json` antes y después.

## Versiones y commits

- **Firma:** `build.sh` firma con «Carita (firma propia)», un certificado autofirmado que está en el llavero `~/Library/Keychains/carita-firma.keychain-db` (contraseña en `~/.config/carita/keychain.pass`, nunca en el repo); si no está, firma ad hoc. En GitHub Actions sale de los secretos `CARITA_P12` y `CARITA_P12_PASS`; el certificado público está en `.github/carita-firma.pem`. Con la misma identidad, macOS conserva los permisos (TCC) entre versiones, y el actualizador rechaza apps firmadas con otro certificado.
- Para publicar: sube `VERSION`, commit, `git tag vX.Y.Z && git push --tags`. El workflow comprueba que la etiqueta coincide con `VERSION` y publica la Release con `Carita.zip`; las apps instaladas la ven en «Buscar actualizaciones».
- Versión en `VERSION` (semver). Súbela en cada mejora que llegue al usuario.
- Un commit por tarea del `ROADMAP.md`, mensaje en español.
- Actualiza `README.md` cuando cambie algo que el usuario ve.
