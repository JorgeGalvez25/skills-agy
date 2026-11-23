---
name: comisiones-final
description: Genera el concentrado mensual de comisiones de Mantenimiento (Mantenimiento_Comisiones_<Mes>_<año>.xlsx). Se ejecuta desde la carpeta del mes (C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Comisiones\<año>\YYYYMM-Mes), toma como base el concentrado del mes anterior, llena los cambios externos con el externos.PDF del mes y los internos con los HorasCambioTT#####.xlsx de CambiosInternos tal como estén guardados, y conserva igual la hoja Mejoras. Si el Excel ya existe, deja en Outlook el borrador del correo "Resumen de comisiones" con el archivo adjunto. Usar cuando digan "/comisiones-final", "genera el concentrado de comisiones", "archivo final de comisiones" o "Mantenimiento_Comisiones del mes".
---

# Concentrado mensual de comisiones (/comisiones-final)

Generas el archivo final con todas las comisiones del mes, con las mismas fórmulas y el mismo formato del mes anterior.
Si el Excel del mes ya existe, la skill solo deja el borrador del correo (ver el final). Va después de `/comisiones-internos` (que crea los `HorasCambioTT#####.xlsx`) y de que el usuario los haya revisado o editado.

- **Carpeta de la skill:** `C:\Users\jorge\.gemini\config\skills\comisiones-final`.
- **Carpeta del mes** (`$MES`): la carpeta de trabajo actual, con nombre `YYYYMM-Mes` (por ejemplo `202609-Septiembre`).
- **Base:** `Mantenimiento_Comisiones_<Mes>_<año>.xlsx` de la carpeta del mes anterior. En enero se busca en la carpeta del año anterior.
- **Títulos de los cambios:** `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm` (columna A = ID, columna B = Descripción).
- El script corre en PowerShell 5.1, usa Excel por COM y está guardado en UTF-8 con BOM. Si lo editas, consérvalo con BOM.

## Reglas (fijas)

**Cambios externos** (filas 7 a 9 de la hoja del mes):

| Concepto | Valor |
|---|---|
| Fuente | `externos.PDF` de la carpeta del mes (Reporte de Comisiones por Vendedor) |
| Cliente JAG (`001132-JAG AUTOSERVICIOS`) | Concepto `Póliza Mantenimiento`; siempre es de **Martin** |
| Otros clientes | Concepto `CAMBIO EXTERNO`; el beneficiario lo indica el usuario |
| Reparto | 15 % Jorge y 85 % el beneficiario |

**Cambios internos** (filas 16 a 28):

| Concepto | Valor |
|---|---|
| Fuente | `CambiosInternos\<Colaborador>\HorasCambioTT#####.xlsx`, tal como estén guardados |
| Orden | Por número de TT |
| Fecha | La primera fecha de la columna D del HorasCambio |
| Solicitó / Cliente | `Ing. Jorge Orduño` / `IMAGENSOFT` |
| Concepto | Título de CambiosProceso sin espacios alrededor de los guiones |
| Importe | El "Importe Total" del HorasCambio, con las ediciones del usuario |
| Comisión | 15 % del importe |
| Reparto | 25 % Jorge y 75 % el colaborador (la carpeta). Columnas: J Jorge, K Susana, L Martin, M Saulo, N Miguel |

**Pagos en partes** (filas 16 a 28): cuando el usuario reparte la comisión de un TT en varios meses, lo deja en el concentrado con `(Pago k de N)` al final del concepto (columna F) y el importe como `=(G*H)/N`. Antes de generar, el script revisa el concentrado del mes anterior y arrastra a este mes cada TT con k < N: mismo concepto con `(Pago k+1 de N)`, misma fecha, importe, porcentaje y reparto, y la fórmula `/N`. Al llegar al último pago (k = N) ya no se arrastra. Se mezclan con los TT nuevos y quedan ordenados por número de TT. Solo aplica a cambios internos.

**Mejoras:** la hoja Mejoras y la fila 15 ("Mejora a productos i-Gas", con su reparto) se conservan exactas del mes anterior.

Solo quedan visibles las filas con datos; las demás de cada tabla se ocultan.

## Paso 1 — Leer los cambios externos

