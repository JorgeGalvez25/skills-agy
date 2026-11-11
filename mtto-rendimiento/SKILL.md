---
name: mtto-rendimiento
description: 'Genera el reporte mensual privado de rendimiento por colaborador de Mantenimiento (MMYYYY_RendimientoColaboradores.xlsx en C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Rendimiento\YYYYMM): casos atendidos por mes, días hábiles para entregar y para liberar (LDP) cambios y fallos, cumplimiento por criticidad, calidad (ORIGEN, reaperturas, REVPR, hallazgos de PR), carga de trabajo, fortalezas y dificultades por tipo, módulo, criticidad y complejidad, y mapa de conocimiento por módulo. Cruza los standups de #mtto con CambiosProceso.xlsm, las relaciones de /rfallos, los acuerdos de versión y las revisiones de /mtto-revpr. Recibe el mes como YYYYMM y se ejecuta al mes siguiente. Usar cuando digan "/mtto-rendimiento YYYYMM", "rendimiento del equipo", "rendimiento por colaborador", "cuánto tarda cada uno", "fortalezas y dificultades de cada colaborador" o "desempeño del mes".'
argument-hint: YYYYMM
---

# Rendimiento por colaborador (/mtto-rendimiento YYYYMM)

Reporte **solo para Jorge Gálvez**, para coaching: no se comparte con los colaboradores ni con Dirección. Por eso:
- nunca lo publiques, adjuntes, envíes ni lo guardes en la carpeta de Indicadores (esa carpeta va al consultor externo);
- no menciones su contenido en Slack, correos ni otros reportes;
- el mensaje fijado de #mtto dice que los eventos "evalúan al departamento": este reporte no cambia esa regla hacia el equipo.

El Excel lo crea **siempre** `scripts/generar.js`. Tu trabajo: actualizar la caché de #mtto, consolidar, resolver dudas con Jorge, generar y entregar la lectura.

- **Skill** (`$SK`): `C:\Users\jorge\.gemini\config\skills\mtto-rendimiento`. Scripts Node en `$SK\scripts` (con `xlsx` y `exceljs`). No hay Python.
- **Carpeta** (`$R`): `C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Rendimiento`. `generar.js` crea `$R\YYYYMM`.
  - Los mensajes de #mtto salen de la caché compartida (`C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\canal_mtto.json`, desde el 01/09/2026), la misma de `/mtto-standup`, `/mtto-fechas` y `/mtto-quincenal`. La anterior `$R\datos\standups.json` se copió ahí la primera vez y ya no se usa.
  - `$R\datos\atribuciones.json`: decisiones de Jorge sobre quién atendió un caso (`{"TT106583": "Miguel Armenta"}`). Persistente.
- JSON de trabajo en el scratchpad.

## Reglas

1. `YYYYMM` = mes reportado; los datos confiables empiezan en **202610** (septiembre es solo contexto). Sin argumento o con otro formato, pregunta.
2. Si la salida ya existe, pregunta antes de usar `--sobrescribir`.
3. No inventes fechas ni dueños. Lo que no se puede atribuir se le pregunta a Jorge y se guarda en `atribuciones.json` solo con su respuesta.
4. No modifiques los scripts para un mes en particular ni los archivos de origen (CambiosProceso, relaciones, acuerdos, revisiones).
5. Español con acentos; fechas `dd/mm/aaaa`. Señala datos, no califiques a la persona.

## Fuentes (qué sale de dónde)

| Dato | Fuente |
|---|---|
| Dueño del caso | `atribuciones.json` > quien lo trae en su standup (no como tester) > Desarrollador de CambiosProceso > Responsable de los acuerdos |
| Fecha de asignación | La más temprana entre la columna `Fecha asignación` de CambiosProceso (la llena `/mtto-aca`; los históricos salieron de los correos "TT##### ACA"), la asignación de VTiger de la relación de `/rfallos` y el primer standup |
| Entrega | Fallos y AP: fecha real de respuesta de VTiger (relación de `/rfallos`). Cambios: primer standup en Entregado o posterior |
| RSP | `Fecha Entrega dd/mm/aaaa` del motivo del RSP o, sin ella, el primer standup en RSP |
| LDP | Evento `LDP`/`LIBERADO` (`rcalidad/scripts/eventos.js`) o el standup en LDP |
| Criticidad y cumplimiento | Relaciones `MMYYYY_RelacionFallosAtendidos.xlsx` de todos los meses |
| Complejidad y módulos curados | `Versiones\*\Acuerdos_IGAS_RSP*.xlsx` (desde 2024) |
| Hallazgos de PR | `Versiones\*\Revision_PR\TT#####.md` (severidad de la tabla de hallazgos) |
| ORIGEN / REABIERTO / REVPR | Eventos y standups de #mtto |

El colaborador que atendió un fallo **no** sale de VTiger (la relación va al consultor y no debe llevar ese dato): sale de los standups.

