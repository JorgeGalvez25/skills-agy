---
name: actualizar-backlog
description: >-
  Actualiza el backlog de videojuegos de Jorge sincronizando el HTML oficial exportado de Backloggd con el visor interactivo HTML (backlog_consolas.html) y el libro Excel de compatibilidad (game_backlog_compatibilidad_consolas.xlsx). Elimina los juegos que ya no están en el HTML base, unifica títulos, investiga en la web los juegos nuevos y los pendientes por lanzar o en revisión, y mantiene todas las hojas del Excel y el HTML sincronizados. Usar cuando digan "/actualizar-backlog", "actualiza mi backlog", "sincroniza el backlog" o proporcionen la ruta de backlog.html.
---

# Actualizar Backlog de Videojuegos

Sincroniza la lista oficial guardada desde Backloggd (`backlog.html`) contra el visor web autónomo (`backlog_consolas.html`) y el libro Excel multihoja (`game_backlog_compatibilidad_consolas.xlsx`).

## Rutas y parámetros

El usuario puede invocar la skill con 0, 1, 2 o 3 rutas:

1. **HTML base oficial** (opcional, por defecto: `C:\Users\jorge\Desktop\backlog.html`)
2. **HTML visor a actualizar** (opcional, por defecto: `G:\Mi unidad\backlog_consolas.html`)
3. **Excel a actualizar** (opcional, por defecto: `G:\Mi unidad\game_backlog_compatibilidad_consolas.xlsx`)

Si el usuario pasa una sola ruta, corresponde al **HTML base oficial** y los otros dos mantienen sus rutas por defecto.

## Paso 1: Inspección y validación previa

Ejecuta el script en modo `inspect` pasando las rutas correspondientes (o sin flags si aplican las rutas por defecto):

```powershell
python C:\Users\jorge\.gemini\config\skills\actualizar-backlog\scripts\sync_backlog.py inspect --base "<BASE_HTML>" --html "<CONSOLAS_HTML>" --excel "<EXCEL>" --out "<SCRATCH_DIR>\inspect.json"
```

Revisa el JSON devuelto:

- **Warnings:**
  - `WARNING_TRUNCATED_BASE`: Si `backlog.html` tiene menos de 50 juegos o cayó más de 30% respecto al backlog actual, **detente y avisa al usuario** para confirmar que guardó la página completa antes de eliminar nada.
  - `WARNING_DUPLICATED_TITLES`: Dos juegos con el mismo nombre en `backlog.html`; el script no puede distinguirlos. Avisa y detente.
  - `WARNING_EXCEL_JS_MISMATCH`: El visor y el Excel ya estaban descuadrados (`excel_not_in_js` / `js_not_in_excel`); `apply` se detendrá hasta corregirlo. Muéstralo y pregunta cómo resolverlo antes de seguir.
- **Coincidencias dudosas (`fuzzy_matches_base_vs_html`):** Para cada candidato (`source` = título en Backloggd, `target` = título actual), pregunta al usuario si es el mismo juego:
  - Si es el mismo juego → `"unify_titles": {"<target>": "<source>"}`.
  - Si es un juego distinto → `<target>` va a `remove` y `<source>` va a `add` (usando el `img` de `base_item`), investigándolo como juego nuevo.
- **Confirmación de bajas (`to_remove`):** Si `to_remove` contiene juegos a eliminar, muestra un resumen breve al usuario (altas detectadas, bajas propuestas, unificaciones y empates dudosos) y confirma antes de aplicar eliminaciones, salvo que el usuario ya haya autorizado aplicar todo directo.
- **Unificaciones de título:** Los pares en `title_unifications` (p. ej. diferencias menores entre Excel y el nombre oficial en Backloggd) quedan alineados automáticamente al título oficial de `backlog.html` cuando se ejecuta `apply`.

## Paso 2: Investigación web obligatoria

Lee [esquema-y-criterios.md](C:/Users/jorge/.gemini/config/skills/actualizar-backlog/references/esquema-y-criterios.md) antes de preparar fichas nuevas o actualizaciones.

Investiga directamente con `search_web` (puede hacerse en llamadas paralelas; no delegar búsquedas web al subagente `research` porque no tiene acceso a red):

1. **Juegos nuevos (`to_add`):**
   - Año de lanzamiento (`y`), estudio desarrollador (`d`), plataformas confirmadas (`p`), duración promedio estilo HowLongToBeat (`h`, o `"N/A"` si aún no sale), estado de lanzamiento (`s`).
   - Compatibilidad en los 9 dispositivos (`m`) y notas breves por plataforma (`n`) aplicando estrictamente las reglas de `Criterios`, más la mejor opción (`b`).
   - Cross-save real entre ecosistemas (`cs`: `[cross_save?, tipo, alcance, notas]` y `url` de soporte si aplica).
   - Switch 2 Handheld Mode Boost (`bo`) si tiene versión nativa de Switch 1 (o `na` para `Boost - No Aplica` si es exclusivo/nativo Switch 2 u otro caso documentado; si no tiene relación con Switch 1/2, omitir ambos).
   - Conservar `img` y el orden tal como vienen en `to_add` desde `backlog.html`.

