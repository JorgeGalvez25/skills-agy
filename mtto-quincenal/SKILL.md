---
name: mtto-quincenal
description: 'Genera la hoja quincenal del reporte a dirección "Seguimiento de Casos por Desarrollador" (Casos_por_Desarrollador_mantenimiento.xlsx). Toma la última hoja del archivo, lee los standups de #mtto desde esa fecha y los títulos de CambiosProceso.xlsx, y agrega una hoja nueva (dd-mm) solo con el trabajo vigente de cada desarrollador. Usar cuando digan "/mtto-quincenal", "genera la hoja de la reunión", "reporte de casos por desarrollador" o "hoja para dirección".'
argument-hint: "[dd/mm/aaaa (default: hoy)]"
---

# Hoja quincenal para dirección (/mtto-quincenal [dd/mm/aaaa])

Jorge Gálvez (jefe de Mantenimiento) presenta cada 15 días a dirección el archivo
`C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\Casos_por_Desarrollador_mantenimiento.xlsx`: una hoja por reunión, nombrada `dd-mm`
(`31-08`, `14-09`, `28-09`, `13-10`…). La hoja muestra **en qué está trabajando actualmente** cada desarrollador.
Columnas (desde `13-10`): **Desarrollador | Caso | Estatus | Observaciones | Fecha cierre**. Las hojas anteriores a `13-10` no tienen Estatus.

- **Fecha de la hoja**: el argumento o, sin él, hoy. Nombre de la hoja: `dd-mm`.
- **Periodo**: desde la fecha de la última hoja del archivo (su nombre `dd-mm`, mismo año o el anterior si el mes es mayor) hasta el día anterior a la fecha de la hoja.

**Script:** `C:\Users\jorge\.gemini\config\skills\mtto-quincenal\scripts\hoja.js` (Node, con `exceljs` en su `node_modules`). Archivos de trabajo en el scratchpad.

## Reglas de Jorge (aplican siempre, salvo que pida otra cosa)

1. **Solo trabajo vigente.** Un caso que en el periodo quedó con estatus de cierre (CEC, RSP, LDP, LIBERADO, Cancelado/CANCELADO, Cerrado) **no se incluye**,
   aunque estuviera en la hoja anterior. Si después de RSP volvió al standup (REVPR por observaciones al PR, integración/pruebas con el tester), sí se incluye.
2. **Fecha cierre vacía** salvo que haya información para determinarla (Jorge la da o pasa una captura del tablero con la fecha). No se arrastran las fechas de la hoja anterior ni se calculan.
3. **Bloque de Jorge**: no se genera contenido. Se dejan 5 filas vacías con "Jorge" en Desarrollador y su color (lila) para que él capture (`captura` en la spec).
4. **Casos de la hoja anterior sin información en #mtto** (no se pueden ligar a ningún TT ni mención del periodo): se incluyen igual, con el texto de Caso y Observaciones de la hoja anterior,
   con el Estatus de la hoja anterior (si no tenía, `Proceso`), sin fecha y con una `nota` (comentario de celda) "Sin información en #mtto del dd/mm al dd/mm. Revisar." Jorge decide qué hacer con ellos.
