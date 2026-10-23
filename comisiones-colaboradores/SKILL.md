---
name: comisiones-colaboradores
description: Genera el Excel de comisiones de cada colaborador (Mantenimiento_Comisiones_<Mes>_<año>_<Nombre_Apellido>.xlsx en PorBeneficiario), con importes fijos en lugar de las fórmulas de porcentaje y solo las filas que le tocan a cada quien. Se ejecuta desde la carpeta del mes (C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Comisiones\<año>\YYYYMM-Mes) y toma los valores del concentrado del mes. Usar cuando digan "/comisiones-colaboradores", "genera los archivos por beneficiario", "el excel de cada colaborador", "reportes por beneficiario" o "comisiones sin fórmulas de cada uno".
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

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-colaboradores\scripts\colaboradores.ps1'
```

Usa la herramienta PowerShell con un timeout amplio (unos 300000 ms). Agrega `-Sobrescribir` solo si el usuario lo autoriza; sin esa opción, el script se detiene si un archivo ya existe.

Si falla porque el archivo está abierto, pide al usuario que lo cierre y vuelve a correrlo.

## Paso 2 — Entregar (en el chat, breve)

1. Una tabla: beneficiario, total y archivo.
2. La suma de los archivos contra el total del concentrado sin la parte de Jorge. Si no cuadran, dilo.
