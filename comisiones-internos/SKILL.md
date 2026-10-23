---
name: comisiones-internos
description: Genera los reportes mensuales de comisiones de los cambios internos de Mantenimiento. Se ejecuta desde la carpeta del mes (C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Comisiones\<año>\YYYYMM-Mes), lee los "Reporte Hrs Caso*.xls" de CambiosInternos\<colaborador>, crea un HorasCambioTT#####.xlsx por cambio. Usar cuando digan "/comisiones-internos", "genera las comisiones del mes", "reportes de comisiones de los colaboradores" o "comisiones de cambios internos". Los correos de autorización los hace /comisiones-correos.
---

# Comisiones mensuales de cambios internos (/comisiones-internos)

Generas los Excel de comisiones de los cambios internos del mes.
Los Excel los crea **siempre** `scripts/generar.ps1` a partir de la plantilla de la skill, nunca a mano. Así el estilo es el mismo todos los meses.

- **Carpeta de la skill** (`$SK`): `C:\Users\jorge\.gemini\config\skills\comisiones-internos`.
- **Carpeta del mes** (`$MES`): la carpeta de trabajo actual, con nombre `YYYYMM-Mes`, por ejemplo `202609-Septiembre`.
- **Títulos y estatus de los cambios:** `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx`. Usa la columna A (ID), la B (Descripción) y la D (Estatus).
- En este equipo no hay Python. Los scripts se corren en PowerShell 5.1, usan Excel por COM y están guardados en UTF-8 con BOM. Si los editas, consérvalos con BOM; sin él, los acentos salen corruptos.

## Entrada esperada

```
$MES\CambiosInternos\<Colaborador>\Reporte Hrs CasoTT#####.xls
```

- `<Colaborador>` es el nombre de pila: Miguel, Saulo, Susana, Martin o Jorge.
- Cada .xls es la exportación de horas de VTiger. Encabezados en la fila 1 y columnas en este orden:

  | Columna | Contenido |
  |---|---|
  | 1 | Id Caso |
  | 2 | Nombre de la tarea |
  | 3 | Descripción |
  | 9 | Horas trabajadas |
  | 10 | Fecha de inicio (`dd-mm-aaaa`) |
  | 11 | Asignado a |

- El TT se toma del contenido del archivo, no de su nombre. Si el nombre y el contenido no coinciden, avísalo en la entrega.

## Reglas de cálculo (fijas)

| Concepto | Valor |
|---|---|
| Horas que cuentan | Solo las tareas "Codificación"/"Codificacion" |
| Tarifa | $954 por hora (viene en la plantilla) |
| Importe | Horas × (1 − Descuento) × $954. El descuento es 0 salvo que el usuario indique otro. |
| Comisión | 15 % del importe |
| Reparto | 75 % para el programador y 25 % Adm. (Jorge) |
| Fecha de cada registro | Columna D (Fecha) del HorasCambio; `/comisiones-final` toma la primera como fecha del cambio |

## Paso 1 — Generar los Excel

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-internos\scripts\generar.ps1'
```

Usa la herramienta PowerShell con un timeout amplio (unos 300000 ms). Agrega `-Sobrescribir` solo si el usuario lo autoriza; sin esa opción, el script se detiene cuando un archivo de salida ya existe.

El script crea `CambiosInternos\<Colaborador>\HorasCambioTT#####.xlsx` para cada cambio.

Cuando todos los cambios se generaron sin error, el script **elimina los `Reporte Hrs Caso*.xls` base** que procesó. Si falla en cualquier cambio, no borra ninguno, para poder corregir y volver a correrlo.

Al final imprime, por cambio: TT, archivo de origen, quién codificó, horas, importe, última fecha, estatus en CambiosProceso y título.

Si el script falla con `no está en CambiosProceso.xlsx`, pregunta al usuario el título del caso. No lo inventes.

## Paso 2 — Entregar (en el chat, breve)

1. Una tabla: Colaborador | TT | Horas | Importe.
2. Las observaciones que el usuario debe confirmar:
   - archivos cuyo nombre no coincide con el TT de su contenido;
   - horas de otras tareas (análisis, pruebas) o de otra persona que no generan comisión;
   - fechas de registro fuera del mes del reporte;
   - cambios que en CambiosProceso no están en estatus "Entregado" o "Finalizado";
   - errores de captura en los títulos (se dejan tal cual vienen);
   - que no se aplicó descuento;
   - que los .xls base ya se eliminaron (para regenerar un cambio hay que volver a exportarlo de VTiger).
3. Que, una vez revisados (y editados si hace falta), los correos de autorización se preparan con `/comisiones-correos`.

Los reportes por beneficiario y el consolidado no son parte de esta skill.
