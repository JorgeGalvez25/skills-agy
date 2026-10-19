---
name: rcalidad
description: 'Genera los reportes mensuales de los indicadores 2 y 3 del Departamento de Mantenimiento — "Tasa de éxito de cambios liberados" y "Resolución definitiva de fallos" — a partir de los eventos LDP (antes LIBERADO) / REABIERTO / ORIGEN del canal de Slack #mtto y de la relación de fallos de /rfallos. Recibe el mes a reportar como YYYYMM (los casos de ese mes, con 30 días de seguimiento) y se ejecuta al mes siguiente. Crea MMYYYY_TasaExitoCambios.xlsx y MMYYYY_ResolucionDefinitivaFallos.xlsx. Usar cuando digan "/rcalidad YYYYMM", "indicadores 2 y 3", "tasa de éxito de cambios", "resolución definitiva de fallos" o "reaperturas del mes".'
argument-hint: YYYYMM
---

# Indicadores 2 y 3 — Calidad de entregas (/rcalidad YYYYMM)

Generas la evidencia mensual de dos indicadores del jefe de Mantenimiento (Jorge Gálvez):

| # | Indicador | Peso | Fórmula | Matriz |
|---|---|---|---|---|
| 2 | Tasa de éxito de cambios liberados | 15% | Cambios sin fallo atribuible ÷ cambios liberados × 100 | EXCELENTE ≥ 98% · BUENO 95–97.99% · REGULAR 90–94.99% · NO ACEPTABLE < 90% |
| 3 | Resolución definitiva de fallos | 25% | Fallos sin reapertura ni recurrencia ÷ fallos cerrados × 100 | EXCELENTE ≥ 97% · BUENO 93–96.99% · REGULAR 85–92.99% · NO ACEPTABLE < 85% |

Los Excel los crea **siempre** `scripts/generar.js`. Tu trabajo es: leer el canal, convertir los mensajes en eventos con `scripts/eventos.js`,
resolver dudas con el usuario, ejecutar el generador, verificar y reportar.

**Carpeta de la skill** (`$SK`): `C:\Users\jorge\.gemini\config\skills\rcalidad`. Scripts en `$SK\scripts` con sus dependencias (`xlsx`, `exceljs`).
**Carpeta raíz** (`$RAIZ`): `C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Indicadores`.
No hay Python: todo se ejecuta con `node` desde la herramienta Bash con rutas absolutas. Los JSON de trabajo van en el scratchpad, nunca en la carpeta del mes.

## Reglas que no se negocian

1. **Argumento:** `YYYYMM` = mes que se reporta y se evalúa (misma carpeta que `/rfallos`). Se ejecuta al mes siguiente: en octubre, `/rcalidad 202609` evalúa lo liberado y lo atendido en septiembre. Si falta o tiene otro formato, pregunta.
2. **Ventana de seguimiento:** 30 días naturales desde la fecha base (fecha de la LDP del cambio o fecha real de respuesta del fallo), inclusive, cortada a la fecha de ejecución. Los casos de fin de mes tienen seguimiento parcial; la fecha de corte se informa solo en el chat, no en el Excel.
3. **Fuente:** los eventos del canal #mtto (formato de `GUIA_CANAL.md`) y la relación de `/rfallos` del mismo mes. Nunca inventes un evento. Lo que no está registrado no cuenta, salvo que el usuario lo confirme en el chat.
4. **Sin reacciones de validación:** todo evento bien escrito cuenta. Las dudas (ver paso 4) se resuelven preguntando al usuario antes de generar.
5. **No crees carpetas ni sobrescribas.** Si la carpeta del mes no existe o las salidas ya existen, pregunta. Usa `--sobrescribir` solo con autorización explícita.
6. **Integridad:** no quites eventos para mejorar el resultado. Un evento se descarta solo si el usuario lo decide (p. ej. es una solicitud nueva y no un defecto) y debe mencionarse en la entrega.
7. No modifiques los scripts para un mes en particular. Español con acentos; fechas `dd/mm/aaaa`.

