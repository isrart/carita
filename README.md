# Carita

> Para desarrollo: `CLAUDE.md` explica cómo está montada y `ROADMAP.md` lista las próximas mejoras.

Un bichito que flota encima de todo en tu Mac y pone cara a lo que hace Claude Code en la terminal.

| Claude Code está…            | Carita…                                   |
|------------------------------|-------------------------------------------|
| arrancando sesión            | te saluda con la manita                   |
| pensando (le mandas algo)    | mira al techo y le da vueltas a la hoja   |
| leyendo archivos             | se pone las gafas y escanea               |
| editando / escribiendo       | saca la lengua y garabatea con el lápiz   |
| ejecutando comandos (Bash)   | casco de obra, dientes apretados, sudando |
| buscando en internet         | lupa en mano                              |
| lanzando subagentes          | aparecen dos mini-colegas                 |
| esperando que decidas algo   | salta, agita los brazos y te llama        |
| terminado                    | confeti y sonrisa                         |
| 3 min sin nada               | bosteza                                   |
| 12 min sin nada              | se duerme (con pompa de moco incluida)    |

Además: los ojos siguen al ratón, parpadea, y si le haces clic le das cosquillas. Si pasa minuto y medio sin novedades, se queda quieta (sin dejar de mirarte ni de parpadear) para no gastar batería.

## Un bicho por sesión

Si tienes varias sesiones de Claude Code abiertas a la vez (por ejemplo, el blog de Bajovelo en una terminal y otro proyecto en otra), cada una tiene su propio bicho, con su disfraz y su nombre debajo: el que le pongas con `/rename` en Claude Code o, si no, el de la carpeta. El que despliega es el que brinda; el que termina es el que te lee la respuesta. Cuando cierras una sesión, su bicho se despide y se va. Como mucho salen 4; si hay más, el que lleve más rato parado se cambia a la sesión nueva.

### El sofá

Para que varios bichos parados no parezcan «un frutero lleno de naranjas»: cuando hay dos o más y llevan un minuto sin novedades, se van andando a un sofá y se sientan juntos (si se duermen, se apoyan en el de al lado). Cuando la sesión de uno hace algo, ese se levanta y se pone delante a trabajar; al acabar, vuelve a su plaza. Si sacas a uno del sofá arrastrándolo, se queda donde lo sueltes hasta que su sesión vuelva a hacer algo.

## Disfraces según el proyecto

En cualquier cosa de Bajovelo lleva la boina granate, y en la mano algo según el subproyecto. Lo deduce del nombre de la carpeta:

| Si la carpeta contiene… | Disfraz |
|---|---|
| trivia, quiz, preguntas, denominacion | boina + cartel con «?» |
| reel, insta, video, redes, social | boina + móvil grabando |
| recurso, guia, ficha, descarga | boina + guía de vino |
| blog, articulo | boina con pluma + cuaderno |
| bajovelo, vino, wine (lo demás de Bajovelo) | boina + copa de vino |
| nada de lo anterior | sin disfraz |

Las palabras se pueden cambiar (y añadir reglas nuevas) en Ajustes → Disfraces. Si alguna carpeta no la pilla bien, crea un archivo `.carita` en su raíz con una palabra: `blog`, `recursos`, `trivia`, `reels`, `bajovelo` o `none`. También puedes fijarlo a mano: clic derecho → Disfraz.

## Fiesta de deploy

Cuando lanzo un `git push`, un `deploy` (npm, Netlify, Firebase, Fly, Supabase…), `vercel --prod` o `supabase db push`, aparece un cohete en la plataforma de lanzamiento. Si sale bien, despega y hay fuegos artificiales. Si falla, no hay fiesta.

En los proyectos de Bajovelo, en lugar del cohete agita una botella de cava y, si el deploy sale bien, salta el tapón (con su «pop») y brinda contigo.

## Modo descanso

Tras 90 minutos seguidos de trabajo, se estira y te dice cuánto llevas. Si lo ignoras y sigues 10 minutos más, se pone un antifaz (y lo lleva puesto mientras trabaja). Cuando pasan 5 minutos sin actividad cuenta como descanso: se lo quita y el contador vuelve a cero.

## Te busca cuando te necesita

Si necesito que decidas algo y estás en otra app, Carita cruza la pantalla corriendo hasta donde tienes el ratón. Un clic sobre ella te lleva a la terminal donde está Claude Code, y cuando respondes vuelve a su sitio. Se desactiva en clic derecho → «Ir a buscarme cuando me necesita».

## No molesta en las llamadas

Si enciendes la cámara (Zoom, Meet, FaceTime, Teams… cualquier app), Carita se esconde y se calla; cuando la apagas, vuelve sola. Mientras tanto sigue enterándose de lo que hace Claude Code, así que vuelve al día.

