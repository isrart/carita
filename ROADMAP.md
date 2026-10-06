# Roadmap: mejoras de la app

Diez mejoras de la app en sí (no del personaje). Están en el orden recomendado de implementación: las primeras preparan el terreno de las siguientes. **Una tarea = un commit**, compilando con `./build.sh` y probando antes de pasar a la siguiente. Lee `CLAUDE.md` antes de empezar.

Si algo de una especificación no es posible o es mala idea al implementarlo, haz la alternativa más cercana y anótalo en el commit. Si dudas en algo que cambia lo que ve el usuario, pregunta a Isra.

---

## 1. Vigilar archivos en vez de mirarlos 20 veces por segundo (ahorro de batería)

**Por qué:** ahora un `Timer` a 20 Hz hace `stat` de 3 archivos y calcula la mirada aunque no pase nada.

**Qué hacer:**
- Vigilar la carpeta `~/.carita` con `DispatchSource.makeFileSystemObjectSource` (`O_EVTONLY`, evento `.write`). Las escrituras son atómicas (`mv`), así que cambian la carpeta, no el archivo. Al dispararse, reutilizar la lógica actual de `tick()` (comparar `mtime` de `state`, `say`, `costume`).
- Seguir al ratón con `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])` más un monitor local; no necesita permiso de accesibilidad. Calcular `look` y `ignoresMouseEvents` solo ahí.
- Mantener un `Timer` de respaldo lento (cada 2 s) por si se pierde algún evento.
- En `face.html`: clase `paused` en `#c` que ponga `animation-play-state: paused` cuando duerme o la app está oculta (ver tarea 3). Los parpadeos y el `setInterval` también se paran.

**Hecho cuando:** Carita reacciona igual de rápido que antes y, en reposo, el uso de CPU en Monitor de Actividad baja claramente (anota antes/después en el commit).

---

## 2. Icono en la barra de menús

**Por qué:** ahora todo va por clic derecho sobre el bicho; si se esconde no hay forma de recuperarlo.

**Qué hacer:**
- `NSStatusItem` con un icono plantilla (silueta monocroma del bicho con su hoja, en PDF o SVG convertido, que se vea bien en modo claro y oscuro).
- El menú del status item y el del clic derecho salen del **mismo** constructor (refactorizar `refreshMenu()`).
- Añadir al menú: **Mostrar/Ocultar Carita**, **Silenciar 1 hora** (sin voz ni avisos; se reactiva solo, con la hora en el menú: «Silenciada hasta las 15:40») y **Ajustes…** (tarea 5).
- Opcional: el icono cambia ligeramente cuando Carita te necesita (`asking`), por si está oculta.
- Recordar si estaba oculta entre reinicios.

**Hecho cuando:** se puede esconder, volver a mostrar y silenciar sin tocar el bicho, y el menú es idéntico por las dos vías.

---

## 3. No molestar automático

**Qué hacer:** que Carita se oculte y se calle sola (y vuelva sola) cuando:
- **Cámara encendida** (videollamada): CoreMediaIO, propiedad `kCMIODevicePropertyDeviceIsRunningSomewhere` en los dispositivos de vídeo, con listener. Sirve para Zoom, Meet en el navegador, FaceTime, Teams…
- **Compartiendo pantalla:** no hay API pública directa. Prueba heurísticas razonables (p. ej., el indicador de captura del sistema / `CGWindowListCopyWindowInfo` buscando ventanas de captura, o apps de llamada en primer plano). Si no hay forma fiable, deja solo la cámara y documéntalo.
- **Modo concentración del Mac:** `INFocusStatusCenter` (Intents), que pide autorización al usuario. Comprueba si funciona en una app sin sandbox firmada ad hoc; si no, descártalo y anótalo.
- Mientras está en «no molestar» sigue recibiendo estados (para estar al día al volver) pero no habla, no viaja y no se ve.
- Opción en el menú/ajustes para desactivarlo, con lo que detecta en cada caso.

**Hecho cuando:** al abrir una videollamada desaparece y al cerrarla vuelve sin hacer nada.

---

## 4. Atajo de teclado global

**Qué hacer:**
- `⌥⌘C` por defecto: mostrar/ocultar. `⌥⌘M`: callarla (parar la voz en curso y silenciar 1 hora; repetir lo reactiva).
- Usar `RegisterEventHotKey` de Carbon: no pide permisos de accesibilidad (`NSEvent` global para teclas sí).
- Configurables en Ajustes (tarea 5) con un grabador de atajos sencillo; si choca con otro atajo, avisar.

**Hecho cuando:** los atajos funcionan con cualquier app en primer plano y sin pedir permisos.

---

## 5. Ventana de ajustes

**Qué hacer:**
- Ventana SwiftUI (`NSHostingController` en un `NSWindow` normal; al abrirla, `NSApp.activate` porque la app es `LSUIElement`). Pestañas o secciones:
  - **General:** tu nombre (el `NOMBRE` de `face.html`), tamaño, abrir al iniciar sesión.
  - **Voz:** leer respuestas sí/no, avisos con voz sí/no, voz (lista de voces `es-ES` instaladas con su calidad), velocidad, tono, botón «Probar».
  - **Descanso:** minutos hasta estirarse (90), hasta el antifaz (10) y pausa que cuenta como descanso (5).
  - **Disfraces:** tabla editable de palabras clave → disfraz (las de `SUBPROJECTS` y `WINE` de `carita.py`).
  - **No molestar** y **Atajos** (tareas 3 y 4).
