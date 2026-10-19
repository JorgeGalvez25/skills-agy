---
name: mtto-acuerdos
description: Genera o completa el archivo de acuerdos de una versión (Acuerdos_IGAS_RSP.xlsx en C:\Users\jorge\Dropbox\MTTO\Versiones\<versión>) a partir de los informes internos de /mtto-docu que los colaboradores entregan en .zip/.rar dentro de esa carpeta. Si el Excel no existe lo crea con el formato oficial; asigna el tester de cada caso de forma equitativa y llena Complejidad, Acuerdos, Módulos, Repositorios, Versión y FechaReunion. Usar cuando digan "/mtto-acuerdos", "genera/completa el archivo de acuerdos", "llena los acuerdos de la versión", "asigna testers" o similar.
argument-hint: "[versión, p. ej. 4.3.13.0 (default: carpeta actual)] [fecha reunión dd/mm/aaaa (default: hoy)]"
---

# Acuerdos de versión (/mtto-acuerdos [versión] [fecha])

- **Carpeta:** `C:\Users\jorge\Dropbox\MTTO\Versiones\<versión>`. Sin argumento, el directorio de trabajo actual si su nombre es una versión (`4.3.x.y`).
- **Fecha de reunión (col. L):** el argumento o, sin él, hoy.
- **Entrada:** los comprimidos de cada colaborador (`martin.zip`, `saulo.rar`…), cada uno con el `.docx` para distribuidor y el `.md` de revisión interna de `/mtto-docu`; y, si ya existe, `Acuerdos_IGAS_RSP.xlsx` (hoja `RSP`, tabla `Table2`, columnas A–L: ID, ID Soporte, Descripción, Tipo, Responsable, Tester, Complejidad, Acuerdos, Modulos, Repositorios, Versión, FechaReunion).
- **Salida:** el archivo completo. No hay Python en el equipo: todo va por PowerShell + Excel COM con los scripts de `scripts\` (comparten `comun.ps1`: equipo, normalización de nombres y módulos; guardar los `.ps1` en UTF-8 con BOM).
- **Si el Excel no existe** se crea copiando `references\plantilla.xlsx` (formato oficial tomado de la 4.3.11.0: tabla `Table2`, `TableStyleMedium2`, anchos 8 / 11.5 / 62.88 / 6.5 / 19.63 / 18 / 14 / 51.75 / 30.25 / 77.38 / 9.5 / 15.38, texto ajustado en C y H–J, alineación superior, K como texto, L `dd/mm/aaaa`). Los casos salen **solo de los informes** (decisión de Jorge); los TT sin informe no aparecen y se avisan. A–E salen de la ficha del informe:
  - **ID** = TT del nombre; **Descripción** = nombre del archivo tras `_IC_`, normalizado a `TT##### - …`.
  - **Tipo** = `Cambio` si la ficha dice Cambio, si no `Fallo` (Corrección).
  - **ID Soporte** = el otro TT entre paréntesis en "Ticket VTiger" solo si es Fallo; si no hay, o es Cambio, `-`. Los Fallos que quedan en `-` se avisan (el ID de soporte viene de VTiger y a veces no está en el informe).
  - **Responsable** = desarrollador normalizado. Orden de filas: Martín, Miguel, Saulo, Susana; Fallos antes que Cambios; número de TT.
- **Si el Excel existe** no se tocan A–E ni el orden; solo se llena el Tester donde esté vacío y G–L.

## Pasos (no hacer nada más; no leer las versiones anteriores, los criterios ya están aquí)

1. **Digest y casos** (un solo comando; extrae solo los `.md` a `%TEMP%\mttoacu` para evitar rutas de más de 260 caracteres):
   ```powershell
   & "C:\Users\jorge\.claude\skills\mtto-acuerdos\scripts\extraer.ps1" -Carpeta "<carpeta>" -Salida "<scratchpad>"
   ```
   Genera `<scratchpad>\casos.json` (A–F por caso) y `<scratchpad>\digest.md`. Leer el digest completo con Read y `allow_large: true` (una sola lectura; sin esa opción se corta en versiones con muchos casos): trae la tabla de casos (qué TT no tiene informe, tester ya asignado, filas con G/H llenos) y, por informe, las secciones 1 (Ficha), 2 (Resumen técnico), 3.1/3.3 (archivos modificados, BD y configuración) y 4 (hallazgos).
   - Si alguna fila ya tiene G/H llenos, preguntar antes de sobrescribirla.
