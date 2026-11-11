---
name: mtto-fechas
description: 'Revisa el canal de Slack #mtto y compara los standups diarios del equipo de mantenimiento con una captura del tablero de tickets (columnas PROCESO / ENTREGADO con TT#####, responsable y fecha) para decir a qué tickets hay que moverles la fecha, cuáles revisar/cerrar y cuáles van bien. Usar cuando digan "/mtto-fechas", adjunten la imagen del tablero, o pregunten "a cuál le muevo la fecha".'
---

# Revisión de fechas del tablero vs. #mtto (/mtto-fechas)

El usuario (Jorge Gálvez, jefe de mantenimiento) invoca esta skill y adjunta una **captura del tablero**.
No hace falta que explique nada más: haz todo el flujo y entrega el resultado.

## 1. Leer la imagen

Extrae de la captura, por cada tarjeta: **columna** (PROCESO / ENTREGADO), **TT#####**, cliente/descripción corta,
**responsable** y **fecha** (formato dd/mm/aaaa). Ignora el número del círculo junto al reloj (no interpretarlo).
Si no hay imagen adjunta, pídela y detente.

## 2. Estado de los casos en #mtto

**No leas el canal tú.** Los standups salen de la caché compartida de #mtto:

1. Actualiza la caché siguiendo `C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.md` (léelo), con `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" oldest` de **hace 12 días**.
   Puedes lanzar el subagente lector **antes** de leer la imagen, para que trabaje mientras tanto.
2. Obtén el estado por colaborador y TT de esos 12 días:
   ```powershell
   node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" estado <dd/mm/aaaa de hace 12 días>
   ```
   Por cada TT trae `estatus` (el último), `fecha` (de ese standup), `etapa`, `contador`, `historial` (cambios de estatus con su fecha) y
   `enUltimo` (si sigue en el último standup de su responsable); además `ultimoStandup` por colaborador, `sinTT`, `eventos` y `rango`.
   Cómo interpretarlo: `C:\Users\jorge\.gemini\config\skills\mtto-comun\vocabulario.md`.
3. Si necesitas el texto exacto de un caso dudoso: `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" mensajes <desde> [hasta]`. Las respuestas en hilo no están en la caché: si hace falta una, léela con: `node "C:\Users\jorge\.gemini\config\scripts\slack.js" replies C02CGD1D9NX <threadTs> "<scratchpad>\hilo.json"`.

Usa el **último standup de cada responsable** como estatus vigente y el `historial` para ver la tendencia.
Un caso con `enUltimo: false` y sin etapa de cierre (`rsp`, `ldp`, `cierre`) ni `revpr` se trata como "dejó de aparecer".

## 3. Cruzar y clasificar

Hoy = fecha actual. Para cada ticket del tablero:

1. **Mover fecha**: la fecha ya pasó o es hoy, y el canal muestra que sigue abierto
   (standby, pausa, revisando, en espera de logs/respuesta, entregado sin respuesta, o sin evidencia de entrega).
2. **Revisar estatus**: la fecha ya pasó y el ticket **dejó de aparecer** en los standups, o la última
   mención fue "mandar a RSP"/"LDP"/"entrega"/"cancelado". Probablemente necesita cambiar de columna o cerrarse, no una fecha nueva
   (si se canceló, la acción sugerida es cerrarlo como cancelado en el tablero).
3. **Sin cambio**: va en tiempo, o el canal indica cierre (CEC) / siguiente paso claro. Si la fecha es futura pero
   el ticket lleva mucho tiempo pausado ("x3", "pausado"), menciónalo como riesgo.
4. **Sin información**: no aparece en el canal; dilo, no inventes.

Nunca supongas un estatus que el canal no diga; cita brevemente lo que dice el standup y de qué día.

## 4. Respuesta

En español, breve, con este formato:

- Una línea con el rango de mensajes leídos (ej. "Leí #mtto del 21/09 al 01/10").
- **Mover fecha**: tabla `Ticket (responsable) | Fecha actual | Qué dicen en el canal`, del más atrasado al menos.
- **Revisar estatus**: viñetas con la acción sugerida (pasar a Entregado, confirmar RSP o LDP, cerrar).
- **Sin cambio**: viñetas cortas.
- **Sin información** (si aplica).

No envíes mensajes a Slack ni modifiques nada: solo es lectura y recomendación. Si el usuario después pide
mandar recordatorios a los responsables, redacta el mensaje en mrkdwn y pide confirmación; con ella, guarda el texto en `<scratchpad>/recordatorio_<userId>.txt` y déjalo como borrador ejecutando con `run_command`:
`node "C:\Users\jorge\.gemini\config\scripts\slack.js" draft <userId> --file "<scratchpad>/recordatorio_<userId>.txt"`
para que Jorge lo envíe. Nunca lo envíes con `slack.js send`.