## Definiciones

- **Cambio evaluable (ind. 2):** un TT de tipo CAMBIO o MEJORA con un mensaje `LDP` cuya fecha (la del correo de LDP del tester) cae en el mes reportado. Un TT = un cambio; si hay varios se usa el primero.
  Los `LIBERADO` publicados antes del 09/10/2026 (fecha de instalación) se leen igual que un LDP de cambio.
- **LDP de fallos** (`LDP TT##### | FALLO | ...`): `eventos.js` los devuelve en `fallosLdp`. No cambian el ind. 3, cuyo universo y fecha base salen de `/rfallos`; sirven para cruzar contra la relación.
- **Fallo evaluable (ind. 3):** cada caso del detalle de `$RAIZ\YYYYMM\MMYYYY_RelacionFallosAtendidos.xlsx` (salida de `/rfallos`, ya sin cancelados). Fecha base = "Fecha real de respuesta".
- **Incidencia:** hay un `REABIERTO` del mismo TT o un `ORIGEN TT_nuevo <- TT_evaluado` en la ventana. Con una basta para que el caso quede en "No".
  - **Cambios:** la reapertura ocurre cuando el caso pasa de RSP (Revisión SCRUM Pendiente), CEC o Cancelado a revisión (desde el 16/10/2026; antes también de Entregado), es decir, **antes** de la LDP; después de la LDP ya no se reabre (un problema nuevo es otro TT, con ORIGEN). Por eso cuenta cualquier REABIERTO u ORIGEN anterior a la LDP más los 30 días posteriores.
  - **Fallos:** los 30 días posteriores a la fecha real de respuesta.
- `ORIGEN` sirve para ambos indicadores: si el TT anterior es un cambio, cuenta en el 2; si es un fallo, en el 3.

## Paso 1 — Preparar

```bash
node "C:/Users/jorge/.gemini/config/skills/rcalidad/scripts/preparar.js" YYYYMM
```

Devuelve `mes`, `periodo`, `finSeguimiento`, `corte`, `seguimientoCompleto`, `slack` (canal y fechas `after`/`before` para buscar),
`salidas` (y si existen), `fallos` (universo del ind. 3) y `avisos`.

- `ERROR:` → muéstralo y detente.
- `seguimientoCompleto: false` es lo normal (se ejecuta a inicios del mes siguiente): menciónalo en la entrega con la fecha de corte; no hace falta preguntar.
- Sin relación de `/rfallos` del mes → propón correr primero `/rfallos YYYYMM`. Si eso no es posible (meses anteriores a 202609), ve a **Transición**.

## Delegación (ahorro de tokens)

Las búsquedas en Slack son lo que más tokens consume y no requieren criterio fino: **delégalas**; tú conservas las decisiones (paso 4), la generación y la entrega.

| Tarea | Subagente (`invoke_subagent`) | Devuelve |
|---|---|---|
| Paso 2: búsquedas de eventos y `mensajes.json` | `TypeName: "self"`, `Role: "Buscador de Eventos Slack"`, `Model: "flash"` | Ruta del archivo, mensajes por palabra clave, truncados que no pudo completar |
| Paso 3: barrido de control | `TypeName: "self"`, `Role: "Barrido de Control Slack"`, `Model: "pro"`; si son más de 25 TT, divídelos en lotes de ~15 y lanza los agentes **en paralelo** | Solo los sospechosos: TT, fecha, autor, cita textual (≤ 2 líneas) y ts; más la lista de TT revisados sin hallazgo (solo IDs) |