2. **Redactar** `<scratchpad>\acuerdos.json` con Write: arreglo `[{ "id", "G", "H", "I", "J" }]`, solo para los TT con informe. Saltos de línea dentro de I y J con `\n`. Seguir los criterios de abajo y el ejemplo `references\ejemplo-4.3.12.0.json`.
3. **Asignar testers** (solo a los casos sin tester; usa G e I del paso 2):
   ```powershell
   & "C:\Users\jorge\.claude\skills\mtto-acuerdos\scripts\asignar.ps1" -Carpeta "<carpeta>" -Casos "<scratchpad>\casos.json" -Acuerdos "<scratchpad>\acuerdos.json"
   ```
   Escribe el tester en `casos.json` e imprime la asignación con su motivo y la carga por tester. No ajustar a mano salvo que el resultado rompa una regla (p. ej. "SIN CUPO"); en ese caso editar `casos.json` y explicarlo en el resumen.
4. **Llenar** (crea el archivo desde la plantilla si no existe; si existe lo respalda en el scratchpad y valida que no esté abierto; escribe Tester vacío, G–J del JSON y K–L en todas las filas):
   ```powershell
   & "C:\Users\jorge\.claude\skills\mtto-acuerdos\scripts\llenar.ps1" -Carpeta "<carpeta>" -Casos "<scratchpad>\casos.json" -Json "<scratchpad>\acuerdos.json" -Fecha yyyy-MM-dd -Respaldo "<scratchpad>"
   ```
   Su salida (fila | ID | responsable | tester | complejidad | versión | fecha) es la verificación; no volver a abrir el archivo.
5. **Resumen al usuario** con este formato: qué se llenó o creó y de dónde salió; tabla de carga por tester (casos, Alta, Media, Baja, puntos) y la asignación caso → tester; reparto de complejidad en una tabla (Alta / Media / Baja con sus TT); tabla de los casos donde la complejidad difiere de la que trae el informe; acuerdos con pendientes agrupados por tipo; y la lista "Revisa esto antes de la reunión" (TT sin informe, Fallos sin ID Soporte, fecha usada si fue la de hoy, URLs de repositorio que quedaron en la base del repo).
6. **Casos de atención especial** (mensaje aparte, después del resumen): guardar el análisis en `<carpeta>\Atencion_Especial_<versión>.md` con Write (título "Casos que requieren atención especial — versión <versión>", fecha de reunión y número de casos analizados) y luego mandarlo como el último mensaje. Se analiza con el digest del paso 1 y lo decidido en los pasos 2–4; no se lee nada más. Ver criterios en "Criticidad".

## Criterios de llenado

### G · Complejidad (Alta / Media / Baja)
La calibración de las versiones anteriores es **más baja que la que propone el informe** de `/mtto-docu`. Tomar el informe como referencia y ajustar:
- **Alta:** cambia un contrato entre módulos (firma RemObjects `.rodl`/Intf/Invk del Master, que obliga a actualizar cliente y servidor juntos) junto con lógica de importes/cupones/paquetes; o cálculo fiscal en varios tipos de factura con cambios de BD en 3 o más repos; o funcionalidad grande Tablet + Master.
- **Media:** dos repos con lógica nueva (p. ej. método de socket nuevo Panel→Master); cálculo de precios/importes en liquidaciones aunque sea un solo repo; ajuste automático de importes contables; reinicio automático de un proceso en producción; varios ejecutables con validaciones nuevas; proceso nuevo de importación que crea registros.
- **Baja:** un solo componente o validación (`Assigned`, enlace de `.dfm`, mensaje de una validación, variable con valor por omisión que conserva el comportamiento, un reporte, una pantalla). También dos repos con cambios pequeños (unas cuantas líneas por repo).