## Paso 1 — Actualizar la caché de #mtto [subagente]

Sigue `C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.md` (léelo): `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" oldest 01/09/2026` (este reporte necesita la caché desde esa fecha),
el subagente lector del canal y `node "C:\Users\jorge\.gemini\config\skills\mtto-comun\canal.js" unir`. Si la caché ya cubre desde el 01/09/2026 solo se leen los últimos días.

## Paso 2 — Consolidar

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-rendimiento\scripts\datos.js" YYYYMM > "<scratchpad>/datos.json"
```

Lee la caché de #mtto y arma un registro por caso. Para reconsolidar no hace falta volver a leer Slack.
Revisa `dudas` y `eventos.noLeidos` del JSON (con `node -e`, sin volcar todo el archivo).

## Paso 3 — Resolver dudas con Jorge (ask_question, varias por llamada)

- `dudas.sinDueno`: fallos de la relación o cambios sin standup ni responsable → ¿quién lo atendió? (opciones: los 4 colaboradores; "Otro" para Jorge o alguien de fuera, que se deja sin atribuir).
- `dudas.variosDuenos`: TT en los standups de dos personas → ¿de quién es?
- `dudas.reasignados`: el Desarrollador de CambiosProceso no coincide con el del standup → solo menciónalo si cambia el dueño que eligió el script.

Escribe las respuestas en `$R\datos\atribuciones.json` (agrega, no borres las existentes) y vuelve a correr el paso 2.
`dudas.entregaAntesDeDatos` (casos que ya venían entregados antes del 01/09/2026) no se pregunta: esos casos no cuentan en los tiempos de entrega.

## Paso 4 — Generar

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-rendimiento\scripts\generar.js" YYYYMM "<scratchpad>/datos.json"
```

Crea `$R\YYYYMM\MMYYYY_RendimientoColaboradores.xlsx`:

| Hoja | Contenido |
|---|---|
| Equipo | Una fila por colaborador: atendidos (C/F/AP), nuevos, entregados, LDP, CEC, medianas de entrega y liberación, cumplimiento por criticidad, ORIGEN, reaperturas, REVPR, hallazgos de PR, carga activa y casos probados como tester |
| Saulo / Miguel / Martín / Susana | KPI del mes contra sus meses anteriores y el promedio del equipo; fortalezas y dificultades (acumulado desde 09/2026); incidencias del mes |
| Tendencia | Métricas clave por mes y colaborador |
| Módulos | Casos por módulo y colaborador (acuerdos desde 2024 + casos recientes); marca en rojo los módulos que solo conoce una persona |
| Detalle | Cada caso atendido en el mes con sus fechas por etapa, fuente de la asignación y señales de calidad (auditable) |

Definiciones (fijas en los scripts):
- Días hábiles = NETWORKDAYS inclusivo, lunes a viernes sin feriados LFT ni los días no laborables de la empresa (`mtto-comun\feriados-extra.json`). Se reporta la **mediana** (y el promedio en Equipo) porque un caso atorado distorsiona el promedio.
- **Atendido** en el mes: aparece en su standup del mes o tuvo entrega, LDP o cierre en el mes.
- **Fortaleza / dificultad** por categoría (tipo, módulo, criticidad, complejidad): índice = su mediana de días de entrega ÷ mediana del resto del equipo. Fortaleza ≤ 0.8 sin fallos fuera de objetivo; dificultad ≥ 1.25, o alguna ORIGEN o reapertura, o 2 o más fallos fuera de objetivo. Requiere 3 casos suyos y 2 del resto.
- **Carga activa**: casos propios por standup que no están en pausa, RSP ni cierre.

## Paso 5 — Verificar

Vuelca la hoja Equipo con `require('C:/Users/jorge/.gemini/config/skills/mtto-rendimiento/scripts/node_modules/xlsx')` y confirma que coincide con el `resumen` que imprime `generar.js`.

## Paso 6 — Entregar (en el chat, solo para Jorge)

1. Ruta del archivo y rango de standups leído.
2. Tabla breve por colaborador: atendidos, entregados, mediana de entrega (C y F), cumplimiento por criticidad, incidencias de calidad y carga.
3. Por colaborador, **2 o 3 puntos de conversación** para una 1:1: una fortaleza con su dato, una dificultad con su dato y el contexto que la matiza (carga, casos atorados por el cliente, muestra chica).
   Distingue lo que depende del colaborador (asignación → entrega, REVPR, hallazgos de PR) de lo que no (espera del cliente, calendario de versiones).
4. Módulos que solo conoce una persona (riesgo y oportunidad de rotar asignaciones).
5. Atribuciones hechas en el paso 3, eventos `noLeidos` y limitaciones del mes (pocas LDP porque la versión no ha salido, muestras menores a 3, casos sin título o sin módulo).
