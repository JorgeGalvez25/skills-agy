# Actualizar la caché de #mtto

Todas las skills que usan los standups (`/mtto-standup`, `/mtto-fechas`, `/mtto-quincenal`, `/mtto-rendimiento`) trabajan sobre la misma caché:
`C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\canal_mtto.json`. Slack se lee **una sola vez** y solo lo que falta;
después cada skill consulta la caché con su script. No leas el canal de otra forma ni edites la caché a mano.

`$C` = `C:/Users/jorge/.gemini/config/skills/mtto-comun`. El ID del canal y el equipo están en `$C/equipo.json`.

## 1. Saber desde dónde leer

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" oldest [dd/mm/aaaa]
```

El argumento es el primer día que necesita la skill que te mandó aquí (ella lo indica). Devuelve `oldest` (timestamp Unix para Slack) y `desde` (`AAAA-MM-DD`).
Normalmente son 3 días antes del último mensaje guardado, para recoger los standups que se editaron; si la caché no cubre el día pedido, se lee desde ese día.

## 2. Leer Slack [subagente]

**No leas el canal tú.** Lanza un subagente (invocando `invoke_subagent` con `TypeName: "self"`, `Role: "Lector Canal Slack"`, `Model: "flash"`) con estas instrucciones y los valores del paso 1.
Si la skill tiene otras lecturas que delegar, lánzalas en una sola llamada a `invoke_subagent` para que corran en paralelo.

- Canal **#mtto**, ID `C02CGD1D9NX`. Obtén los mensajes ejecutando con `run_command`:
  `node "C:\Users\jorge\.gemini\config\scripts\slack.js" history C02CGD1D9NX <oldest> 1000 "<scratchpad>/raw_mtto.json"`
  con `oldest` = el del paso 1.
  `slack.js history` se detiene al juntar el tope (1000): si el archivo sale con 1000 mensajes o es demasiado grande, revisa el `oldest` y acorta la ventana en lugar de procesarlo.
- Si el helper de Slack falla por el token (p. ej. error de autenticación o token expirado no renovable), avisa al usuario y detente.
- Si algún mensaje viene truncado ("..."), léelo completo con: `node "C:\Users\jorge\.gemini\config\scripts\slack.js" replies C02CGD1D9NX <ts> "<scratchpad>\msg.json"` antes de transcribirlo.
- Transcribe **todos** los mensajes (standups, eventos y avisos de Jorge), en orden ascendente y sin resumir ni corregir nada, en `<scratchpad>/nuevos.json`:
  `[{"ts":"1791234567.000100","fecha":"AAAA-MM-DD HH:MM","autor":"Saulo Lopez","texto":"..."}]`
  (`fecha` es la que muestra Slack, en MST; `autor`, el nombre tal cual aparece). Valida con `node -e` que el JSON se parsea.
- Responde solo con: ruta del archivo, número de mensajes, rango de fechas y los mensajes que no pudiste leer completos. Nada del contenido.

## 3. Unir

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" unir "<scratchpad>/nuevos.json" <desde>
```

`<desde>` es el `desde` del paso 1. Lo leído sustituye a lo guardado de ese periodo: agrega lo nuevo, actualiza lo editado y quita lo que se borró en Slack.
Revisa la salida:

- `diasHabilesSinMensajes`: si no son días festivos, la lectura quedó incompleta; repite el paso 2.
- `ERROR: ... lectura incompleta`: al subagente le faltó paginar; repite el paso 2. Usa `--forzar` solo si Jorge confirma que esos mensajes se borraron.
- `porAutor`: deben aparecer los cuatro colaboradores cuando el periodo cubre días hábiles.

## Consultar la caché

| Comando | Para qué |
|---|---|
| `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" estado <desde dd/mm/aaaa> [hasta]` | Estado por colaborador y TT: último estatus, historial de cambios, si sigue en su último standup, trabajo sin TT y eventos. Lo usan `/mtto-fechas` y `/mtto-quincenal` |
| `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" mensajes <desde dd/mm/aaaa> [hasta]` | Los mensajes del periodo, tal cual (para citar un texto exacto) |
| `node "C:\Users\jorge\.gemini\config\skills\mtto-standup\scripts\revisar.js" [fecha]` | Revisión de standups: lee la caché directamente |
| `node "C:\Users\jorge\.gemini\config\skills\mtto-rendimiento\scripts\datos.js" YYYYMM` | Consolidado de rendimiento: lee la caché directamente |

Las respuestas en hilo no están en la caché: si hace falta una, léela con: `node "C:\Users\jorge\.gemini\config\scripts\slack.js" replies C02CGD1D9NX <threadTs> "<scratchpad>\hilo.json"`.
`/rcalidad` no usa la caché: busca los eventos por palabra clave en Slack, como siempre.