Pásale a cada subagente el texto completo de su paso, los datos de `preparar.js` que necesita (`slack.*`, lista de TT con su fecha base) y la ruta del scratchpad.
Lanza el subagente del paso 2 en cuanto tengas la salida del paso 1. El del paso 3 necesita la lista de cambios del mes (sale de `datos.json`).
Verifica tú cada sospechoso antes de preguntarle a Jorge (lee su ts con el helper de Slack o scripts). Nunca descartes un evento etiquetado por lo que diga un subagente.

## Paso 2 — Leer los eventos del canal [subagente]

Canal **#mtto**, privado, ID `C02CGD1D9NX`. Ejecuta con `run_command` el helper de Slack (`slack.js search` o búsquedas por palabra clave):
`node "C:\Users\jorge\.gemini\config\scripts\slack.js" search "<query>" "<scratchpad>\<archivo>.json"`

- Palabras clave: `"LDP"`, luego `"LIBERADO"` (eventos publicados antes del 09/10/2026), `"REABIERTO"` y `"ORIGEN"`
- La guía de registro es el mensaje fijado del 07/10/2026 (ts `1791397394.905699`); sus ejemplos llevan prefijo y no son eventos. Si aparece en los resultados, ignóralo.
- La búsqueda de `LDP` también trae standups ("en espera de LDP", `TT#####: LDP`). `eventos.js` solo toma las líneas que **empiezan** con la clave; el resto se ignora.

Guarda **todos** los mensajes encontrados, tal cual, en `<scratchpad>/mensajes.json`:

```json
[{"ts":"1791234567.000100","autor":"Saulo Lopez","texto":"LDP TT106586 | CAMBIO | Petroservicios | 09/10/2026"}]
```

Después (tú, con el archivo que escribió el subagente):

```powershell
node "C:\Users\jorge\.gemini\config\skills\rcalidad\scripts\eventos.js" "<scratchpad>/mensajes.json" > "<scratchpad>/datos.json"
```

Devuelve `cambios`, `fallosLdp`, `reaperturas`, `origenes`, `noLeidos` (líneas con la palabra clave mal escritas) y `avisos`.

## Paso 3 — Barrido de control (menciones sin etiqueta) [subagente]

Para detectar reaperturas que no se registraron con el formato, busca cada TT evaluado (fallos del paso 1 y cambios del mes) en el canal:
`keywords: ["TT######"]`, `filters: "in:<#C02CGD1D9NX> after:<día anterior a su fecha base> before:<fecha base + 31 días>"` (para los cambios, `after:<slack.afterIncidencias>`), `content_types: "messages"`, `include_context: false`, `response_format: "concise"`.

Márcalo como **sospechoso** solo si una mención **posterior a la fecha base** (en los cambios, cualquiera hasta 30 días después de su LDP) indica que el problema regresó o la corrección no funcionó
("reabre", "regresó", "otra vez", "de nuevo", "nuevamente", "persiste", "sigue fallando", "no quedó", "lo rechazaron", "volvió a").
Que el TT siga en los standups como "Entregado, en espera de respuesta", "RSP" o "CEC" **no** es reapertura.
Sí es reapertura que el caso pase de RSP, CEC o Cancelado a revisión o desarrollo (desde el 16/10/2026). Que pase de Entregado a revisión no lo es (antes del 16/10/2026 sí contaba). Una vez iniciadas las pruebas (SDP, tester, integración) no hay reapertura: lo que encuentre el tester se corrige en el mismo TT hasta la LDP. No marques sospechosos en ese tramo.

## Paso 4 — Resolver dudas con el usuario (ask_question, varias por llamada)

Pregunta antes de generar sobre:
- cada línea de `noLeidos` (qué quiso decir; corrige el evento en `datos.json` solo con su respuesta);
- cada sospechoso del paso 3 (¿se agrega como REABIERTO/ORIGEN?);
- `ORIGEN` cuya causa parezca un problema distinto o una solicitud nueva (la guía dice que eso no es reincidencia);
- `LDP` (o `LIBERADO`) de CAMBIO o MEJORA de un TT que también está en la relación de fallos (¿es cambio o corrección de fallo?).

