---
name: mtto-fechas
description: 'Revisa el canal de Slack #mtto y compara los standups diarios del equipo de mantenimiento con el tablero de fallos (columnas PROCESO / ENTREGADO con TT#####, responsable y fecha promesa), que lee en vivo de VTiger o de una captura, para decir a qué tickets hay que moverles la fecha, cuáles revisar/cerrar y cuáles van bien; también cruza los correos de los casos (entregas, RSP, CEC, LDP, cambios de ID) como evidencia y, con aprobación de Jorge, mueve las fechas en VTiger. Usar cuando digan "/mtto-fechas", adjunten la imagen del tablero, o pregunten "a cuál le muevo la fecha".'
---

# Revisión de fechas del tablero vs. #mtto (/mtto-fechas)

El usuario (Jorge Gálvez, jefe de mantenimiento) invoca esta skill, con o sin **captura del tablero**, o con una lista de TT.
No hace falta que explique nada más: haz todo el flujo y entrega el resultado.

## 1. Leer el tablero

El tablero es el de fallos de VTiger: **PROCESO** = estatus fallo `Revisión` (fecha = promesa de entrega, `cf_1229`) y **ENTREGADO** = `Entregado` (fecha = promesa de respuesta, `cf_1078`).

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" promesas
```

Devuelve por tarjeta `columna`, `caso`, `soporte` (ID de soporte, `cf_1275`), `titulo`, `tipo`, `responsable`, `fecha` (AAAA-MM-DD), `entrega` y `accion` (la de `mover` para cambiar su fecha).
Úsalo siempre: es el tablero vigente. Credenciales en `C:\Users\jorge\.mtto\vtiger.json`; nunca las muestres.

- **Con captura:** extrae de la imagen, por tarjeta, columna, TT#####, responsable y fecha (dd/mm/aaaa); ignora el número del círculo junto al reloj.
  Contrasta con `promesas` y menciona las diferencias (tarjeta que ya no está, fecha distinta).
- **Con una lista de TT:** `vtiger.js casos TT##### TT#####` y revisa solo esos.
- Si VTiger falla y no hay captura, pídela y detente.

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

## 2b. Correos de los casos

1. Actualiza la caché de correos (sin argumentos; puedes lanzarla en paralelo con el subagente lector del canal).
   Si Outlook falla, avisa y sigue solo con el canal:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jorge\.gemini\config\skills\mtto-comun\correos.ps1"
   ```
2. Consúltala con los mismos 12 días:
   ```powershell
   node "C:\Users\jorge\.gemini\config\skills\mtto-comun\correos.js" estado <dd/mm/aaaa de hace 12 días>
   ```
   Por TT usa `casos[TT].ultimo` (último correo propio: tipo, fecha, asunto), `sinRespuesta` (entrega o estatus sin respuesta posterior; se apaga con una respuesta externa o con un RSP, CEC o LDP posterior), `soporte` (ID anterior de soporte)
   y `atiendeCon` (TT con el que sigue el trabajo tras un CEC). A nivel global, `cambiosId` (`antes` → `nuevo`) y `anomalias` (ruta de entrega de otro TT).

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

El canal sigue siendo la fuente del estatus; el correo lo confirma o lo contradice:

- **Entregado por correo y `sinRespuesta`**: refuerza "Mover fecha" (en espera de respuesta); cita la fecha del correo de entrega.
  Si hubo respuesta del cliente o soporte después de la entrega, menciónalo.
- **Correo `cec`, `rsp` o `ldp` del caso**: "Revisar estatus" (cerrar, pasar a Entregado, confirmar RSP/LDP), aunque el standup no lo diga todavía; señala la discrepancia con el standup.
- **CEC con `atiendeCon`**: la tarjeta se cierra y el trabajo sigue en el otro TT; di cuál.
- **ID de soporte:** el standup o el correo pueden traer el caso con su `soporte` de VTiger en lugar del definitivo; búscalo con los dos.
- **TT de la tarjeta que en `cambiosId` es el ID de soporte (`antes`)**: indica el ID definitivo (`nuevo`), busca el estatus con ese ID y sugiere actualizar la tarjeta.
- **Nada en el canal pero con correos**: ya no es "Sin información"; usa el último correo como evidencia.
- **`anomalias`** de TT del tablero: menciónalas aparte.

VTiger también es evidencia:

- **Tarjeta de PROCESO con `entrega`** (`cf_1076`): la corrección ya se entregó; va en "Revisar estatus" (pasar a Entregado con la fecha de `entrega`).
- **Tarjeta sin `fecha`**: va en "Mover fecha" con la fecha propuesta, aunque el canal diga que va bien.
- **Comentarios del caso:** para las tarjetas de "Mover fecha", "Revisar estatus" y "Sin información", lee los comentarios con `vtiger.js caso TT#####`. Un comentario posterior al último standup o correo (el cliente respondió, soporte pidió cerrar, se espera información) es evidencia: cítalo con fecha y autor. Con un comentario, el caso ya no es "Sin información".
- **`responsable` distinto** de quien lo trae en su standup (salvo como tester): menciónalo en "Revisar estatus" para reasignar.

