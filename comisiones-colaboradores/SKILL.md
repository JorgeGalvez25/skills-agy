---
name: comisiones-colaboradores
description: Genera el Excel de comisiones de cada colaborador (Mantenimiento_Comisiones_<Mes>_<año>_<Nombre_Apellido>.xlsx en PorBeneficiario), con importes fijos en lugar de las fórmulas de porcentaje y solo las filas que le tocan a cada quien. Se ejecuta desde la carpeta del mes (C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Comisiones\<año>\YYYYMM-Mes) y toma los valores del concentrado del mes. Si los Excel ya existen, deja en Outlook un borrador por colaborador con su archivo adjunto. Usar cuando digan "/comisiones-colaboradores", "genera los archivos por beneficiario", "el excel de cada colaborador", "reportes por beneficiario", "comisiones sin fórmulas de cada uno" o "manda el reporte de comisiones a cada colaborador".
---

# Comisiones por colaborador (/comisiones-colaboradores)

Generas un Excel por beneficiario a partir del concentrado del mes. Va después de `/comisiones-final`.
Los archivos los crea **siempre** `scripts/colaboradores.ps1` a partir de la plantilla de la skill, nunca a mano.

- **Carpeta de la skill:** `C:\Users\jorge\.gemini\config\skills\comisiones-colaboradores`.
- **Carpeta del mes** (`$MES`): la carpeta de trabajo actual, con nombre `YYYYMM-Mes`.
- **Origen:** `$MES\Mantenimiento_Comisiones_<Mes>_<año>.xlsx`, tal como esté guardado.
- **Salida:** `$MES\PorBeneficiario\Mantenimiento_Comisiones_<Mes>_<año>_<Nombre_Apellido>.xlsx`.
- **Plantilla:** `plantillas\Beneficiario.xlsx`. Es el archivo de Jorge de agosto 2026; el script cambia el nombre y el número de cada persona.
- El script corre en PowerShell 5.1, usa Excel por COM y está guardado en UTF-8 con BOM. Si lo editas, consérvalo con BOM.

## Reglas (fijas)

| Concepto | Valor |
|---|---|
| Quién recibe archivo | Cada beneficiario con total mayor a cero (columnas R:V del concentrado), excepto Jorge Gálvez |
| Nombre y número | Del concentrado: nombre en la fila 6 y número en la fila 5 de R:V |
| Filas | Solo las de externos (7 a 9) e internos (15 a 28) donde la persona tiene importe; la de Mejoras va primero en internos |
| Columnas B:I | Los valores calculados del concentrado, sin fórmulas |
| Columna J | Lo que le toca a la persona, como importe fijo |
| Totales y resumen | Fórmulas `SUM` y referencias, igual que la plantilla |
| Tabla sin filas | Queda solo la fila de total en ceros |

## Paso 1 — Generar

Primero revisa `$MES\PorBeneficiario`. Si ya hay archivos `Mantenimiento_Comisiones_<Mes>_<año>_*.xlsx`, omite este paso y el Paso 2, y ve directo al Paso 3. Solo regenéralos si el usuario lo pide.

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-colaboradores\scripts\colaboradores.ps1'
```

Usa la herramienta PowerShell con un timeout amplio (unos 300000 ms). Agrega `-Sobrescribir` solo si el usuario lo autoriza; sin esa opción, el script se detiene si un archivo ya existe.

Si falla porque el archivo está abierto, pide al usuario que lo cierre y vuelve a correrlo.

## Paso 2 — Entregar (en el chat, breve)

1. Una tabla: beneficiario, total y archivo.
2. La suma de los archivos contra el total del concentrado sin la parte de Jorge. Si no cuadran, dilo.

Si en esta ejecución generaste los Excel, aquí terminas: **no hagas borradores**. Los borradores se hacen en una ejecución posterior de la skill, cuando los Excel ya existan.

## Paso 3 — Borradores en Outlook (solo si los Excel ya estaban generados)

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-colaboradores\scripts\correos.ps1'
```

Usa la herramienta PowerShell con un timeout de unos 180000 ms. Por cada Excel de `PorBeneficiario`, el script deja un borrador en Outlook con ese archivo adjunto, tal como esté guardado. **No lo envía.** Si ya había un borrador con el mismo asunto para esa persona, lo borra y crea uno nuevo. Si un Excel (de `PorBeneficiario`, el concentrado o `CambiosProceso.xlsm`) está abierto, se detiene antes de hacer nada; pide al usuario que lo cierre y vuelve a correrlo.

Después actualiza `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm` (`Tabla1`) con lo pagado en este mes, según los cambios internos del concentrado (filas 16 a 28; externos y Mejoras no se tocan):

| Concepto | Valor |
|---|---|
| Columna `Cobrado` | Porcentaje pagado después de este pago: `k/N` si el concepto termina en `(Pago k de N)`, 100 % si no |
| Pagado al 100 % | Se quita el relleno amarillo de la fila |

Como escribe el porcentaje acumulado (no lo suma), correr la skill varias veces deja el mismo resultado.

Redacción fija, tomada de los que Jorge envió en agosto 2026 (`<mes>` en minúscula; el de pago es el mes siguiente, con su año):

- **Para:** `<nombre><apellido>@igas.com.mx`, en minúsculas y sin acentos (p. ej. `saulolopez@igas.com.mx`).
- **Asunto:** `Reporte de comisiones <mes> <año>`
- **Cuerpo:**

```
Comisiones de <mes> pagadas en <mes de pago> <año de pago>.


Jorge Armando Gálvez Martínez
Analista - Desarrollador
```

En el chat, entrega la lista de borradores (persona, correo y fecha de guardado del Excel) y cuáles reemplazaron a uno anterior, y los TT con el porcentaje que quedó en `Cobrado` (y a cuáles se les quitó el amarillo). Si un TT no está en CambiosProceso, dilo.
