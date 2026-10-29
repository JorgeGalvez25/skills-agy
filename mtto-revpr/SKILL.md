---
name: mtto-revpr
description: Revisa todos los pull requests de Azure DevOps (igasmxproyectos) de una versión de Mantenimiento. Toma los TT del archivo de acuerdos (Acuerdos_IGAS_RSP.xlsx en C:\Users\jorge\Dropbox\MTTO\Versiones\<versión>), localiza sus PR, baja el código base/head, lo revisa con subagentes contra los acuerdos del Excel, el informe interno de /mtto-docu y la nota Atencion_Especial_<versión>.md, detecta conflictos entre PR y guarda un informe por caso más un índice en <versión>\Revision_PR. Usar cuando digan "/mtto-revpr", "revisa los PR de la versión", "revisa los pull request de la 4.3.x.y", "code review de la versión", "me mandaron un montón de PR", "qué PR puedo aprobar" o pidan revisar PR de Azure DevOps de una versión, aunque no mencionen el Excel.
argument-hint: "[versión, p. ej. 4.3.13.0 (default: carpeta actual)]"
---

# Revisión de PR de una versión (/mtto-revpr [versión])

- **Carpeta:** `C:\Users\jorge\Dropbox\MTTO\Versiones\<versión>`. Sin argumento, se usa el directorio de trabajo actual si su nombre es una versión (`4.3.x.y`); si no lo es, preguntar.
- **Entrada:**
  - `Acuerdos_IGAS_RSP.xlsx`: hoja `RSP` con ID, Responsable, Tester, Complejidad, Acuerdos y Módulos. Es obligatorio; si no existe, hay que correr antes `/mtto-acuerdos`.
  - `Atencion_Especial_<versión>.md` (opcional): nivel de cada caso y hallazgos H1/H2 a vigilar.
  - Los comprimidos de los colaboradores con los informes `.md` de `/mtto-docu`.
  - Azure DevOps de la organización `igasmxproyectos`.