Nunca supongas lo que el canal, el correo o VTiger no digan; cita brevemente lo que dice el standup y de qué día, del correo tipo, fecha y asunto, y del comentario fecha y autor.

## 4. Respuesta

En español, breve, con este formato:

- Una línea con el origen del tablero y el rango leído (ej. "Tablero de VTiger: 9 tarjetas. Leí #mtto del 21/09 al 01/10 y correos del 21/09 al 01/10").
- **Mover fecha**: tabla `Ticket (responsable) | Fecha actual | Fecha propuesta | Qué dicen en el canal | Correo o comentario`, del más atrasado al menos.
- **Revisar estatus**: viñetas con la acción sugerida (pasar a Entregado, confirmar RSP o LDP, cerrar).
- **Correos que contradicen el standup** (si aplica): viñetas cortas, también las `anomalias`.
- **Sin cambio**: viñetas cortas.
- **Sin información** (si aplica).

En "Mover fecha" propón la fecha nueva (día hábil futuro, según lo que diga el canal) y termina preguntando cuáles se aplican.

## 5. Aplicar en VTiger (solo con aprobación)

Cuando Jorge apruebe fechas o cambios de estatus, aplícalos con el flujo de `C:\Users\jorge\.gemini\config\skills\vtiger\SKILL.md` (léelo: simular, confirmar, ejecutar, revisar `despues`):

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" mover TT##### promesa-entrega fecha=AAAA-MM-DD     # PROCESO
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" mover TT##### promesa-respuesta fecha=AAAA-MM-DD   # ENTREGADO
```

- Simula todas, muéstralas en una tabla (caso, columna, fecha actual → nueva) y pide **una** confirmación para el lote; después repite cada una con `--confirmar`.
- La fecha debe ser futura. `promesa-entrega` recalcula también la promesa de respuesta (4 días hábiles después, sin feriados).
- Los cambios de estatus que salgan de "Revisar estatus" (`entregado`, `terminado`, `cerrado`, `cancelado`, `regresa-en-proceso`) van igual, uno por uno con su confirmación.
- Al final, da la ruta del log `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\vtiger_escrituras.log`.

Nunca envíes mensajes a Slack. Si el usuario después pide
mandar recordatorios a los responsables, redacta el mensaje en mrkdwn y pide confirmación; con ella, guarda el texto en `<scratchpad>/recordatorio_<userId>.txt` y déjalo como borrador ejecutando con `run_command`:
`node "C:\Users\jorge\.gemini\config\scripts\slack.js" draft <userId> --file "<scratchpad>/recordatorio_<userId>.txt"`
para que Jorge lo envíe. Nunca lo envíes con `slack.js send`.
