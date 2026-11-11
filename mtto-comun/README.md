# mtto-comun

Datos y código que comparten las skills de Mantenimiento. No es una skill (no tiene `SKILL.md`): las demás lo usan desde sus scripts.
Debe estar en la misma carpeta que ellas (`C:\Users\jorge\.gemini\config\skills\mtto-comun`).

| Archivo | Qué es | Quién lo usa |
|---|---|---|
| `equipo.json` | Equipo (nombre, nombre corto, nombre y User ID de Slack, correo, color de la hoja quincenal), jefe, canal #mtto y copia del correo de asignación | Todas |
| `equipo.js` / `equipo.ps1` | Lectores de `equipo.json` para Node y PowerShell | `mtto-rendimiento`, `mtto-quincenal`, `rcalidad`, `mtto-aca`, `mtto-acuerdos` |
| `fechas.js` | Feriados (LFT art. 74), días hábiles y fechas de Slack | `mtto-standup`, `mtto-rendimiento`, `rfallos` |
| `feriados-extra.json` | Días no laborables de la empresa que no son feriado de la LFT | Los mismos, a través de `fechas.js` |
| `standup.js` | Parser único de los standups: línea → caso, tipo, código, etapa | `mtto-standup`, `mtto-rendimiento`, `canal.js` |
| `canal.js` + `canal.md` | Caché compartida de #mtto y cómo actualizarla | `mtto-standup`, `mtto-fechas`, `mtto-quincenal`, `mtto-rendimiento` |
| `vocabulario.md` | Cómo leer los estatus | `mtto-fechas`, `mtto-quincenal` |

## Cambios frecuentes

- **Entra o sale un colaborador:** edita `equipo.json` (UTF-8). Es el único lugar. El orden de `equipo` es el de los reportes
  (hoja quincenal y rendimiento); los acuerdos usan orden alfabético. Quedan fuera de este archivo las columnas por persona de
  `comisiones-final/scripts/concentrado.ps1` y el historial de testers de `mtto-acuerdos/references/historial.csv`.
- **Código o estatus nuevo en el standup:** `standup.js` (`CODIGOS`, `ETAPA_CODIGO`, `etapaTexto`). Las reglas de revisión
  (qué se le señala al colaborador) siguen en `mtto-standup/scripts/revisar.js`.
- **Día no laborable de la empresa** (Semana Santa, puentes, cierre de fin de año): agrégalo a `dias` de `feriados-extra.json`,
  `{ "fecha": "dd/mm/aaaa", "motivo": "..." }`. Deja de contar como día hábil en `/mtto-standup` (huecos, contadores, estancados),
  en `/mtto-rendimiento` (días de entrega y liberación) **y en `/rfallos`**, que lo descuenta del indicador 1 y lo lista en `feriadosDescontados`:
  agrega solo los días que también valgan para ese indicador. Los feriados de la LFT no se capturan: los calcula `fechas.js`.
  Pista: `/mtto-standup` lista en `diasSinRegistro` los días entre semana en que nadie publicó standup.