Ejemplos 4.3.12.0 (informe → hoja): TT102499 Media→Baja (dos repos, +3 y +18 líneas); TT98105 Alta→Media; TT103931 Alta→Media; TT104035 Media→Baja (solo una variable). Coincidieron: TT91138 Alta, TT102632 Alta, TT101184 Alta, TT102057 Media, TT99917 Media, TT100075 Media, TT103813 Media, y las Bajas de un solo componente.

### H · Acuerdos
- Siempre empieza con **"Se aplicará solución de la evidencia."**. Si no hay nada más que decir, queda solo esa frase.
- Agregar una o dos frases cortas, en futuro impersonal ("Se atenderá…", "Se revisará…", "Se subirán…"), solo con lo que cambie la liberación:
  - Hallazgos **Alta o Media** no atendidos de la sección 4, solo si cambian lo que se entrega en esta versión. Se redactan como la acción concreta que se hará, tomada de la columna Sugerencia, no como "Se atenderán H1 y H2 (…)" (TT103931 H1 → "El ajuste se moverá después de las validaciones del turno y permiso para generar poliza."). Si la causa queda fuera del cambio: "La corrección de X se atenderá en ticket aparte." No se mencionan los Baja ni los Media que son variantes de otro escenario del mismo ajuste, casos secundarios del script o código entregado (p. ej. trigger solo BEFORE INSERT), otros clientes, bitácoras o mejoras (TT103931 H2 y TT99470 H1/H2 no se mencionaron).
  - Hallazgos que dependen de cómo opera el usuario (reimportar un archivo después de un fallo, capturar datos incorrectos, repetir un proceso) no los corrige el sistema: se dejan bajo responsabilidad del usuario (TT103813: "La duplicidad de pólizas al reimportar un archivo después de un fallo queda bajo responsabilidad del usuario.").
  - Cambios **sin commit / pendientes de commit** que haya que subir a la rama.
  - **Orden o simultaneidad de instalación** (Master y Kioscos al mismo tiempo; servicio Master antes que Panel; DLL y XML juntos).
  - **Scripts de BD** no versionados o cambios de tablas: van al ActualizadorBD ("el script se subirá al ActualizadorBD"; nunca "al repositorio de scripts" ni "junto con TT#####"). Si el caso es solo de BD, incluir también los pasos de aplicación en una frase (TT99470: "Se ejecutará el script de DPVGDOCU.TOTALCMB en Gas Consola y se regenerará el layout del periodo en el portal del Convertidor; el script se subirá al ActualizadorBD").
  - **Variable que activa el cambio** ("Se activa con la variable X=Si.").
  - **Fuera de alcance relevante para soporte** (datos ya inconsistentes que soporte debe corregir; algo que no corrige; "se atenderá en ticket aparte").
- Lenguaje funcional, como lo diría el equipo en la reunión: describir lo que el usuario ve, no el nombre del método o las siglas internas (ValidaTurnoCXC y ChecaDerechoEspecialAutor3 → "las validaciones del turno y permiso para generar poliza", no "validaciones de CxC y autorización"). Tablas, campos, triggers y variables sí van tal cual (DGASLIQGTRIGGER2, DPVGDOCU.TOTALCMB).
- Sin backticks, sin rutas de archivo largas.

### I · Módulos y J · Repositorios
Un módulo por línea en I y su URL en la misma posición en J (separados con `\n`). Orden: el módulo principal del caso primero. Catálogo (carpeta del archivo modificado → módulo → URL):

