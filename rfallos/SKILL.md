---
name: rfallos
description: Genera la relación mensual de fallos atendidos del Departamento de Mantenimiento (indicador 1, "Cumplimiento de atención de fallos según criticidad") para cualquier mes. Recibe el mes como YYYYMM (año de 4 dígitos + mes de 2 dígitos, p. ej. 202610 o 202701), lee la exportación de VTiger de la carpeta de ese mes, asigna la criticidad P1–P4 de cada caso según su título y crea MMYYYY_RelacionFallosAtendidos.xlsx con el formato oficial. Usar cuando digan "/rfallos YYYYMM", "rfallos <mes>", "relación de fallos atendidos de <mes>" o "genera el indicador de fallos del mes".
argument-hint: YYYYMM
---

# Relación mensual de fallos atendidos (/rfallos YYYYMM)

Generas el reporte de evidencia del **indicador 1 — Cumplimiento de atención de fallos según criticidad** del jefe de Mantenimiento.
El Excel lo crea **siempre** el script `scripts/generar.js`, nunca a mano ni con otro código, para que el estilo sea idéntico todos los meses.
Tu trabajo es: validar la entrada, **asignar la criticidad de cada caso a partir de su título**, preguntar lo que tenga duda, ejecutar el script y reportar el resultado.

**Carpeta de la skill** (en este documento, `$SK`): `C:\Users\jorge\.gemini\config\skills\rfallos`. Los scripts están en `$SK\scripts` y ya tienen sus dependencias (`node_modules` con `xlsx` y `exceljs`).
**Carpeta raíz de indicadores** (`$RAIZ`): `C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Indicadores`.
No hay Python en este equipo: todo se ejecuta con **Node** (`node`). Ejecuta los scripts con la herramienta Bash usando rutas absolutas.

## Reglas que no se negocian

1. **Argumento:** clave `YYYYMM` de 6 dígitos para **cualquier mes** (año de 4 dígitos + mes 01–12). Ejemplos: `202610` = octubre de 2026, `202701` = enero de 2027. Los nombres de carpeta y archivos se derivan de esa clave (carpeta `YYYYMM`, archivos `MMYYYY_...`); nunca asumas un mes fijo. Si no viene o tiene otro formato, pregunta el mes y no continúes.
2. **No crees carpetas.** La carpeta `$RAIZ\YYYYMM` ya debe existir y contener la exportación de VTiger. Si falta, avisa al usuario y detente.
3. **No modifiques la exportación de VTiger** ni ningún otro archivo de la carpeta del mes. Solo se crea `MMYYYY_RelacionFallosAtendidos.xlsx`.
4. **No sobrescribas.** Si el xlsx de salida ya existe (`salidaExiste: true`), pregunta antes. Usa `--sobrescribir` solo con autorización explícita para ese mes.
5. **No cambies el estilo ni el script** para un mes en particular. Si algo no encaja (columnas distintas, fechas raras), detente y pregunta.
6. **Integridad:** no ajustes criticidades para mejorar el porcentaje. La criticidad se decide por el impacto que describe el título, no por el tiempo que tardó el caso.
7. Español con acentos y ortografía correctos. Fechas `dd/mm/aaaa`.

## Datos fijos del indicador

| Concepto | Valor |
|---|---|
| Objetivos por criticidad (días hábiles) | **P1 = 2 · P2 = 4 · P3 = 8 · P4 = 12** |
| Conteo de tiempo | `NETWORKDAYS(Asignación de caso, Fecha real de respuesta, feriados)`, inclusivo en ambos extremos, lunes a viernes |
| Feriados descontados | Días de descanso obligatorio de la LFT, art. 74 (1/01, primer lunes de febrero, tercer lunes de marzo, 1/05, 16/09, tercer lunes de noviembre, 25/12 y 1/10 cada seis años desde 2024), solo los que caen entre la asignación más antigua y la respuesta más reciente. El script los calcula. |
| Cumple | Tiempo de atención ≤ objetivo de su criticidad |
| Fórmula del indicador | Fallos dentro del objetivo ÷ fallos evaluables × 100 |
| Matriz | **EXCELENTE** ≥ 97% · **BUENO** 93–96.99% · **REGULAR** 85–92.99% · **NO ACEPTABLE** < 85% |
| Evaluables | Todos los casos de la exportación **excepto** los de "Estatus fallo" = `Cancelado` |
| Sí cuentan | "Apoyo a soporte" y cualquier caso registrado como Fallo, aunque el título parezca solicitud o capacitación (se clasifica, normalmente P4) |