5. **Trabajo sin número de caso** (actividades sin TT##### en el standup: "pendiente de caso", fallos sin TT, pilotos, apoyos sueltos): **no se incluye**,
   pero **antes de generar** pregúntale a Jorge por cada uno con `ask_question` (incluir con el texto propuesto / dejar fuera). Cursos, reuniones, documentación para la scrum, informes y eventos internos no son trabajo de caso: ignóralos sin preguntar.
6. Si la hoja `dd-mm` ya existe, pregunta antes de usar `--sobrescribir`. Nunca modifiques las hojas anteriores ni `CambiosProceso.xlsx`.

## Paso 1 — Leer la hoja anterior y los títulos

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-quincenal\scripts\hoja.js" leer "C:/Users/jorge/Dropbox/MTTO/ReportesMTTO/Casos_por_Desarrollador_mantenimiento.xlsx"
node "C:\Users\jorge\.gemini\config\skills\mtto-quincenal\scripts\hoja.js" titulos "C:/Users/jorge/Dropbox/MTTO/ReportesMTTO/CambiosProceso.xlsx"
```

`leer` devuelve las hojas existentes y las filas de la última (`dev`, `caso`, `estatus`, `obs`, `fecha`; ubica las columnas por encabezado, así que en hojas sin Estatus viene vacío). `titulos` devuelve `{TT#####: {titulo, dev, estatus}}` de los cambios.

## Paso 2 — Leer #mtto del periodo (subagente)

**No leas el canal tú.** Calcula el `oldest` y delega a un subagente (invocando `invoke_subagent` con `TypeName: "self"`, `Role: "Lector Standups Quincenal"`, `Model: "flash"`), lanzado
**en el mismo mensaje** que los comandos del Paso 1 para que corran en paralelo. Pásale los puntos de abajo y pídele que escriba
`<scratchpad>/estado_mtto.json` y responda solo con la ruta, el rango leído y cuántos standups por desarrollador:

```json
{ "rango": "28/09–12/10",
  "devs": { "Saulo": { "ultimoStandup": "2026-10-12",
    "tts": [ { "tt": "TT104919", "tipo": "C", "descripcion": "Monederos", "historial": [ ["2026-09-29", "Revisando"], ["2026-10-08", "Entregado, en espera de respuesta"] ], "enUltimo": true } ],
    "sinTT": [ { "texto": "Pendiente de caso: piloto transmisor", "desde": "2026-10-01", "hasta": "2026-10-12" } ] } },
  "eventos": [ "LDP TT106586 | CAMBIO | Petroservicios | 09/10/2026" ] }
```

`historial` registra solo los **cambios** de estatus (texto tal cual), no cada día. Tú armas el estado vigente (Paso 3) a partir de este archivo.

Instrucciones para el subagente:
- Canal **#mtto**, ID `C02CGD1D9NX`. Obtén los mensajes ejecutando:
  `node "C:\Users\jorge\.gemini\config\scripts\slack.js" history C02CGD1D9NX <oldest> 1000 "<scratchpad>/raw_mtto.json"`
  con `oldest` = timestamp Unix de la fecha de la última hoja a las 00:00 MST (UTC-7; calcúlalo con `node -e`).
  `slack.js history` se detiene al juntar el tope (1000): un `oldest` mal calculado (p. ej. error de año) trae meses de mensajes.
  Si el archivo sale con 1000 mensajes o es demasiado grande, revisa el `oldest` y acorta la ventana en lugar de procesarlo.
- Si el helper de Slack falla por el token (p. ej. error de autenticación o token expirado no renovable), avisa al usuario y detente.
- Formato de los standups: secciones **standby** y **seguimiento** con `TT#####: estatus`. Los anteriores al 08/10/2026 traen "Ayer"/"Viernes" + "Hoy": usa solo "Hoy".
  Saulo marca el tipo como `- C -` (cambio) / `- F -` (fallo); los demás escriben "Cambio"/"Fallo". Eventos aparte: `LDP`/`LIBERADO`, `REABIERTO`, `ORIGEN`; `CANCELADO TT##### | …` dentro del standup.
- Equipo: Saulo López, Miguel Armenta, Martín Reyes, Susana Gámez (los mensajes de Jorge son avisos, no standups).

## Paso 3 — Armar el estado vigente

Por desarrollador, toma su **último standup** del periodo como estatus vigente y los anteriores para ver la evolución:
- Un TT que salió del standup: su último estatus decide. Cierre → fuera (regla 1). Sin cierre → inclúyelo con su último estatus.
- Cambios, mejoras y proyectos: **una fila por TT**, con el título completo de `titulos` (`TT##### -CLIENTE-TIPO- TÍTULO`, tal cual viene). Si no hay título, usa `TT#####` + la descripción del standup y menciónalo en el resumen.
- Fallos con TT abiertos: agrúpalos en una sola fila por desarrollador, Caso = `Atención a casos de mantenimiento`, Observaciones = `TT##### <estatus breve>; TT##### <estatus breve>`.
  Si el desarrollador no tiene fallos abiertos, no lleva esa fila.
- Liga los renglones de la hoja anterior que no traían TT con su TT cuando la relación sea clara (p. ej. "Seguimiento cambio JAG multi-estación" → TT106711); si es dudosa, aplica la regla 4 y menciónalo.
- **Estatus**: etapa del caso en una o dos palabras, del catálogo que usa Jorge:
  - `En análisis`: análisis, propuesta o definición con el cliente; también si quedó en pausa hasta definir cómo implementarlo.
  - `Proceso`: asignado, en desarrollo/codificación, pruebas internas, integración con el tester o en pausa por otra prioridad.
  - `Piloto`: liberado al cliente en piloto o en pruebas en sitio.
  - `Terminado`: entregado y en espera de respuesta/visto bueno del cliente para cerrarse.
  - La fila "Atención a casos de mantenimiento" lleva `Proceso`. Si la hoja anterior tiene un valor distinto a estos para el mismo caso y no hay avance, consérvalo.
- **Observaciones**: frase breve para dirección sobre cómo está hoy y, si cambió, qué avanzó ("El cliente respondió a la propuesta; en codificación").
  Complementa al Estatus, no lo repite solo (evita Estatus `Proceso` + Observaciones "Proceso"). Sin vocabulario interno (x2/x3, CEC, RSP, SDP, "preguntar estatus") ni nombres del cliente que ya estén en el título.
- Orden: Saulo, Miguel, Martín, Susana, Jorge. Dentro de cada uno: lo que está en seguimiento activo, luego lo pausado/en espera, luego casos de la regla 4, al final "Atención a casos de mantenimiento".

## Paso 4 — Preguntar y generar

1. Pregunta por el trabajo sin TT (regla 5). Si no hay, sigue.
2. Escribe `<scratchpad>/spec_dd-mm.json`:

```json
{ "hoja": "13-10",
  "filas": [ { "dev": "Saulo", "caso": "TT104919 -EL TREBOL-FACTURACION- MONEDEROS", "estatus": "Terminado", "obs": "Entregado; en espera de respuesta del cliente" },
             { "dev": "Miguel", "caso": "Licenciamiento Tablet multi-islas", "estatus": "Proceso", "obs": "Pendiente", "nota": "Sin información en #mtto del 28/09 al 12/10. Revisar." } ],
  "captura": { "dev": "Jorge", "filas": 5 } }
```

   `estatus` va en todas las filas (Paso 3). `fecha` (AAAA-MM-DD) solo si aplica la regla 2. Las filas de captura salen con Estatus vacío. `dev` usa los nombres cortos: Saulo, Miguel, Martín, Susana (cada uno tiene su color fijo en el script).
3. Genera:

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-quincenal\scripts\hoja.js" generar "C:/Users/jorge/Dropbox/MTTO/ReportesMTTO/Casos_por_Desarrollador_mantenimiento.xlsx" "<scratchpad>/spec_dd-mm.json"
```

   Si falla porque el archivo está abierto en Excel (EBUSY/EPERM), pídele a Jorge que lo cierre y reintenta.
4. Verifica con `node "C:\Users\jorge\.gemini\config\skills\mtto-quincenal\scripts\hoja.js" leer … dd-mm` que la hoja quedó con las filas esperadas.

## Paso 5 — Resumen para Jorge (en el chat)

- Una línea: "Leí #mtto del dd/mm al dd/mm; hoja `dd-mm` agregada con N filas + 5 de captura".
- **Salieron de la hoja** (cerrados en el periodo): TT, estatus de cierre y fecha.
- **Nuevos** respecto a la hoja anterior.
- **Avances relevantes** (lo que conviene comentar en la reunión).
- **Revisar**: casos de la regla 4, títulos que no se encontraron, ligas dudosas entre renglones y TT.