2. **Juegos pendientes o en revisión (`pending_and_review`):**
   - Revisa todos los juegos listados con estado distinto de `"Disponible o ya lanzado"` (`Por lanzar...`, `2026 / confirmar fecha exacta`, `Switch 2 pendiente`, etc.) o con `"Revisar"` en algún dispositivo.
   - Verifica en la web si ya salieron, si ya tienen fecha exacta confirmada, o si se confirmó/canceló alguna plataforma (p. ej. versión Switch 2).
   - Si ya salieron, cambia `s` a `"Disponible o ya lanzado"` (o el estado vigente), actualiza `"Sí, cuando esté disponible"` a `"Sí"` (o `"Sí*"`), ajusta `y` si cambió el año, actualiza `p`, `n`, `h`, `cs` y `bo`/`na` según corresponda. No incluyas en `update` juegos cuya información siga idéntica.

## Paso 3: Aplicar cambios y verificar

Genera un archivo `changes.json` en `<SCRATCH_DIR>\changes.json` con la estructura:

```json
{
  "remove": ["Título exacto a eliminar"],
  "update": [
    {
      "t": "Título exacto",
      "s": "Disponible o ya lanzado",
      "m": ["Sí", "Sí", "Sí", "No", "Sí", "Sí", "No", "No", "No"],
      "n": ["PS5: ...", "PC: ..."]
    }
  ],
  "add": [
    {
      "t": "Título oficial de backlog.html",
      "y": 2026,
      "d": "Estudio",
      "p": "PC, PS5, Xbox Series X|S",
      "h": "N/A",
      "m": ["Sí, cuando esté disponible", "Sí, cuando esté disponible", "No", "No", "Sí, cuando esté disponible", "Sí, cuando esté disponible", "No", "No", "No"],
      "b": "PC",
      "n": ["PS5: ...", "Xbox: ...", "PC: ...", "ROG: ..."],
      "s": "2026 / confirmar fecha exacta",
      "img": "coajye",
      "tag": "",
      "cs": ["No confirmado", "Nube por ecosistema / storefront", "Steam/Epic/GOG, PS Plus, Xbox Cloud o NSO por separado", "Notas."],
      "bo": null,
      "na": null
    }
  ]
}
```

*(Opcionalmente incluye `"unify_titles": {"Nombre actual": "Nombre oficial"}` si hubo casos que no coincidieron por normalización automática).*

Notas de formato en `changes.json`:
- `cs` en `add` puede ser lista `[cross_save?, tipo, alcance, notas]` o un objeto con `cs_q`, `cs_type`, `scope`, `confidence`, `notes` y `url`; en `update` es un objeto con solo las llaves que cambian.
- `bo` es una lista `[tipo, cómo corre, FPS/resolución, veredicto]`, y opcionalmente `confianza`, `notas` y `url`, o un objeto con `tipo`, `como_corre`, `fps`, `veredicto`, `confianza`, `notas` y `url`. En `update` reemplaza la ficha completa.
- `na` es una lista `[motivo, nota]`, y opcionalmente `url`, o un objeto con `motivo`, `nota` y `url`.

Ejecuta `apply`:

```powershell
python C:\Users\jorge\.gemini\config\skills\actualizar-backlog\scripts\sync_backlog.py apply --base "<BASE_HTML>" --html "<CONSOLAS_HTML>" --excel "<EXCEL>" --changes "<SCRATCH_DIR>\changes.json"
```

- Si responde `"status": "error"`, **no se modificó ningún archivo** ni se crearon respaldos. Revisa los errores reportados, corrige `changes.json` y vuelve a intentar.
- Si responde `"status": "ok"`, el script automáticamente:
  - Crea respaldos con marca de tiempo en `_backups_backlog\` junto al Excel (conserva solo los 10 más recientes de cada archivo).
  - Unifica títulos contra `backlog.html`, elimina bajas, aplica actualizaciones y da de alta nuevos juegos.
  - Recalcula `# Backlog` (orden alfabético `1..N`) y `Orden Backlog` (`1` = más reciente según `backlog.html`).
  - Actualiza las hojas `Compatibilidad`, `Backlog`, `Switch 2 Boost`, `Boost - No Aplica`, `Cross-Save` (preservando la nota al pie y su fuente), `Dashboard` (conteos, fórmulas `COUNTIF` hasta la fila final y lista `REVISAR MANUALMENTE`), `Resumen Boost`, las tablas de Excel y el formato condicional.
  - Actualiza `const GAMES` en `backlog_consolas.html` conservando sus saltos de línea originales.
  - Verifica que los conteos coincidan entre `Compatibilidad`, `Backlog`, `Cross-Save` y `backlog_consolas.html`.

## Paso 4: Resumen final

Entrega un resumen claro con:
- Ruta de los respaldos creados.
- Conteo final de juegos (`HTML base` / `HTML consolas` / `Excel`).
- Juegos agregados, juegos eliminados y títulos unificados.
- Juegos pendientes o en `"Revisar"` cuya fecha, estado o plataformas se actualizaron tras la búsqueda web.