Si el usuario cambia algún objetivo, actualiza `OBJETIVOS` en `$SK\scripts\comun.js`, esta tabla y la hoja "Guía de indicadores" de `$RAIZ\Indicadores_Depto_Mantenimiento_Actualizados.xlsx`.

## Entrada esperada

- Carpeta: `$RAIZ\YYYYMM`.
- Archivo: exportación del reporte de VTiger **"Relacion fallos atendidos"** (Clase = Proyectos; Tipo = Fallo, Apoyo a soporte o Piloto; Suite = I-Gas; Fecha real de respuesta dentro del mes de la clave; en VTiger se usa el filtro "Mes anterior" cuando se exporta al mes siguiente o un rango de fechas para cualquier otro mes), nombrada `MMYYYY_RelacionFallosAtendidos.xls`. Por ejemplo, para `202610` es `102026_RelacionFallosAtendidos.xls` y para `202701` es `012027_RelacionFallosAtendidos.xls`.
  - Si tiene otro nombre pero es el único `*RelacionFallosAtendidos*.xls/.xlsx/.csv` de la carpeta, el script lo usa. Si hay varios, el script falla y debes preguntar cuál usar.
- Columnas obligatorias (primera hoja, encabezados en la fila 1): `Id Caso`, `Título`, `Tipo`, `Estatus fallo`, `Asignación de caso`, `Fecha real de respuesta`. Las fechas vienen como `dd-mm-aaaa` (con o sin hora).

## Paso 1 — Extraer y validar los casos

```bash
node "C:/Users/jorge/.gemini/config/skills/rfallos/scripts/extraer.js" YYYYMM
```

Devuelve un JSON con `entrada`, `salida`, `salidaExiste`, `evaluables[]` (id, tipo, estatus, asignacion, respuesta, titulo), `cancelados[]` y `avisos[]`.

- Si termina con `ERROR:`, muéstrale el mensaje al usuario y detente (carpeta inexistente, archivo faltante, columnas faltantes, etc.).
- Si `salidaExiste` es `true`, pregunta si se sobrescribe (regla 4).
- Si hay `avisos` (casos sin fecha, con respuesta fuera del mes, con respuesta anterior a la asignación o duplicados), pregúntale al usuario qué hacer antes de continuar. El script de generación no acepta casos evaluables sin fechas.

## Paso 2 — Asignar criticidad por título

Clasifica **cada** caso de `evaluables` en P1, P2, P3 o P4 leyendo su título. El título sigue el patrón `TT###### -CLIENTE-MÓDULO-DESCRIPCIÓN`; lo que define el impacto son el **módulo** y la **descripción**.

Definiciones oficiales (hoja "Guía de indicadores"):

- **P1 — Crítico:** impide vender, facturar o realizar otra operación esencial de la estación, sin alternativa razonable.
- **P2 — Alto:** afectación importante, pero existe una alternativa temporal o solo una parte de la operación está comprometida.
- **P3 — Normal:** fallo real que requiere corrección, pero no compromete la continuidad de la operación.
- **P4 — Bajo:** problema menor, cosmético o con impacto operativo reducido.

Criterios prácticos (calibrados con septiembre de 2026):