Extrae el texto de `$MES\externos.PDF` con pdfplumber, que da los importes exactos y gasta menos que leer las páginas como imagen:

```powershell
python -c "import pdfplumber,sys; [print(p.extract_text()) for p in pdfplumber.open(sys.argv[1]).pages]" "<$MES>\externos.PDF"
```

Si el texto sale vacío o desordenado (PDF escaneado), léelo con la herramienta `read_file`. De cada factura toma: factura (`FI-######`), fecha, recibo (`RI-######`), cliente, importe pagado y porcentaje de comisión.

- Si un cliente no es JAG, pregunta al usuario a quién le corresponde (Jorge, Susana, Martin, Saulo o Miguel). No lo supongas.
- Si no hay PDF, pregunta al usuario si el mes no tuvo cambios externos.

Escribe un JSON en el scratchpad (no en la carpeta del mes):

```json
[
  { "Factura": "FI-019209", "Fecha": "04/08/2026", "Recibo": "RI-036866", "Cliente": "001132-JAG AUTOSERVICIOS", "Importe": 15600, "Pct": 0.1 },
  { "Factura": "FI-019300", "Fecha": "15/09/2026", "Recibo": "RI-037100", "Cliente": "000123-OTRO CLIENTE", "Importe": 8000, "Pct": 0.1, "Beneficiario": "Saulo" }
]
```

`Fecha` va en `dd/MM/yyyy`. `Beneficiario` solo es necesario cuando el cliente no es JAG.

## Paso 2 — Generar

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-final\scripts\concentrado.ps1' -Externos '<ruta del JSON>'
```

Si no hay externos, omite `-Externos`. Usa la herramienta PowerShell con un timeout amplio (unos 300000 ms). Agrega `-Sobrescribir` solo si el usuario lo autoriza; sin esa opción, el script se detiene si el archivo ya existe.

Si falla:

- `no está en CambiosProceso.xlsm`: pregunta al usuario el título del caso. No lo inventes.
- `no tiene fechas en la columna D`: ese HorasCambio se generó sin fechas; pide al usuario la fecha del primer registro y escríbela en D2.
- El archivo está abierto: pide al usuario que lo cierre y vuelve a correrlo.

## Paso 3 — Entregar (en el chat, breve)

1. El concentrado base que se usó.
2. La tabla de internos (TT, colaborador, fecha, importe, comisión) y la de externos.
3. El total de externos, internos y general, y el resumen por beneficiario.
4. Los TT arrastrados con pago pendiente (se listan como `Pago k/N` en la columna Colab.) y los que terminaron su último pago.
5. Si algo no cuadra (un TT sin título o un externo sin beneficiario), dilo.

## Borrador del correo (cuando el Excel ya está generado)

Si `Mantenimiento_Comisiones_<Mes>_<año>.xlsx` ya existe en la carpeta del mes y el usuario no pide regenerarlo, **no corras `concentrado.ps1`**: deja el borrador en Outlook con el archivo tal como esté guardado (incluye las ediciones del usuario).

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-final\scripts\correo.ps1'
```

Usa la herramienta PowerShell con un timeout de unos 120000 ms. **No lo envía.** Reemplaza el borrador previo con el mismo asunto. Si el Excel está abierto, se detiene; pide al usuario que lo cierre y vuelve a correrlo.

Redacción fija, tomada del correo de octubre 2026 (`<mes>` en minúscula; el de pago es el mes siguiente, con su año):

- **Para:** `'rosaescalante@imagensoft.com.mx'; Ma. Esther Ahumada (estherahumada@imagensoft.com.mx)`
- **CC:** `'jorgeorduno@imagensoft.com.mx'`
- **Asunto:** `Resumen de comisiones de <mes> de <año>`
- **Adjunto:** el concentrado del mes.
- **Cuerpo:**

```
Buen día,

Envío resumen de comisiones correspondientes al mes de <mes> de <año> a pagar en <mes de pago> de <año de pago>.

Cualquier duda o comentario quedo a la orden.

Saludos…


Jorge Armando Gálvez Martínez
Analista - Desarrollador
```

En el chat, entrega el asunto, los destinatarios y la fecha de guardado del Excel adjunto, y si reemplazó un borrador anterior.
