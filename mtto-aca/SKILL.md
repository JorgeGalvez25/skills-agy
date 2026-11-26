---
name: mtto-aca
description: Asigna y registra una solicitud de cambio nueva de Mantenimiento a partir del TT##### (los datos salen de VTiger) o de la captura del caso en VTiger (Id Caso TT#####, Título, Asignado a). Agrega el cambio a CambiosProceso.xlsm con los valores por omisión, deja en Outlook el borrador "TT##### ACA" para el colaborador asignado, con copia a Diana y la captura incrustada (o una imagen del caso generada desde VTiger), y con aprobación de Jorge pasa el caso a Codificando o Analizando en VTiger. Usar cuando digan "/mtto-aca", "asigna este cambio", "registra el cambio", "haz el ACA", "asignación de actividad de cambio" o adjunten la captura de un caso de VTiger de clase Proyectos para asignarlo.
argument-hint: "TT##### [colaborador] | [captura del caso de VTiger]"
---

# Asignación de actividad de cambio (/mtto-aca)

Jorge da el TT (y, si quiere, a quién se asigna) o pega la captura del caso de VTiger. Con eso registras el cambio en `CambiosProceso.xlsm`, preparas el correo de asignación al colaborador y mueves el caso en VTiger.

- **Script:** `C:\Users\jorge\.gemini\config\skills\mtto-aca\scripts\aca.ps1` (PowerShell 5.1, Excel y Outlook por COM, guardado en UTF-8 con BOM; si lo editas, consérvalo con BOM).
- **Registro:** `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm`, tabla `Tabla1` de `Hoja1`.
- **VTiger:** `C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js` (credenciales en `C:\Users\jorge\.mtto\vtiger.json`; nunca las muestres).

## Paso 1 — Datos del caso

Lee el caso en VTiger (con captura también, para no transcribir el título a mano):

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" caso TT#####
```

| Dato | De dónde | Uso |
|---|---|---|
| TT | `Caso (ticket_no)` | `-TT` |
| Título | `Título (ticket_title)`, tal cual (p. ej. `TT107494 -EL TREBOL-PANEL CLIENTE-AÑADIR CAMPO FECHA DE PAGO REPORTE DE ABONOS`) | `-Titulo` |
| Desarrollador | El que dé Jorge; si no, `asignado` de VTiger si es del equipo; si no, el "Asignado a" de la captura | `-Desarrollador` |

- Verifica que sea un Cambio (`Tipo (cf_867)`) de clase Proyectos; si no, díselo a Jorge antes de seguir.
- Si VTiger falla y hay captura, toma los datos de la imagen (respeta mayúsculas, guiones, espacios y acentos/Ñ; si algo no se lee, pregunta). Sin VTiger ni captura, pide la captura.
- Si no queda claro a quién se asigna (VTiger lo tiene en Melissa Virtual u otra persona fuera del equipo y Jorge no lo dijo), pregúntalo.
- Con varios casos, procesa cada uno por separado.

## Paso 2 — Ejecutar

```powershell
& 'C:\Users\jorge\.gemini\config\skills\mtto-aca\scripts\aca.ps1' -TT TT107494 -Titulo 'TT107494 -EL TREBOL-PANEL CLIENTE-AÑADIR CAMPO FECHA DE PAGO REPORTE DE ABONOS' -Desarrollador 'Martin Reyes' [-Imagen '<ruta de la captura>']
```

Usa la herramienta PowerShell con un timeout amplio (unos 120000 ms). Si el título lleva comillas simples, duplícalas.
`-Imagen` es la ruta que aparece en `[Image: source: ...]` del mensaje; sin captura, no lo pases.

El script:

1. **Agrega una fila al final de `Tabla1`** con: ID, Descripción (título), Desarrollador (nombre con acentos, como en la tabla), `Estatus = Proceso`, `Interno` vacío, `Autorizado = No`, `SCRUM = No`, `Cobrado = 0%` y `Fecha asignación` = hoy (columna I, la usa `/mtto-rendimiento`). Reacomoda `Tabla2` (rangos de descuento) para que siempre queden dos filas vacías entre ella y `Tabla1`. Guarda el `.xlsm` (conserva macros).
2. **Deja el borrador en Outlook** (Borradores, **no lo envía**):
   - **Para:** `<usuario>@igas.com.mx` del colaborador. **CC:** `dianagonzalez@imagensoft.com.mx`.
   - **Asunto:** `TT##### ACA`.
   - **Cuerpo:** `<Nombre> buen día, favor de darle seguimiento a la siguiente solicitud de cambio.` (`buenas tardes` desde las 12:00), la captura incrustada (sin captura, una imagen del encabezado del caso como lo muestra VTiger, generada con `vtiger.js vista`, con la misma sombra) y la firma de Jorge.
   - Si ya había un borrador con ese asunto, lo reemplaza.

Los colaboradores, sus correos y la copia salen de `C:\Users\jorge\.gemini\config\skills\mtto-comun\equipo.json`. Si el script dice que el desarrollador no está en la lista, pregunta sus datos y agrégalo a ese archivo (no al script).

## Errores

- **`CambiosProceso.xlsm está abierto`:** pide a Jorge que lo guarde y lo cierre, y vuelve a correrlo.
- **`TT##### ya está registrado`:** detente y pregúntale qué hacer (puede ser una reasignación). No modifiques el Excel por tu cuenta. Si te pide solo el correo, vuelve a correr con `-SoloCorreo`.

## Paso 3 — Mover el caso en VTiger (con aprobación)

Por omisión el cambio pasa a **Codificando**. Solo va a **Analizando** si la solicitud pide analizar primero (lo dice Jorge, los comentarios del caso en VTiger o el correo de la solicitud: busca el TT en `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\correos_mtto.json`).

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" mover TT##### codificando usuario="<Desarrollador>"
```

Sigue el flujo de `C:\Users\jorge\.gemini\config\skills\vtiger\SKILL.md` (léelo): simula, muestra estatus actual → nuevo y asignado, espera el "sí" de Jorge y repite con `--confirmar`.
Si el caso ya está en Codificando con ese colaborador, no hace falta moverlo. Si la API no permite el cambio desde el estatus actual, dilo y no insistas.

## Paso 4 — Entregar (en el chat, breve)

TT, título registrado, desarrollador, fila de CambiosProceso, que el borrador `TT##### ACA` está en Outlook listo para revisar y enviar, y el estatus que quedó en VTiger (o que no se movió).