También se esconde si compartes pantalla con Zoom, si alguien está viendo tu Mac con Compartir pantalla o si duplicas la pantalla (AirPlay o proyector). Compartir pantalla desde Meet o Teams en el navegador sin cámara no se puede detectar. El modo concentración del Mac tampoco: macOS no se lo cuenta a una app como esta.

Se configura en el menú → «No molestar automático», donde también ves qué detecta ahora mismo.

## Háblale

**Mantén pulsado `⌃⌥⌘Espacio`** mientras hablas, como un walkie-talkie. El bicho de la sesión que estuvo activa la última se lleva la mano a la oreja y va escribiendo en su bocadillo lo que entiende. Al soltar, trae al frente la terminal de esa sesión y **deja el texto escrito, sin pulsar Intro**: lo revisas y lo envías tú.

- El reconocimiento es en español de España y **en tu Mac, sin internet**.
- La primera vez pide permiso para el **micrófono** y el **reconocimiento de voz**. Para que escriba ella en la terminal necesita además **Accesibilidad** (Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → Carita). Sin ese permiso, te deja el texto copiado y te dice que lo pegues con `⌘V`.
- En Terminal elige la pestaña exacta de la sesión (te pedirá permiso de Automatización una vez). En otras terminales (Warp, iTerm…) trae la app al frente y pega donde estés.
- El atajo se cambia en Ajustes → Atajos.

## Te lee las respuestas

Cuando termino de responder, Carita te dice en voz alta la idea general (las primeras frases, sin código, tablas ni rutas largas) y pone la frase principal en el bocadillo, moviendo la boca mientras habla.

- **Callarla**: clic encima mientras habla. También se calla sola si le mandas otra cosa a Claude Code.
- **Activar o desactivar**: clic derecho → «Leer mis respuestas en voz alta».
- **Elegir voz, velocidad y tono**: Ajustes → Voz, con botón «Probar».
- **Mejor voz**: la que viene de serie suena algo robótica. En Ajustes del Sistema → Accesibilidad → Contenido leído → Voz del sistema → Gestionar voces, descarga una voz de *Español (España)* con la etiqueta «mejorada» o «prémium» (por ejemplo, Mónica). Carita elige sola la mejor que tengas instalada (o la que escojas en Ajustes → Voz); reiníciala después de descargarla.

## Instalar

### Ya compilada (lo más fácil)