| Carpeta / proyecto | Módulo (I) | Repositorio (J) |
|---|---|---|
| Imagen Ib Gas `Liq/` | Liquidaciones | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib%20Gas?path=/Liq` |
| Imagen Ib Gas `Liq/Auxi` | Modulo auxiliar | `…/Imagen%20Ib%20Gas?path=/Liq/Auxi` |
| Imagen Ib Gas `Gas/` | Igas Administrador | `…/Imagen%20Ib%20Gas?path=/Gas` |
| Imagen Ib Gas `Fag/` | Igas Facturación | `…/Imagen%20Ib%20Gas?path=/Fag` |
| Imagen Ib Gas `Pvg/` | PVG | `…/Imagen%20Ib%20Gas?path=/pvg` |
| Imagen Ib Volumetricos `Kiosko/` | Kiosco | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib%20Volumetricos?path=/Kiosko` |
| Imagen Ib Volumetricos `Master/` (Delphi, IGASMASTER) | Master Delphi | `…/Imagen%20Ib%20Volumetricos?path=/Master` |
| Imagen Ib Volumetricos `Panel Cliente/` | Panel Cliente | `…/Imagen%20Ib%20Volumetricos?path=/Panel%20Cliente` |
| Imagen Ib Volumetricos `Panel Vol 2.0/` | iGas Controlador | `…/Imagen%20Ib%20Volumetricos?path=/Panel%20Vol%202.0` |
| Imagen Ib `Cnt/` | Contabilidad | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib?path=/Cnt` |
| Imagen Ib `Iva/` | Iva | `…/Imagen%20Ib?path=/Iva` |
| Imagen Ib Vtas `Cxc/` | CXC | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib%20Vtas?path=/Cxc` |
| Imagen Ib Libs (`Revisiones/Revi Consola`) | Script consola | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib%20Libs?path=/Revisiones/Revi%20Consola` |
| Imagen Ib Libs (otra ruta o desconocida) | (no se lista aparte) | `https://dev.azure.com/igasmxproyectos/Imagen%20Ib/_git/Imagen%20Ib%20Libs` |
| Hosts `IGas.Master/…` (servicio .NET, incl. Generales y FacturaMasterLogica bajo IGas.Master) | MasterVol | `https://dev.azure.com/igasmxproyectos/MasterNETLegacy/_git/Hosts?path=/IGas.Master` |
| Hosts `IGas.Master.Facturacion` | Master Facturación | `…/Hosts?path=/IGas.Master.Facturacion` |
| MasterNETLegacy/Host43110 | Master Facturación | `https://dev.azure.com/igasmxproyectos/MasterNETLegacy/_git/Host43110` |
| TabletAndroid | Tablet | `https://dev.azure.com/igasmxproyectos/_git/TabletAndroid` |
| VolumetricoWebLegacy | Volumétrico web | `https://dev.azure.com/igasmxproyectos/_git/VolumetricoWebLegacy` |
| EstacionFacCts | EstacionFacCts | `https://dev.azure.com/igasmxproyectos/_git/EstacionFacCts` |
| SVN TransmisorNET | Transmisor | `svn://192.168.0.2/Fuentes Desarrollo/Ramas 2015/ImagenSoft Net/IGas/Volumetricos/TransmisorNET` |
| SVN Nómina | Nómina | `svn://192.168.0.2/Fuentes Desarrollo/Ramas 2015/Imagen Ib Nom/Nom` |
| Caso solo de BD (sin rama; scripts `.sql` en 3.3) | ActualizadorBD | `https://dev.azure.com/igasmxproyectos/ActualizadorBD` |

(`…` = mismo prefijo de la fila anterior del mismo repo; en el JSON siempre escribir la URL completa.)
- Listar solo las carpetas con cambios funcionales: `DDMGAS` compartido dentro de `Gas/` no agrega "Igas Administrador" si el cambio es de Liquidaciones, salvo que el informe lo marque como ejecutable directo con pantalla propia (TT104035 quedó solo Liquidaciones).
- Si una ruta no está en el catálogo, usar la URL base del repo y mencionarlo en "Revisa esto antes de la reunión".

### K · Versión y L · FechaReunion
Las pone `llenar.ps1` en todas las filas: K = nombre de la carpeta (texto), L = fecha de reunión (`dd/mm/aaaa`).