- Todo se guarda en **`~/.carita/config.json`** (una sola fuente de verdad), no en `UserDefaults`; migrar los valores que ya están en `UserDefaults`.
- `carita.py` lee `config.json` para las palabras de los disfraces (con los valores actuales por defecto si no existe).
- `face.html` recibe la config con una nueva función `carita.config({nombre, breakAfter, maskAfter, breakGap, frases})` al cargar y cada vez que cambia.

**Hecho cuando:** cualquier cambio en Ajustes se aplica al momento, sin reinstalar ni reiniciar.

---

## 6. Frases editables sin reinstalar

**Qué hacer:**
- `~/.carita/frases.json` opcional con la misma forma que `FRASES` (`{"done": ["…", "…"], "shippedVino": […]}`). Las claves que estén **sustituyen** a las de serie; las que no, se quedan. Clave especial `"+done"` para **añadir** en vez de sustituir.
- La app vigila el archivo (ya lo hace por la tarea 1) y se lo pasa a `carita.config`.
- En Ajustes, botón «Editar frases…» que crea el archivo con las frases actuales si no existe y lo abre en el editor por defecto.
- Si el JSON está mal, no romper nada: seguir con las frases de serie y avisar en el bocadillo («Hay un error en frases.json, línea N»).

**Hecho cuando:** editas `frases.json`, guardas y la siguiente frase ya es la nueva.

---

## 7. Diagnóstico «¿por qué no reacciona?»

**Qué hacer:** opción **Diagnóstico…** en el menú que abra una ventanita con semáforos:
- Último aviso de Claude Code: estado y hace cuánto (mtime de `~/.carita/state`).
- Hooks instalados en `~/.claude/settings.json` (y cuántos de los esperados en `hooks.py`), `hook.sh` existe y es ejecutable, `/usr/bin/python3` disponible, versión de `carita.py` igual a la de la app.
- Terminal detectada (`~/.carita/term`) y voz que se está usando.
- Botones: **Reinstalar hooks** (ejecuta los scripts que van dentro de la app, `Contents/Resources/hooks.py`, y copia `hook.sh` y `carita.py` a `~/.carita`), **Probar** (escribe un estado de prueba y comprueba que llega), **Copiar informe** (texto al portapapeles para pegármelo).
- Además, al arrancar: si los scripts de `~/.carita` son de otra versión que los de la app, actualizarlos solos (necesario para la tarea 9).

**Hecho cuando:** si borras a mano los hooks de `settings.json`, el diagnóstico lo marca en rojo y «Reinstalar hooks» lo arregla.

---

## 8. Estadísticas locales

**Qué hacer:**
- `hook.sh`/`carita.py` añaden una línea a `~/.carita/historial.jsonl` en `prompt`, `done`, `shipped` y fallo de deploy: `{"t": epoch, "ev": "...", "proyecto": "<carpeta raíz>", "disfraz": "..."}`. Debe seguir siendo rápido (append de una línea). La app añade `stretch` y `mask` (descansos pedidos e ignorados).
- Ventana **Estadísticas** (SwiftUI + Swift Charts, macOS 13): horas de trabajo por proyecto de Bajovelo esta semana (sumando tramos entre eventos con huecos < 5 min), tareas terminadas por día, deploys de la semana (y fallidos) y descansos pedidos/ignorados. Selector semana/mes.
- Rotación: si el historial pasa de unos MB, resumir lo antiguo por días.
- Todo local; nada se envía a ningún sitio.

**Hecho cuando:** después de un día normal de trabajo la ventana muestra números creíbles.

---

## 9. App ya compilada con GitHub Actions

Ya hay un workflow inicial en `.github/workflows/build.yml` que compila en un runner de macOS y sube `Carita.zip`. Revísalo y termínalo:
- Que funcione la primera vez (versión de Xcode del runner, `ditto` para el zip conservando la firma).
- Al crear una etiqueta `vX.Y.Z` que coincida con `VERSION`, publicar una **Release** con el zip y el changelog de los commits.
- **Firma:** sin cuenta de desarrollador de Apple solo hay firma ad hoc, y Gatekeeper avisará al abrir la app descargada con el navegador. Documenta en el README cómo abrirla la primera vez (clic derecho → Abrir, o `xattr -dr com.apple.quarantine`). Si Isra quiere, más adelante se añade firma y notarización con su Developer ID mediante secretos del repo.

**Hecho cuando:** `git tag v1.5.0 && git push --tags` genera una Release con la app descargable.

---

## 10. Actualizar con un clic

**Qué hacer:**
- Opción **Buscar actualizaciones…** en el menú y comprobación silenciosa una vez al día: consulta la última Release del repo en la API de GitHub y compara con `CFBundleShortVersionString`.
- Si hay una nueva, Carita lo dice en el bocadillo («¡Hay versión nueva! Clic derecho → Actualizar»). Al aceptar: descargar el zip con `URLSession` (no se marca en cuarentena), descomprimir con `ditto`, sustituir `~/Applications/Carita.app`, actualizar los scripts de `~/.carita` (tarea 7) y relanzar.
- Si el repo es privado, la API necesita token: en ese caso, guardar un token de solo lectura en el Llavero desde Ajustes, o proponer hacer el repo público (no lleva nada privado). Pregunta a Isra.
- Para desarrollo sigue valiendo `git pull && bash install.sh`.

**Hecho cuando:** con una versión vieja instalada, «Buscar actualizaciones» deja la nueva funcionando sin tocar la terminal.
