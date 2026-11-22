---
name: actualizar-backlog
description: Actualiza el backlog de videojuegos de Jorge sincronizando el HTML exportado de Backloggd (backlog.html) con el visor interactivo (backlog_consolas.html) y el libro de compatibilidad (game_backlog_compatibilidad_consolas.xlsx). Da de baja los juegos que ya no están en Backloggd, unifica títulos, investiga en la web los juegos nuevos y los pendientes por lanzar o en "Revisar", y deja todas las hojas del Excel y el visor sincronizados. Usar cuando digan "/actualizar-backlog", "actualiza mi backlog", "sincroniza el backlog", "ya guardé el backlog de Backloggd" o den la ruta de backlog.html.
argument-hint: "[backlog.html] [backlog_consolas.html] [excel]"
---

# Actualizar backlog de videojuegos (/actualizar-backlog)

Sincronizas la lista oficial guardada desde Backloggd (`backlog.html`) contra el visor web (`backlog_consolas.html`) y el Excel multihoja. `backlog.html` manda: al terminar, los tres tienen exactamente los mismos juegos.
Los archivos los modifica **siempre** el script `scripts/sync_backlog.py`, nunca a mano ni con otro código. Tu trabajo es: inspeccionar, resolver dudas con Jorge, investigar en la web, preparar `changes.json`, aplicar y reportar.

**Carpeta de la skill** (`$SK`): `C:\Users\jorge\.gemini\config\skills\actualizar-backlog`. Ejecuta con la herramienta `run_command`: `python "$SK/scripts/sync_backlog.py" ...` (Python 3 con `openpyxl`).
**Archivos de trabajo** (`inspect.json`, `changes.json`): en el scratchpad de la sesión.

## Rutas

Se aceptan 0 a 3 rutas, en este orden; las que falten usan su valor por omisión:

1. HTML de Backloggd: `C:\Users\jorge\Desktop\backlog.html`
2. Visor: `G:\Mi unidad\backlog_consolas.html`
3. Excel: `G:\Mi unidad\game_backlog_compatibilidad_consolas.xlsx`

Pasa al script solo las que difieran del valor por omisión (`--base`, `--html`, `--excel`).

## Paso 1: Inspección

```powershell
python "C:\Users\jorge\.gemini\config\skills\actualizar-backlog\scripts\sync_backlog.py" inspect --out "<SCRATCH>\inspect.json" | Out-Null
```

Lee `inspect.json` y actúa según su contenido:

- **`warnings`**:
  - `WARNING_TRUNCATED_BASE` (menos de 50 juegos o caída de más de 30 %): detente y pide a Jorge que confirme que guardó la página completa de Backloggd.
  - `WARNING_DUPLICATED_TITLES`: dos juegos con el mismo nombre; el script no puede distinguirlos. Avisa y detente.
  - `WARNING_EXCEL_JS_MISMATCH`: el visor y el Excel ya estaban descuadrados (`excel_not_in_js` / `js_not_in_excel`). Muéstralo y pregunta cómo resolverlo antes de seguir.
- **`fuzzy_matches_base_vs_html`**: pares con nombre parecido (`source` = título en Backloggd, `target` = título actual). Pregunta por cada uno si es el mismo juego:
  - Mismo juego → `"unify_titles": {"<target>": "<source>"}`.
  - Juego distinto → `<target>` va a `remove` y `<source>` va a `add` (con el `img` de `base_item`), investigándolo como juego nuevo.
- **`to_remove`**: confirma las bajas con Jorge, salvo que ya haya autorizado aplicar todo directo.
- **`title_unifications`**: informativo; el script alinea esos títulos al oficial de Backloggd por su cuenta.

## Paso 2: Investigación web

Lee `C:\Users\jorge\.gemini\config\skills\actualizar-backlog\references\esquema-y-criterios.md` antes de preparar fichas. Usa `search_web` y lanza las búsquedas independientes en paralelo. Si hay más de 6 juegos que investigar, reparte los juegos en subagentes en paralelo (invocando `invoke_subagent` con `TypeName: "self"`, `Role: "Investigador de Backlog"`, `Model: "flash"`; no uses `research` porque no tiene acceso a red). A cada uno le pasas los criterios y le pides de vuelta solo los objetos JSON de su lote.