- **Salida:** `<carpeta>\Revision_PR\` con un `TT#####.md` por caso y `00_Resumen_Revision_PR_<versión>.md`.
- **Solo lectura en Azure DevOps.** No se aprueba, no se vota y no se comenta en los PR, a menos que Jorge lo pida explícitamente después de ver los informes.
- No hay Python en el equipo: todo corre con PowerShell y los scripts de `scripts\`, que comparten `comun.ps1`. Los `.ps1` se guardan en UTF-8 con BOM.

## Token

Los scripts leen `AZURE_DEVOPS_EXT_PAT`, primero de la sesión y luego de la variable de usuario de Windows. Si `preparar.ps1` termina con `SIN_TOKEN` o `TOKEN_INVALIDO`, explicarle a Jorge cómo resolverlo:

1. En Azure DevOps, ir al engrane con persona (arriba a la derecha) → **Personal access tokens** → **+ New Token**.
   - Organización: `igasmxproyectos`.
   - Vigencia: 90 días.
   - Scope: *Custom defined* → **Code: Read**.
   - El token que crea Git Credential Manager ("Git: https://dev.azure.com/…") no sirve: su valor no se puede ver y vence en un día.
2. Guardarlo desde una ventana de PowerShell propia, no en el chat, para que no quede en el historial:
   `[Environment]::SetEnvironmentVariable('AZURE_DEVOPS_EXT_PAT','<token>','User')`
3. Avisar cuando esté listo y repetir el paso 1.

Si Jorge pega el token en el chat, usarlo solo en esta sesión (`$env:AZURE_DEVOPS_EXT_PAT = '…'` dentro del mismo comando) y recomendarle revocarlo al terminar.

## Pasos

1. **Preparar** (un solo comando, tarda unos 2 minutos):
   ```powershell
   & "C:\Users\jorge\.gemini\config\skills\mtto-revpr\scripts\preparar.ps1" -Carpeta "<carpeta>" -Salida "<scratchpad>\revpr"
   ```
   Hace lo siguiente:
   - Lee el Excel y la nota.
   - Extrae los `.md` de los comprimidos.
   - Busca en Azure DevOps los PR de cada TT por número de TT en la rama o el título, en cualquier estado.
   - De cada PR activo baja `pr.md`, `diff.patch` y los archivos `base\` y `head\`.
   - Prueba la integración (`git merge-file`) de los archivos que modifican varios casos.

   Escribe `casos.json` y `digest.md` e imprime el digest: tabla de casos con sus PR, avisos y cruces. Con el digest basta para planear; `casos.json` es para los subagentes.
   - Si un caso no tiene PR activo, no se revisa: va al índice en "Casos sin PR para revisar". Los PR completados se listan como "ya integrado".
   - **Si hay PR activos que no están en el Excel**, preguntar si se revisan. Si la respuesta es sí, agregar su TT a mano a la asignación del agente correspondiente.

2. **Mostrar el plan y arrancar sin esperar confirmación:** número de PR y casos, los avisos del digest y el reparto de agentes en una tabla. Jorge ya pidió la revisión al invocar el skill.

3. **Revisar con subagentes** en paralelo: todos los subagentes en una sola llamada a `invoke_subagent` (`TypeName: "self"`, `Role: "Revisor PR <TTs>"`, `Model: "inherit"`), con el prompt de `references\revisor.md`.
   - **Reparto:** de 4 a 6 agentes, con un máximo de unas 4 000 líneas de diff y 4 TT por agente.
   - Los casos que comparten archivos según `cruces` van con el mismo agente siempre que se pueda. Si no, cada agente recibe el cruce en su asignación.
   - Los Crítico grandes, como TT101184 con 3 PR, van solos.
   - En "Tu asignación" escribir, por cada TT:
     - los PR;
     - el nivel y el porqué según la nota;
     - los H1/H2 a verificar;
     - los acuerdos concretos del Excel;
     - los riesgos propios del caso (dinero o fiscal, firmas `.rodl`, variables, `.dfm` enormes);
     - los cruces que le tocan.
   - Mientras trabajan, avisar a Jorge de cada agente que termine: veredicto y hallazgo más grave por TT, en 3 a 6 viñetas. No inventar resultados de agentes que siguen en curso.

4. **Verificar los hallazgos Alta** antes de darlos por buenos. Leer el código en `head\` (y `base\` o el diff) en las líneas citadas y confirmar que el problema existe tal como se describe. Por ejemplo, que el código "eliminado" no se haya movido a otra parte del archivo, o que el campo nulo de verdad no se envíe.
   - Confirmar también que la unidad y las líneas de "Cambios requeridos" son las correctas y que el mensaje para el solicitante dice lo mismo que el hallazgo.
   - Si un Alta no se sostiene, corregir el informe con Edit (bajar la severidad o quitar el hallazgo con su bloque de cambios) y decirlo en el resumen.
   - Si un informe trae hallazgos de estilo o sin escenario concreto, quitarlos.

5. **Contar e indexar:**
   ```powershell
   & "C:\Users\jorge\.gemini\config\skills\mtto-revpr\scripts\contar.ps1" -Reportes "<scratchpad>\revpr\reportes"
   ```
   - Imprime el veredicto y los hallazgos por severidad de cada TT, y los totales. Si un informe sale con veredicto vacío o con conteos que no cuadran con lo que reportó su agente, el formato quedó mal: corregirlo antes de seguir.
   - Escribir `<scratchpad>\revpr\reportes\00_Resumen_Revision_PR_<versión>.md` con la plantilla de `references\indice.md`. Los números se toman de `contar.ps1`, nunca se cuentan a mano.

6. **Guardar:** copiar `reportes\*.md` a `<carpeta>\Revision_PR\`. Si la carpeta ya existe, primero respaldarla en `<scratchpad>\revpr\respaldo_Revision_PR` y mencionarlo en el resumen.

7. **Resumen a Jorge:**
   - la ruta de la carpeta;
   - el conteo de veredictos y hallazgos;
   - lo más urgente, en 3 a 5 puntos: hallazgos Alta, H1/H2 que siguen abiertos, acuerdos sin cumplir y conflictos entre PR;
   - qué casos se pueden aprobar sin observaciones.

   No pegar los informes completos. Al final, ofrecer en una línea publicar los hallazgos como comentarios en los PR. Eso requiere un token con **Code: Read & write** y aprobación expresa.

## Criterios

- **Solo hallazgos importantes:** cada hallazgo debe obligar al desarrollador a cambiar el código, con un escenario concreto de falla. Estilo, refactors y riesgos teóricos no se reportan.
- **Sugerencias accionables:** cada hallazgo trae en "Cambios requeridos" la unidad o unidades, las líneas y el método que hay que cambiar, y el mensaje listo para enviar al solicitante del PR.
- **Revisión estática:** no se compila ni se ejecuta. Lo que dependa de procedimientos almacenados, triggers, scripts de BD o clases fuera del diff es "No verificable", no un hallazgo.
- **`.dfm` re-guardados:** un `.dfm` de miles de líneas de diff suele ser ruido del IDE (imágenes recodificadas). El revisor separa ese ruido de los cambios reales; el tamaño del diff, por sí solo, no es un hallazgo.
- **Acuerdos del Excel:** son compromisos de la reunión de versión. Si un acuerdo concreto no está en el PR (p. ej. "Se aplicará StrToIntDef"), se pide cambios aunque el resto esté bien.
- **Cruces con CONFLICTO:** van en el informe de los dos TT y en "Riesgos de integración" del índice. Hay que explicar qué corrección se pierde según cómo se resuelva, porque un conflicto mal resuelto puede compilar sin errores.
- **Sin base común:** los dos PR parten de commits distintos de `main` para ese archivo, así que el script no puede probar la integración. Se anotan para revisarlos a mano al integrar.
- **Nombres:** se escriben como en el Excel (Martín Reyes, Miguel Armenta, Saulo López, Susana Gámez).