1. Descarga **Carita.zip** de la [última Release](https://github.com/isrart/carita/releases/latest), descomprímelo y mueve **Carita.app** a `~/Applications` (o a Aplicaciones).
2. **La primera vez, clic derecho → Abrir → Abrir.** La app va firmada con un certificado propio, no con uno de Apple (no hay cuenta de desarrollador), así que Gatekeeper avisa de que no puede comprobarla. Gracias a ese certificado, macOS no olvida los permisos (micrófono, accesibilidad) cuando Carita se actualiza. Si ni así te deja, quítale la cuarentena:
   ```bash
   xattr -dr com.apple.quarantine ~/Applications/Carita.app
   ```
3. Menú del bichito → **Diagnóstico… → Reinstalar hooks**. Copia los scripts a `~/.carita` y conecta los hooks de Claude Code (sin tocar lo demás de tu `settings.json`).
4. Abre una sesión **nueva** de Claude Code.

Necesitas `python3` (viene con las Command Line Tools: `xcode-select --install`).

### Desde el código

Necesitas macOS 13 o superior y las Command Line Tools (`xcode-select --install` si no las tienes).

```bash
cd carita
bash install.sh
```

El script:

1. Compila la app con `build.sh` y la deja en `~/Applications/Carita.app`.
2. Copia `hook.sh` a `~/.carita/`.
3. Añade los hooks a `~/.claude/settings.json` sin tocar lo que ya tengas (guarda copia en `settings.json.antes-de-carita`).
4. Abre Carita.

Abre una sesión **nueva** de Claude Code para que coja los hooks.

## Usar

- **Arrastrar**: muévela a donde quieras, incluso pegada arriba del todo; recuerda la posición.
- **Bocadillo**: sale pegado a la cabeza; si no cabe por arriba, aparece debajo.
- **Clic**: cosquillas. Si está hablando, se calla. Si te está llamando, te lleva a la terminal.
- **Clic derecho** (o el icono del bicho en la barra de menús, que tiene el mismo menú): ocultar/mostrar, silenciar 1 hora, tamaño, disfraz, leer respuestas en voz alta, avisos con voz («¡Hecho!», «te necesito»), ir a buscarte, abrir al iniciar sesión, probar expresiones y salir.
- **Ocultarla**: desde la barra de menús la vuelves a mostrar; se acuerda aunque reinicies. Si te necesita estando oculta, al icono le sale una exclamación.
- **Silenciar 1 hora**: ni voz, ni bocadillos, ni viene a buscarte. En el menú pone hasta qué hora («Silenciada hasta las 15:40») y se reactiva sola.
- **Atajos de teclado** (funcionan con cualquier app delante): `⌃⌥⌘C` la esconde o la muestra; `⌃⌥⌘M` la calla al momento y la silencia una hora (otra vez, la reactiva). Si chocan con un atajo del Mac, te avisa en el bocadillo.
- **Abrirla**: Spotlight (`Cmd + Espacio` → «Carita») o `open ~/Applications/Carita.app`.

## Estadísticas

Menú → **Estadísticas…**, esta semana o este mes:

- **Horas por proyecto** (en color, los de Bajovelo). Cuenta cada pregunta a Claude Code hasta su respuesta, más los ratos seguidos sin pausas de más de 5 minutos.
- **Tareas terminadas** por día.
- **Deploys**: los que llegaron a producción y los que fallaron.
- **Descansos**: cuántas veces te pidió estirarte y cuántas lo ignoraste.

Se apuntan en `~/.carita/historial.jsonl` (una línea por evento). Cuando pasa de 2 MB, lo de hace más de 60 días se resume por días en `historial-resumen.json`. Todo se queda en tu Mac.

## ¿No reacciona?

Menú → **Diagnóstico…** enseña con semáforos lo que puede fallar: cuándo llegó el último aviso de Claude Code, si los hooks están en `~/.claude/settings.json`, si `hook.sh` y `python3` están bien, si los scripts son de la misma versión que la app, qué terminal ha detectado y qué voz usa.

- **Reinstalar hooks** vuelve a copiar los scripts y a poner los hooks (sin tocar lo demás de tu `settings.json`).
- **Probar** hace lo mismo que Claude Code al empezar una sesión y comprueba que Carita se entera.
- **Copiar informe** deja el resultado en el portapapeles, para pegarlo donde haga falta.

Al arrancar, si los scripts de `~/.carita` son de otra versión que la app, Carita los actualiza sola.

## Cómo funciona

```
Claude Code ──hook──▶ ~/.carita/hook.sh <estado> ──▶ ~/.carita/state ──▶ Carita.app ──▶ face.html
```

Los hooks solo escriben una palabra en un archivo. `carita.py` elige el disfraz, detecta los deploys y, al terminar, saca la última respuesta de la conversación y deja el resumen en `~/.carita/say`. La app vigila esa carpeta (sin consultarla en bucle) y cambia la cara al momento. Cuando se duerme, para todas las animaciones para no gastar batería. Nada sale de tu Mac.

## Ajustes

Menú → **Ajustes…** (`⌘,` con el menú abierto). Todo se aplica al momento, sin reiniciar:

- **General**: tu nombre (cómo te llama), tamaño, ir a buscarte y abrir al iniciar sesión.
- **Voz**: leer respuestas, avisos con voz, qué voz, velocidad y tono.
- **Descanso**: minutos hasta estirarse (90), hasta el antifaz (10) y pausa que cuenta como descanso (5).
- **Disfraces**: el disfraz fijo o automático y las palabras de cada uno.
- **No molestar** y **Atajos**.

Se guardan en `~/.carita/config.json`. Puedes editarlo a mano; si lo guardas con un error, Carita te avisa y sigue con lo de antes.

## Frases a tu gusto

Ajustes → General → **Editar frases…** crea `~/.carita/frases.json` con todas las frases de serie y lo abre en tu editor. Al guardar, la siguiente frase ya es la nueva, sin reiniciar nada:

```json
{
  "done": ["¡Hecho, máquina!", "Otra más al saco"],
  "+asking": ["Isra, que te estoy esperando…"]
}
```

- Cada estado que pongas **sustituye** a sus frases de serie; los que no pongas se quedan como estaban.
- Con `+` delante (`"+done"`) **añades** frases a las de serie en vez de sustituirlas.
- `{n}` es tu nombre y `{t}` el tiempo que llevas trabajando (en `stretch`).
- Si el archivo tiene un error, Carita te dice en qué línea y sigue con las de serie.

## Personalizar el personaje

El dibujo está en `face.html`: frases (`FRASES`), colores en `:root` (`--clay`, `--leaf`…). Puedes abrir `face.html` en el navegador para ver la demo. Tras cambiarlo, vuelve a ejecutar `bash install.sh`.

## Actualizar

Menú → **Buscar actualizaciones…**. Si hay una versión nueva, Carita te lo dice en el bocadillo y en el menú aparece **«Actualizar a la X.Y.Z…»**: la descarga, sustituye la app, actualiza los scripts de `~/.carita` y se reinicia sola, sin tocar la terminal.

Además lo mira sola una vez al día (se desactiva en Ajustes → General). Es lo único que sale de tu Mac: una consulta a GitHub por la última versión.

Si trabajas con el código: `git pull && bash install.sh`.

## Desinstalar

```bash
bash uninstall.sh
```