| Criticidad | Señales en el título | Ejemplos reales |
|---|---|---|
| **P1** | No se puede vender ni despachar; cambio de precios que no se aplica; no se puede facturar ni timbrar en general; caída total del punto de venta, de la isla principal o del sistema completo | `PANEL CLIENTE-CAMBIO DE PRECIOS NO SE APLICA` |
| **P2** | Falla en una sola isla, terminal o dispositivo; kiosco o retiro de efectivo; transmisiones a terceros que no se envían (Mobil, controles volumétricos, interfaces); impresión de tickets; operación de caja parcialmente afectada | `TRASMISOR MOBIL-LAS TRANSMISIONES MOBIL NO SE ENVIAN` · `TERMINAL PARA IMPRIMIR TICKET NO SE VINCULA CON EL MULTIISLA EN ISLA 1` · `APOYO A SOPORTE-KIOSCO-RETIRO DE EFECTIVO` |
| **P3** | Diferencias o datos incorrectos en reportes, liquidaciones, inventarios, CxC o saldos; reportes que no generan; tipos de pago mal relacionados; herramientas de migración; revisiones de "Apoyo a soporte" sin impacto operativo inmediato | `LIQUIDACIONES-NO SE ACTUALIZAN INVENTARIOS DE ACEITES` · `DIFERENCIAS EN LITROS ENTRE REPORTES` · `CXC-REPORTE ... NO DA` · `REPORTE DE FACTURAS DE CREDITO MUESTRA TODAS LAS ESTACIONES` · `APOYO A SOPORTE-REVISION FLUJO POR VEHICULO` |
| **P4** | Falta una columna, error de formato o texto; detalle visual; solicitud de capacitación o consulta registrada como fallo | `REPORTE DE VENTAS POR RANGO NO SALE UNA COLUMNA` · `SOLICITA CAPACITACION PARA FLEXPLAY` |

Reglas de decisión:

1. Si el título describe un **reporte** (aunque sea de facturación o liquidación), por defecto es P3. Solo sube si el título dice que impide la operación.
2. Si afecta **facturación individual al cliente** (no se puede emitir, cancelar o timbrar una factura): P2 si hay alternativa evidente; P1 si la estación no puede facturar.
3. "Apoyo a soporte" se clasifica igual que un fallo, por lo que describe el título.
4. Si el título es demasiado vago para decidir (ej. `PANEL CLIENTE- TIPO DE PAGO`), usa P3 y márcalo como dudoso en la entrega.
5. **Pregunta antes de generar** (con `ask_question`, varias preguntas por llamada) en estos casos:
   - el título admite razonablemente dos criticidades **y** la diferencia cambia el "Cumple" de ese caso (compara sus días hábiles contra ambos objetivos);
   - cualquier caso que vayas a clasificar como **P1**.
   Si la duda no cambia el resultado, decide tú y solo menciónalo en la entrega.

Escribe las criticidades en un JSON del scratchpad (no en la carpeta del mes) con todos los IDs evaluables y nada más:

```json
{"TT102398":"P3","TT105979":"P2","TT106471":"P1"}
```

## Paso 3 — Generar el Excel

```bash
node "C:/Users/jorge/.gemini/config/skills/rfallos/scripts/generar.js" YYYYMM "<ruta>/criticidades.json"
```

Agrega `--sobrescribir` como tercer argumento solo si el usuario lo autorizó. El script valida que todos los evaluables tengan una criticidad válida y que no sobren IDs. Si falla, corrige el JSON (no el script) y vuelve a ejecutarlo.

Salida: `$RAIZ\YYYYMM\MMYYYY_RelacionFallosAtendidos.xlsx`, y en consola un JSON con `feriadosDescontados`, `total`, `cumplen`, `cumplimiento`, `clasificacion`, `promedioDias`, `resumen` (por P1–P4), `incumplidos[]` y `cancelados[]`.

### Formato exacto que produce el script (referencia; no lo reproduzcas a mano)

