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

Además: los ojos siguen al ratón, parpadea, y si le haces clic le das cosquillas.

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

Si alguna carpeta no la pilla bien, crea un archivo `.carita` en su raíz con una palabra: `blog`, `recursos`, `trivia`, `reels`, `bajovelo` o `none`. También puedes fijarlo a mano: clic derecho → Disfraz.

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

## Te lee las respuestas

Cuando termino de responder, Carita te dice en voz alta la idea general (las primeras frases, sin código, tablas ni rutas largas) y pone la frase principal en el bocadillo, moviendo la boca mientras habla.

- **Callarla**: clic encima mientras habla. También se calla sola si le mandas otra cosa a Claude Code.
- **Activar o desactivar**: clic derecho → «Leer mis respuestas en voz alta».
- **Mejor voz**: la que viene de serie suena algo robótica. En Ajustes del Sistema → Accesibilidad → Contenido leído → Voz del sistema → Gestionar voces, descarga una voz de *Español (España)* con la etiqueta «mejorada» o «prémium» (por ejemplo, Mónica). Carita elige sola la mejor que tengas instalada; reiníciala después de descargarla.

## Instalar

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

## Cómo funciona

```
Claude Code ──hook──▶ ~/.carita/hook.sh <estado> ──▶ ~/.carita/state ──▶ Carita.app ──▶ face.html
```

Los hooks solo escriben una palabra en un archivo. `carita.py` elige el disfraz, detecta los deploys y, al terminar, saca la última respuesta de la conversación y deja el resumen en `~/.carita/say`. La app vigila esa carpeta (sin consultarla en bucle) y cambia la cara al momento. Cuando se duerme, para todas las animaciones para no gastar batería. Nada sale de tu Mac.

## Personalizar

Todo el personaje está en `face.html`:

- `NOMBRE` al principio del script: cómo te llama.
- `FRASES`: lo que dice en cada estado.
- `BREAK_AFTER`, `MASK_AFTER`, `BREAK_GAP`: los tiempos del modo descanso.
- Colores en `:root` (`--clay`, `--leaf`…).

Puedes abrir `face.html` en el navegador para ver la demo. Tras cambiarlo, vuelve a ejecutar `bash install.sh`.

## Desinstalar

```bash
bash uninstall.sh
```