### Criticidad (paso 6)
Se mide por el impacto en el cliente si algo sale mal en producción, no por la complejidad del código. Señales, de mayor a menor peso:
- **Dinero o fiscal:** cambia importes, precios, pagos, cupones o paquetes; pólizas contables; cálculo de impuestos o timbrado de CFDI.
- **Modifica datos sin intervención del usuario:** UPDATE o ajustes automáticos en tiempo de ejecución, scripts con carga masiva o migración, triggers nuevos.
- **Instalación coordinada:** cambio de firma entre módulos (Master/Kioscos, Master/Panel), orden obligatorio de instalación, DLL y XML juntos, cambios de BD que deben ir en el ActualizadorBD.
- **Alcance amplio:** unidad compartida usada por muchos ejecutables (DDMGAS, DDMLIQ), varios repos o procesos automáticos de producción (servicios, reinicios, controlador).
- **Pendientes que bloquean la liberación:** hallazgos Alta/Media sin atender, cambios sin commit, scripts no versionados, causa raíz abierta ("se atenderá en ticket aparte"), riesgo Alto/Medio en la ficha del informe. No cuentan los hallazgos que quedaron bajo responsabilidad del usuario en el acuerdo.
- **Prueba difícil:** el tester asignado no tiene historial en ese módulo (motivo del paso 3), o el caso requiere hardware, BD del cliente o un escenario difícil de reproducir.

Formato del mensaje:
- Tabla ordenada de mayor a menor criticidad, con 3 a 6 casos como máximo: TT · Nivel (**Crítico** / **Atención**) · Responsable → Tester · Por qué (una o dos señales concretas del informe, en lenguaje funcional) · Qué cuidar (qué confirmar en la reunión o qué escenario debe probar el tester).
- **Crítico:** dinero/fiscal o datos modificados automáticamente, con al menos otra señal. **Atención:** una sola señal relevante.
- Si un tester concentra dos o más casos Crítico, decirlo en una línea para que se valore reasignar.
- Los casos con alguna señal que no entraron en la tabla van en una línea "También con una señal: TT… (motivo breve)".
- Al final, una línea con los casos que no requieren atención especial ("El resto son cambios acotados: TT…, TT…").
- Si ningún caso tiene señales, decirlo en una línea. No repetir el resumen del paso 5.

### Filas sin informe
No se inventan: G–J quedan vacías (como TT91675 en 4.3.11.0) y solo reciben K y L. Avisarlo en el resumen.

### F · Tester (lo asigna `asignar.ps1`)
Desde la 4.3.7.0 no hay testers dedicados: el equipo de Mantenimiento (Martín Reyes, Miguel Armenta, Saulo López, Susana Gámez; lista en `comun.ps1`) se prueba de forma cruzada. Reglas, en orden de prioridad (acordadas con Jorge):
1. **Nadie prueba sus propios casos.**
2. **Cantidad equitativa:** diferencia máxima de 1 caso entre testers (contando los que ya traían tester).
3. **Complejidad repartida:** los Alta y Media se asignan primero, al tester con menos puntos pesados acumulados (Alta=3, Media=2), para que nadie concentre los casos difíciles.
4. **Afinidad por historial de módulos:** entre los que tienen cupo, se prefiere a quien más ha probado esos módulos en versiones anteriores (Tablet→Susana, Contabilidad/IVA→Miguel, Liquidaciones→Martín/Miguel…), con una penalización si ya recibió casos del mismo desarrollador en esta versión, para que cada desarrollador reparta sus casos entre los otros tres.
- El historial vive en `references\historial.csv` (caché); el script agrega solo las versiones nuevas (≥ 4.3.7.0 y anteriores a la actual) leyendo su Excel.
- Los nombres se normalizan (Gamez/Gómez → **Susana Gámez**). `llenar.ps1` también corrige el Responsable y el Tester que ya estaban escritos en el Excel. Los casos sin informe cuentan con peso 1 y sin afinidad.
- Si el equipo cambia, actualizar `$Equipo` en `comun.ps1`.