Si el usuario confirma un evento no etiquetado, agrégalo a `datos.json` con `"autor": "confirmado por Jorge"`.
Los comentarios generales (transición, eventos confirmados, baja muestra) se informan solo en el chat; los reportes no llevan observaciones.

## Paso 5 — Generar

```bash
node "C:/Users/jorge/.gemini/config/skills/rcalidad/scripts/generar.js" YYYYMM "<scratchpad>/datos.json"
```

(`--sobrescribir` como tercer argumento solo con autorización.) Crea en `$RAIZ\YYYYMM`:

- **`MMYYYY_TasaExitoCambios.xlsx`** — detalle `Caso | Tipo | Cliente | Fecha de liberación | Fin de seguimiento (=D+30) | Incidencia atribuible | Fecha de incidencia | Sin fallo (=IF(F="","Sí","No"))`, y debajo el resumen: periodo evaluado, cambios evaluables, sin fallo, tasa de éxito y clasificación (fórmulas).
- **`MMYYYY_ResolucionDefinitivaFallos.xlsx`** — detalle `Título | Criticidad | Fecha real de respuesta | Fin de seguimiento | Reapertura o recurrencia | Fecha | Sin reapertura`, resumen por criticidad P1–P4 (`COUNTIF`/`COUNTIFS`), total, clasificación y periodo evaluado.

Ninguno lleva fecha de corte ni observaciones. Ambos usan el estilo de `/rfallos`: hoja `Worksheet`, horizontal, encabezados con relleno `#4F81BD` y texto blanco, fechas `dd/mm/yyyy`.
La consola devuelve un JSON con los resultados, los casos con incidencia, `cambiosFueraDePeriodo` y `eventosSinCasoEvaluado`.

## Paso 6 — Verificar

Vuelca ambos xlsx con `require('C:/Users/jorge/.gemini/config/skills/rcalidad/scripts/node_modules/xlsx')` y confirma que las filas de detalle y los totales coinciden con el JSON de salida.

## Paso 7 — Entregar (en el chat, breve)

1. Rutas de los dos archivos, periodo evaluado y fecha de corte (y que los casos de fin de mes tienen seguimiento parcial).
2. **Ind. 2:** X de N cambios sin fallo = P%, CLASIFICACIÓN; tabla de los que fallaron (TT, liberación, incidencia).
3. **Ind. 3:** X de N fallos sin reapertura = P%, CLASIFICACIÓN; tabla por criticidad y lista de reabiertos/recurrentes. Menciona los `fallosLdp` que no estén en la relación de `/rfallos`.
4. Eventos descartados o confirmados en el chat, `noLeidos` sin resolver, `eventosSinCasoEvaluado` y `cambiosFueraDePeriodo`.
5. Si hubo mensajes mal escritos, sugiere un recordatorio para el equipo citando `GUIA_CANAL.md` (no lo envíes sin autorización).

## Transición (reportes 202609 y anteriores)

El formato de eventos empezó a usarse el 07/10/2026 (con LIBERADO; desde el 09/10/2026, LDP); septiembre no tiene mensajes de eventos. Para meses sin eventos registrados haz lo posible y márcalo:
- **Universo de fallos** sin relación de `/rfallos`: arma `"fallos"` en `datos.json` (`[{tt, titulo, criticidad, fecha}]`) con los archivos del mes
  (`*RelacionFallosAtendidos_NoUrgentes.xlsx` y `*_Urgentes.docx`); criticidad `"S/C"` si no existe.
- **Universo de cambios:** reconstrúyelo con los TT de cambio/mejora del informe de encuestas de cambios del mes y los standups (entregas, CEC). Confirma la lista y las fechas con el usuario.
- Haz el barrido del paso 3 para todos y confirma cada sospechoso.
- En la entrega del chat aclara que es periodo de transición y qué eventos se reconstruyeron o confirmaron.
