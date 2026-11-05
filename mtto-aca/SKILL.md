---
name: mtto-aca
description: Asigna y registra una solicitud de cambio nueva de Mantenimiento a partir de la captura del caso en VTiger (Id Caso TT#####, Título, Asignado a). Agrega el cambio a CambiosProceso.xlsm con los valores por omisión y deja en Outlook el borrador "TT##### ACA" para el colaborador asignado, con copia a Diana y la captura incrustada. Usar cuando digan "/mtto-aca", "asigna este cambio", "registra el cambio", "haz el ACA", "asignación de actividad de cambio" o adjunten la captura de un caso de VTiger de clase Proyectos para asignarlo.
argument-hint: "[captura del caso de VTiger]"
---

# Asignación de actividad de cambio (/mtto-aca)

Jorge pega la captura del caso de VTiger. Con ella registras el cambio en `CambiosProceso.xlsm` y preparas el correo de asignación al colaborador.

- **Script:** `C:\Users\jorge\.gemini\config\skills\mtto-aca\scripts\aca.ps1` (PowerShell 5.1, Excel y Outlook por COM, guardado en UTF-8 con BOM; si lo editas, consérvalo con BOM).
- **Registro:** `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm`, tabla `Tabla1` de `Hoja1`.

## Paso 1 — Leer la captura

De la imagen toma:

| Campo de VTiger | Uso |
|---|---|
| Id Caso | `-TT` (TT#####) |
| Titulo | `-Titulo`, tal cual aparece (p. ej. `TT107494 -EL TREBOL-PANEL CLIENTE-AÑADIR CAMPO FECHA DE PAGO REPORTE DE ABONOS`) |
| Asignado a | `-Desarrollador` (VTiger lo escribe sin acentos; el script lo empata con la lista) |

Transcribe el título con cuidado: respeta mayúsculas, guiones, espacios y acentos/Ñ. Si algo no se lee bien en la captura, pregunta; no lo adivines.

La ruta de la imagen es la que aparece en `[Image: source: ...]` del mensaje. Si el usuario dio varias capturas, procesa cada caso por separado.

## Paso 2 — Ejecutar

```powershell
& 'C:\Users\jorge\.gemini\config\skills\mtto-aca\scripts\aca.ps1' -TT TT107494 -Titulo 'TT107494 -EL TREBOL-PANEL CLIENTE-AÑADIR CAMPO FECHA DE PAGO REPORTE DE ABONOS' -Desarrollador 'Martin Reyes' -Imagen '<ruta de la captura>'
```

Usa la herramienta PowerShell con un timeout amplio (unos 120000 ms). Si el título lleva comillas simples, duplícalas.

El script:

1. **Agrega una fila al final de `Tabla1`** con: ID, Descripción (título), Desarrollador (nombre con acentos, como en la tabla), `Estatus = Proceso`, `Interno` vacío, `Autorizado = No`, `SCRUM = No`, `Cobrado = 0%` y `Fecha asignación` = hoy (columna I, la usa `/mtto-rendimiento`). Reacomoda `Tabla2` (rangos de descuento) para que siempre queden dos filas vacías entre ella y `Tabla1`. Guarda el `.xlsm` (conserva macros).
2. **Deja el borrador en Outlook** (Borradores, **no lo envía**):
   - **Para:** `<usuario>@igas.com.mx` del colaborador. **CC:** `dianagonzalez@imagensoft.com.mx`.
   - **Asunto:** `TT##### ACA`.
   - **Cuerpo:** `<Nombre> buen día, favor de darle seguimiento a la siguiente solicitud de cambio.` (`buenas tardes` desde las 12:00), la captura incrustada y la firma de Jorge.
   - Si ya había un borrador con ese asunto, lo reemplaza.

Colaboradores conocidos: Saulo López, Susana Gámez, Miguel Armenta, Martín Reyes (correo `nombreapellido@igas.com.mx`). Si el script dice que el desarrollador no está en la lista, pregunta su correo y agrégalo a `$colaboradores` en el script.

## Errores

- **`CambiosProceso.xlsm está abierto`:** pide a Jorge que lo guarde y lo cierre, y vuelve a correrlo.
- **`TT##### ya está registrado`:** detente y pregúntale qué hacer (puede ser una reasignación). No modifiques el Excel por tu cuenta. Si te pide solo el correo, vuelve a correr con `-SoloCorreo`.

## Paso 3 — Entregar (en el chat, breve)

TT, título registrado, desarrollador, fila de CambiosProceso y que el borrador `TT##### ACA` está en Outlook listo para revisar y enviar.
