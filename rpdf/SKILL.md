---
name: rpdf
description: Genera la versión PDF de los reportes mensuales de indicadores del Departamento de Mantenimiento (todos los .xlsx y .docx de la carpeta de trabajo actual) en la subcarpeta PDF, que crea si no existe, con el tamaño de página adecuado y sin texto recortado. Se ejecuta desde la carpeta del mes y no pide argumentos. Usar cuando digan "/rpdf", "genera los PDF de los reportes", "pasa a PDF los reportes" o "versión PDF de los reportes".
---

# PDF de los reportes mensuales (/rpdf)

Conviertes a PDF los reportes del mes (normalmente 6: 4 Excel + 2 Word) y verificas visualmente que no falte información.
**Todo lo hace el script `rpdf.ps1`.** No escribas código propio ni ajustes la configuración de página a mano: el script ya resuelve los casos conocidos.

**Carpeta de la skill** (`$SK`): `C:\Users\jorge\.claude\skills\rpdf`.
**Carpeta de reportes**: el directorio de trabajo actual. El usuario corre la skill desde la carpeta del mes, así que **no pidas mes ni ruta**.
- Entrada: `.\*.xlsx` y `.\*.docx`.
- Salida: `.\PDF\<mismo nombre>.pdf`. El script crea la carpeta `PDF` si no existe. Si ya hay un PDF con el mismo nombre, se sobrescribe.

Requiere Excel y Word instalados (se usan por COM). No hay Python en el equipo.

## Pasos

1. **Ejecuta**, sin argumentos, con la herramienta PowerShell, en primer plano y con `timeout` de 600000. El script toma la carpeta actual:
   ```powershell
   & "C:\Users\jorge\.claude\skills\rpdf\scripts\rpdf.ps1"
   ```
   Tarda alrededor de 1 minuto. La salida incluye:
   - `ENTRADA`: los archivos encontrados. Si no son 6, menciónalo al final, pero no te detengas.
   - Si la carpeta no tiene `.xlsx` ni `.docx`, termina con un `ERROR` y no crea nada: avisa al usuario que debe correr la skill desde la carpeta de los reportes.
   - `CREADA`: indica que se creó la carpeta `PDF`.
   - `HOJA ...`: el papel, la orientación y la escala elegidos para cada hoja. `OMITIDA (oculta)`: hojas ocultas que no se imprimen.
   - `ensancha` / `reduce fuente`: las celdas cuyo texto no cabía y cómo se corrigieron.
   - `ERROR ...`: cualquier error o paso que excedió su tiempo límite.
   - `PNG ...`: una imagen por página, en `%TEMP%\rpdf_<nombre de la carpeta>\`.
2. **Verifica visualmente** **solo las imágenes de páginas que vienen de Excel**. Las de Word salen fieles al original y no hace falta revisarlas.
   Las imágenes cuestan muchos tokens: **no las leas tú**. Delega la revisión a un subagente (invocando `invoke_subagent` con `TypeName: "research"`, `Role: "Inspector Visual de Reportes"`, `Model: "pro"`)
   pasándole las rutas de los `PNG` de Excel y estos criterios; en cada imagen debe comprobar que:
   - no haya texto cortado en títulos, encabezados ni celdas;
   - las gráficas aparezcan completas;
   - no haya columnas ni filas fuera de la página;
   - y anotar caracteres raros (□□) que vengan del original.

   Pídele que responda solo con `imagen | OK` o `imagen | problema concreto (hoja, celda o zona)`. Abre tú con `view_file` únicamente las imágenes que marque con problema, para confirmarlo.
   Si todo está bien, no hagas nada más.
3. **Reporta** en una tabla breve: cada PDF con su papel, orientación y escala. Agrega, en una línea cada uno:
   - los ajustes de `ensancha` y `reduce fuente`;
   - las hojas ocultas omitidas;
   - cualquier anomalía que venga del archivo original, por ejemplo caracteres □□. Esas no se corrigen.

## Qué hace el script (para diagnosticar si algo sale mal)

- **Excel** (`exportar-excel.ps1`): abre cada libro de solo lectura, hace los ajustes en memoria y lo cierra **sin guardar**. Los originales nunca se modifican. Por cada hoja visible:
  - **Área de impresión**: el rango usado, ampliado para que quepan las gráficas que se salen de él.
  - **Texto que no cabe**: lo mide con GDI+.
    - En tablas sin gráficas, ensancha la columna para que cada fila quede en una sola línea.
    - En hojas con gráficas o en celdas combinadas, activa `ShrinkToFit`, para no mover el diseño.
    - No usa ajuste de texto (`WrapText`): con él, Excel calcula mal la altura de las filas y parte encabezados.
  - **Papel**: el más chico (Carta → Oficio → Tabloide) con su mejor orientación, siempre que deje una escala de al menos 70 %. Si ninguno llega, usa el de mayor escala. Siempre ajusta 1 página de ancho × 1 de alto y márgenes de 0.5".
  - **`PrintCommunication = $false`** mientras cambia `PageSetup`: sin esto, cada hoja tarda minutos.
- **Word** (`exportar-word.ps1`): copia el documento a una carpeta temporal y exporta con `SaveAs2(..., 17)`, pasando las rutas como `[string]`. Con `ExportAsFixedFormat`, Word se quedaba colgado.
- **Orquestador** (`rpdf.ps1`):
  - Corre cada paso con `Start-Job` y un tiempo límite. Con `Start-Process`, Word por COM no responde.
  - Al final cierra las instancias ocultas de Excel/Word que abrió (sin ventana y que no existían antes).
- **Render** (`render.ps1`): convierte cada página de PDF a PNG con la API `Windows.Data.Pdf`.

## Si algo falla

- **`ERROR: <paso> excedió N min`**: revisa en el Administrador de tareas si quedó un `EXCEL`/`WINWORD` oculto, ciérralo y vuelve a ejecutar una vez. Si se repite, avisa al usuario con el mensaje exacto.
- **Una imagen muestra texto cortado que el script no detectó**: dile al usuario qué celda es. Si es un caso nuevo, propón ajustar la regla en `exportar-excel.ps1` en lugar de parchar el PDF a mano.