Hoja única llamada `Worksheet`, horizontal, ajustada a una página de ancho. Fuente predeterminada Calibri 11.
Anchos de columna A–G: 86.25 · 12 · 19.75 · 24 · 20.75 · 12 · 10.
Las celdas de encabezado llevan relleno sólido `#4F81BD` y texto blanco. Todas las fechas usan el formato `dd/mm/yyyy`.

1. **Fila 1 (encabezado A–G):** `Título | Criticidad | Asignación de caso | Fecha real de respuesta | Tiempo de atención | Objetivo | Cumple`.
2. **Filas de detalle**, una por caso evaluable, ordenadas por número de TT ascendente:
   - A: título tal cual viene de VTiger, sin corregir errores de captura.
   - B: P1–P4, centrado.
   - C y D: fechas.
   - E: `=NETWORKDAYS(Cn,Dn[,feriados])` con formato `0`. Con un feriado usa `DATE(a,m,d)`; con varios, una constante matricial de seriales `{46281,...}`; sin feriados, solo dos argumentos.
   - F: `=VLOOKUP(Bn,$A$<P1>:$B$<P4>,2,FALSE)` contra la tabla de resumen, centrado.
   - G: `=IF(En<=Fn,"Sí","No")`, centrado.
3. **Fila de promedio** (inmediatamente después del detalle): D = `Promedio` y E = `=AVERAGE(E2:E<n>)` con formato `0.00`; D y E llevan estilo de encabezado.
4. Una fila vacía.
5. **Resumen por criticidad:** encabezado A–E `Criticidad | Objetivo (días hábiles) | Fallos evaluables | Dentro del objetivo | Cumplimiento`, seguido de las filas P1, P2, P3 y P4 con `COUNTIF`, `COUNTIFS(...,"Sí")` e `IF(C=0,"N/A",D/C)` en formato `0.00%`; las columnas B–E van centradas.
6. **Fila Total** (A–E con estilo de encabezado): `SUM` de evaluables, `SUM` de los que cumplen y `D/C` en `0.00%`.
7. **Fila Clasificación:** D = `Clasificación` y E = `IF` anidado según la matriz; D y E con estilo de encabezado.
8. Una fila vacía y, si hay cancelados, el bloque **`Casos no evaluables (cancelados) | Estatus | Asignación de caso | Fecha real de respuesta`** (encabezado A–D), con una fila por caso cancelado y "Cancelado" centrado. Es lo último de la hoja.
9. **No lleva notas al pie:** no se agregan textos explicativos (tiempo de atención, feriados u objetivos) debajo de las tablas. Los feriados descontados solo se informan en el chat (paso 5).

Referencia visual: `$RAIZ\202609\092026_RelacionFallosAtendidos.xlsx`. El script reproduce ese formato en valores, fórmulas y estilos.

## Paso 4 — Verificar

Vuelca el xlsx generado con la librería `xlsx` desde `$SK\scripts` (por ejemplo `node -e` con `require('C:/Users/jorge/.gemini/config/skills/rfallos/scripts/node_modules/xlsx')`) y confirma:
- que hay tantas filas de detalle como evaluables y tantas de cancelados como `cancelados`;
- que el total, los que cumplen, el % y la clasificación coinciden con el JSON de salida.

## Paso 5 — Entregar (en el chat, breve)

1. La ruta del archivo creado.
2. El resultado: **X de N fallos dentro del objetivo = P%, CLASIFICACIÓN**, y el promedio de días hábiles.
3. Una tabla con Criticidad | Objetivo | Evaluables | Cumplen | %.
4. Los incumplidos: ID, criticidad, días contra objetivo y una descripción corta.
5. Las criticidades discutibles: los casos donde dudaste, la criticidad elegida y si cambiar de nivel alteraría su "Cumple".
6. Los feriados descontados y los casos cancelados excluidos.

No hagas commits (la carpeta no es repositorio) ni generes PDF salvo que te lo pidan.