1. **Juegos nuevos (`to_add`)**: año (`y`), desarrollador (`d`), plataformas (`p`), duración estilo HowLongToBeat (`h`, `"N/A"` si no ha salido), estado (`s`), compatibilidad en los 9 dispositivos (`m`) aplicando estrictamente los criterios, notas por plataforma (`n`), mejor opción (`b`) y cross-save (`cs`). Agrega `bo` si tiene versión de Switch 1; si es exclusivo de Switch 2 u otro caso de "Boost - No Aplica", agrega `na`; si no tiene relación con Switch, omite ambos. Conserva el `t` y el `img` de `to_add`.
2. **Pendientes y en revisión (`pending_and_review`)**: verifica si ya salieron, si ya tienen fecha exacta o si se confirmó o canceló alguna plataforma. Si salió, cambia `s` a `"Disponible o ya lanzado"` y `"Sí, cuando esté disponible"` a `"Sí"` / `"Sí*"`; ajusta `y`, `p`, `n`, `h`, `cs` y `bo`/`na` si cambiaron. No incluyas en `update` los juegos cuya información siga igual.

## Paso 3: Aplicar

Escribe `<SCRATCH>/changes.json`. Todas las llaves son opcionales:

```json
{
  "unify_titles": {"Título actual": "Título oficial de backlog.html"},
  "remove": ["Título exacto a eliminar"],
  "update": [
    {"t": "Título exacto", "s": "Disponible o ya lanzado", "m": ["Sí", "Sí", "Sí", "No", "Sí", "Sí", "No", "No", "No"], "n": ["PS5: ...", "PC: ..."]}
  ],
  "add": [
    {
      "t": "Título oficial de backlog.html", "y": 2026, "d": "Estudio", "p": "PC, PS5, Xbox Series X|S", "h": "N/A",
      "m": ["Sí, cuando esté disponible", "Sí, cuando esté disponible", "No", "No", "Sí, cuando esté disponible", "Sí, cuando esté disponible", "No", "No", "No"],
      "b": "PC", "n": ["PS5: ...", "Xbox: ...", "PC: ...", "ROG: ..."], "s": "2026 / confirmar fecha exacta",
      "img": "coajye", "tag": "",
      "cs": ["No confirmado", "Nube por ecosistema / storefront", "Steam/Epic/GOG, PS Plus, Xbox Cloud o NSO por separado", "Notas."],
      "bo": null, "na": null
    }
  ]
}
```

- `cs` en `add` puede ser lista `[cross_save?, tipo, alcance, notas]` o un objeto con `cs_q`, `cs_type`, `scope`, `confidence`, `notes` y `url`; en `update` es un objeto con solo las llaves que cambian.
- `bo` es una lista `[tipo, cómo corre, FPS/resolución, veredicto]`, y opcionalmente `confianza`, `notas` y `url`, o un objeto con `tipo`, `como_corre`, `fps`, `veredicto`, `confianza`, `notas` y `url`. En `update` reemplaza la ficha completa.
- `na` es una lista `[motivo, nota]`, y opcionalmente `url`, o un objeto con `motivo`, `nota` y `url`.

```powershell
python "C:\Users\jorge\.gemini\config\skills\actualizar-backlog\scripts\sync_backlog.py" apply --changes "<SCRATCH>\changes.json"
```

- Si devuelve `"status": "error"`, **no se modificó ningún archivo**. Los errores dicen qué falta: juegos de Backloggd sin ficha, juegos que ya no están en Backloggd sin `remove`, títulos que no existen, etc. Corrige `changes.json` y vuelve a ejecutar.
- Si devuelve `"status": "ok"`, el script ya:
  - creó respaldos en `_backups_backlog\` junto al Excel (conserva los 10 más recientes de cada archivo);
  - reescribió las hojas de datos y ajustó las tablas de Excel, el formato condicional y los `COUNTIF` del Dashboard a la nueva última fila;
  - actualizó el Dashboard, Resumen Boost y `const GAMES` del visor, conservando sus saltos de línea;
  - comprobó que los conteos coincidan.

## Paso 4: Resumen

Entrega en pocas líneas:
- Conteo final (Backloggd / visor / Excel) y ruta de los respaldos.
- Juegos agregados, eliminados y títulos unificados.
- Pendientes o en "Revisar" que cambiaron tras la búsqueda (qué cambió en cada uno) y los que siguen pendientes.
