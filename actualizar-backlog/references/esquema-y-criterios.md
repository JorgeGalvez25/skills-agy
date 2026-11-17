# Esquema y Criterios del Backlog

## 1. Los 9 dispositivos (orden fijo)

En la matriz `m` de `backlog_consolas.html` y en las columnas `G:O` de la hoja `Compatibilidad`:

1. `PS5` (col G)
2. `Xbox Series X` (col H)
3. `Nintendo Switch 2` (col I)
4. `Nintendo Switch Lite` (col J)
5. `PC` (col K)
6. `ROG Ally` (col L)
7. `Nintendo 2DS XL` (col M)
8. `PS Vita` (col N)
9. `Trimui Brick` (col O)

## 2. Valores válidos en la matriz de compatibilidad

- `Sí`: jugable y confirmado de forma nativa o por retrocompatibilidad directa.
- `Sí*`: jugable con matiz (modo portátil en Switch Lite, retrocompatibilidad Switch 1 en Switch 2, emulación legal en Trimui Brick, etc.).
- `Sí, cuando esté disponible` / `Sí, cuando esté disponible*`: anunciado / por lanzar para esa plataforma.
- `Revisar`: caso ambiguo o sin fuente clara.
- `No`: sin ruta de juego en ese dispositivo.

## 3. Reglas de la hoja `Criterios`

- **PS5**: `Sí` si existe versión PS5 o PS4 (retrocompatibilidad, salvo excepciones oficiales).
- **Xbox Series X**: `Sí` si existe versión Series X|S o Xbox One. Xbox 360 / Original Xbox solo si es retrocompatible oficial.
- **Nintendo Switch 2**: `Sí` si existe versión Switch 2; `Sí*` si solo tiene versión Switch 1 compatible.
- **Nintendo Switch Lite**: `Sí*` si existe en Nintendo Switch (1) y no es exclusivo de Switch 2 ni requiere TV/Joy-Con obligatorios.
- **PC**: `Sí` si existe versión PC/Windows.
- **ROG Ally**: `Sí` si existe versión PC con soporte de mando (completo o parcial); si es solo teclado y mouse, `No`.
- **Nintendo 2DS XL**: `Sí` para Nintendo 3DS y Nintendo DS. GBA no cuenta.
- **PS Vita**: `Sí` para PS Vita nativa; PSP digital compatible solo `Sí*`, no UMD.
- **Trimui Brick**: `Sí*` para retro/emulación legal probable (SNES, GBA, PS1); N64/DS quedan en `Revisar`.

## 4. Valores de `Estado` (col S en `Compatibilidad`, campo `s` en JS)

- `Disponible o ya lanzado`
- `Disponible o ya lanzado (Switch 2 pendiente)`
- `Por lanzar (<fecha>, ej. 5 nov. 2026)`
- `<año> / confirmar fecha exacta` (ej. `2026 / confirmar fecha exacta`, `2027 / confirmar fecha exacta`)
- `Por anunciar / TBA`

## 5. Estructura JSON de `const GAMES` en `backlog_consolas.html`

Cada elemento del arreglo tiene las llaves:
- `o` *(int)*: Orden Backlog (`1` = más reciente en `backlog.html`).
- `t` *(str)*: Título oficial (coincidente con `backlog.html`).
- `y` *(int | str)*: Año de lanzamiento (o previsto).
- `d` *(str)*: Desarrollador.
- `p` *(str)*: Plataformas separadas por coma (ej. `PC, PS5, Xbox Series X|S`).
- `h` *(str)*: Duración promedio estilo HLTB (ej. `18h`, `12h`, `N/A`).
- `m` *(list[str], len 9)*: Compatibilidad en los 9 dispositivos en el orden de la sección 1.
- `b` *(str)*: Mejor opción (`PC`, `PS5`, `Xbox Series X`, `Nintendo Switch 2`, etc., o `Revisar`).
- `n` *(list[str])*: Notas por dispositivo (`PS5: ...`, `Xbox: ...`, `Switch 2: ...`, `Switch Lite: ...`, `PC: ...`, `ROG: ...`). En Excel se unen con `" | "`.
- `s` *(str)*: Estado.
- `img` *(str)*: Código de portada IGDB extraído de `backlog.html` (ej. `coajye`).
- `add` *(str)*: Fecha en que se añadió al archivo (`YYYY-MM-DD`).
- `tag` *(str)*: Etiqueta opcional (habitualmente `""`).
- `cs` *(list[str], len 4)*: `[Cross-save?, Cross-save type, Scope, Notes]`.
- `bo` *(list[str], len 4, opcional)*: Solo si aplica revisión en `Switch 2 Boost`: `[Tipo en Switch, Cómo corre en Switch 2 Handheld Boost, FPS / resolución esperada, Veredicto]`.
- `na` *(list[str], len 2, opcional)*: Solo si está en `Boost - No Aplica`: `[Motivo, Nota]`.
- `ext` *(list[str], opcional)*: URLs de portada de respaldo si existían.

## 6. Hojas del libro Excel

1. `Dashboard`: Resumen general, conteos por dispositivo (`=COUNTIF('Compatibilidad'!K2:K<N+1>,"*Sí*")`) y lista de revisión manual. Las celdas se ubican por su etiqueta en la columna B; la lista `REVISAR MANUALMENTE` debe ser la última sección de la hoja.
2. `Compatibilidad`: Tabla maestra ordenada por `Orden Backlog` ascendente (`1..N`). Columnas `A:U` (21 columnas). Cada hoja de datos es una tabla de Excel cuyo rango termina en la última fila de datos.
3. `Backlog`: Resumen del backlog ordenado por `Orden Backlog` ascendente (`1..N`). Columnas `A:G` (7 columnas).
4. `Switch 2 Boost`: Juegos con versión Switch 1 (o Cloud/Switch 2 Edition relacionada), ordenados por `# Backlog` ascendente. Columnas `A:L` (12 columnas).
5. `Cross-Save`: Todos los juegos ordenados por `# Backlog` ascendente, más una fila vacía y la fila de nota al pie al final. Columnas `A:K` (11 columnas).
6. `Boost - No Aplica`: Juegos sin versión Switch 1 nativa aplicables a esa lista, ordenados por `# Backlog` ascendente. Columnas `A:G` (7 columnas).
7. `Resumen Boost`: Fecha de revisión y totales de `Switch 2 Boost` / `Boost - No Aplica`.
8. `Criterios`: Reglas de evaluación (solo lectura).
