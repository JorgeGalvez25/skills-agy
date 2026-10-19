---
name: limpieza-equipo
description: Revisa, desinfecta y deja limpio un equipo Windows. Detecta malware, adware, troyanos, extensiones de navegador maliciosas y manipulaciones del antivirus; los elimina con aprobación del usuario; corre el análisis completo de Defender y entrega un informe. Usar cuando digan "/limpieza-equipo", "revisa si mi equipo tiene virus", "veo procesos sospechosos", "creo que tengo malware", "limpia mi computadora", "Defender no detecta nada pero algo raro pasa", "revisa esta grabación o captura del Administrador de tareas", "haz el seguimiento de la limpieza" o cualquier sospecha de infección o lentitud rara en Windows, aunque no digan la palabra malware.
---

# Limpieza de equipo Windows (/limpieza-equipo)

Tu trabajo es averiguar si el equipo está comprometido, eliminar la amenaza **sin romper lo que el usuario usa legítimamente**, comprobar que el antivirus vuelve a ver todo, y dejar un informe claro de qué pasó y qué falta.

**Carpeta de la skill** (`$SK`): `C:\Users\jorge\.claude\skills\limpieza-equipo`.
**Carpeta del incidente** (`$INC`): crea `%USERPROFILE%\Documents\Incidentes\AAAA-MM-DD` al empezar. Ahí van el reporte de auditoría, los registros, los respaldos de registro (`.reg`), los hashes y el informe final. Así la evidencia sobrevive a reinicios y puede pasarse a TI.

## Principios (por qué importan)

- **Nunca ejecutes una muestra sospechosa.** Léela como texto (`[IO.File]::ReadAllText`) o con `inspeccionar-script.ps1`. Un `.vbs` o un `.js` sin extensión se ejecuta con solo invocarlo.
- **Primero observa, luego actúa.** Toda la fase de diagnóstico es de solo lectura. Antes de borrar algo, muestra qué es, por qué crees que es malicioso y pide aprobación. Lo que borres no se recupera y el usuario pierde la evidencia.
- **Respalda antes de cambiar el registro.** Usa `reg export <clave> <archivo>`, sin `/y`, porque el arnés lo confunde con una ruta y bloquea el comando. Guarda el hash SHA256 antes de borrar un archivo.
- **Lo legítimo se queda.** Herramientas de control remoto (VNC, EShare, WonderCast, AnyDesk), activadores, cracks o software viejo pueden ser decisión del usuario. Pregunta antes de quitarlos y explica el riesgo sin sermonear.
- **"Defender no encontró nada" no prueba nada** mientras no hayas verificado que no tiene exclusiones ni amenazas en "Permitir". El malware de este tipo suele cegar al antivirus antes de cualquier otra cosa.
- **Sé honesto con la incertidumbre.** Si la infección fue larga o hubo un troyano de acceso remoto (RAT), di claramente que reinstalar Windows es lo único que da certeza total.

## Lo que necesitas pedir al usuario

Pídelo solo cuando lo necesites, no todo al principio:

1. **Síntoma (opcional):** qué notó y desde cuándo. No pidas grabaciones: los procesos los obtienes tú con `vigilar-procesos.ps1`. Si el usuario ya tiene una, aprovéchala.
2. **Permisos de administrador:** son necesarios para la auditoría completa y la remediación. Ofrece dos caminos:
   - Opción recomendada: cerrar Claude Code, abrir **Terminal (Administrador)** con `Win + X` y ejecutar `claude --continue`.
   - Alternativa: que el usuario ejecute él mismo los scripts en una terminal de administrador y te avise.

   Comprueba si ya tienes los permisos con `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')`.
3. **Qué instaló a propósito:** confírmalo antes de quitar herramientas remotas, activadores o software sin firma.
4. **Si el equipo es corporativo:** pregunta si TI debe enterarse antes de borrar nada, porque quizá quieran conservar evidencia.
5. **Aprobación explícita** antes de cada paso destructivo.
6. **Para el análisis completo:** que el equipo esté **conectado a la corriente**, y qué hacer al terminar (apagar, reiniciar o nada).

## Flujo de trabajo

### Fase 0 · Vigilancia de procesos (no requiere nada del usuario)

La skill obtiene los procesos por su cuenta; **no pidas una grabación**. Una foto instantánea (como la de la auditoría) se pierde los procesos intermitentes, como un `wscript` que una tarea lanza cada pocos minutos. Por eso vigila un rato los procesos que nacen:

```powershell
& "$SK\scripts\vigilar-procesos.ps1" -Minutos 10 -Salida "$INC\vigilancia.txt"
```

Con administrador usa el evento `Win32_ProcessStartTrace` y atrapa incluso los procesos de milisegundos, con su línea de comandos y su padre; sin administrador sondea cada segundo. Marca con `<<<` los intérpretes de scripts, las rutas raras y lo que lanza el Programador de tareas. Como dura varios minutos, ejecútalo en segundo plano (usando `run_command` con `WaitMsBeforeAsync: 500`) mientras haces la auditoría. Si los síntomas son esporádicos (ventanas que parpadean, ventiladores a ratos), alarga a 30–60 minutos.

**Si el usuario ya trae una grabación o captura** del Administrador de tareas, úsala como pista adicional:

```powershell
& "$SK\scripts\extraer-fotogramas.ps1" -Video "<ruta.mp4>" -OutDir "$INC\fotogramas" -Step 3
```

El script usa las APIs de Windows; no requiere ffmpeg ni Python. Los fotogramas son muchas imágenes: **no los leas tú**. Delega su lectura a un subagente (invocando `invoke_subagent` con `TypeName: "research"`, `Role: "Inspector de Fotogramas"`, `Model: "pro"`) con la carpeta `$INC\fotogramas` y pídele una lista compacta (proceso, descripción, CPU/memoria/red, fotogramas donde aparece) de lo que encuentre. Que lea todos los fotogramas y anote nombres raros, procesos de script (`Windows Based Script Host`), herramientas de control remoto y consumos anormales. Confírmalo después en el sistema real: una grabación no muestra rutas ni procesos padre.

### Fase 1 · Auditoría (solo lectura)

```powershell
powershell -ExecutionPolicy Bypass -File "$SK\scripts\auditoria.ps1" -Salida "$INC\auditoria.txt"
```

La auditoría cubre:
- Arranque automático: tareas programadas, servicios, claves Run, Winlogon, IFEO, AppInit y suscripciones WMI.
- Procesos sin firma y conexiones de red.
- **Manipulación de Defender:** exclusiones normales y por política, `ThreatIDDefaultAction` y el historial de cambios (evento 5007).
- Carpetas con nombre aleatorio, incluido el rastro histórico en `VirtualStore`.
- Carpetas con permisos *Deny* para Todos.
- Programas sin fabricante, extensiones y políticas de los navegadores.
- Archivo hosts, proxy, DNS, certificados raíz y cuentas de administrador.

Tarda unos 7 minutos (lo más lento es buscar ejecutables sin firma en el disco), así que lánzala con `run_in_background: true`, en paralelo con `vigilar-procesos.ps1`. Con permisos de usuario normal sale incompleta, y el script lo avisa. Lee el reporte por secciones (`Grep` de `^====` y luego `Read` con offset) en vez de leerlo entero.

Clasifica cada hallazgo con `references/indicadores.md`, que distingue lo malicioso de los falsos positivos habituales.

### Fase 2 · Análisis de lo sospechoso

- **Scripts:** `& "$SK\scripts\inspeccionar-script.ps1" -Ruta <archivo>` saca el hash, los URL y los textos ofuscados con XOR, decodificados de forma estática. Así sabes a qué servidores se conecta y qué descarga.
- **Procesos:** revisa los marcados con `<<<` en `vigilancia.txt` (búscalos con `Grep`, no leas el archivo entero); ya traen su línea de comandos y su padre. Si el padre es «svchost (Programador de tareas)», lo lanzó una tarea programada: búscala en la auditoría. Si es `WmiPrvSE.exe`, revisa las suscripciones WMI. Para un proceso concreto, sigue la cadena con `Win32_Process` (ParentProcessId).
- **Fechas:** cruza las fechas de creación de carpetas, archivos, tareas y eventos 5007 de Defender. Todas las piezas de una instalación suelen nacer en el mismo minuto. **Busca todo lo creado en esa ventana**, sin importar el nombre; así encontramos DLL que el patrón de nombres no detectaba.
- **Historial:** las carpetas vacías de `VirtualStore` y los eventos 5007 revelan cuánto tiempo lleva la infección. Fecha el inicio.
- **Origen:** las exclusiones del tipo `E:\Programa.exe`, `C:\` o `.exe/.dll/.wsf` suelen delatar el activador o crack que pidió desactivar el antivirus.

Antes de remediar, presenta al usuario un resumen: qué es, cuánto lleva, qué hace, cómo persiste y qué propones eliminar.

### Fase 3 · Remediación (con aprobación y permisos de administrador)

Orden recomendado, porque así el malware no tiene cómo reinstalarse a mitad de la limpieza:

1. **Matar procesos** del malware (`Stop-Process`).
2. **Eliminar la persistencia:** `& "$SK\scripts\eliminar-tareas.ps1"`. Sin parámetros solo lista las tareas sospechosas; con `-Nombres a,b -Aplicar` las elimina.
3. **Devolverle la vista a Defender:** `& "$SK\scripts\quitar-manipulacion-defender.ps1" -Respaldo $INC`. Sin `-Aplicar` solo muestra lo que haría. Quita las exclusiones normales y por política y los `ThreatIDDefaultAction`, y activa el bloqueo de aplicaciones no deseadas y la protección en la nube.
4. **Borrar archivos y carpetas:** `& "$SK\scripts\borrar-protegido.ps1" -Rutas <...> -Respaldo $INC -Aplicar`. Guarda los hashes y quita la regla *Deny* que el malware pone para impedir el borrado.
5. **Navegadores:** pide al usuario que quite la extensión en `edge://extensions` (o el equivalente) y que cierre el navegador **por completo**, porque sigue vivo en segundo plano. Después borra la carpeta de la extensión y las políticas `HKLM\SOFTWARE\Policies\Microsoft\Edge` (o Chrome o Brave) que no vengan de su organización. Comprueba antes con `dsregcmd /status` que el equipo no está gestionado por MDM o un dominio. Esas políticas son las que hacen aparecer "Administrado por su organización".
6. **Restos:** entradas de desinstalación falsas (no ejecutes su "desinstalador", que suele ser el propio DLL malicioso), carpetas vacías en `VirtualStore` y `Temp`.
7. **Verificar** volviendo a correr la auditoría o `seguimiento.ps1`.

Pequeños fallos de un paso no detienen el resto: reporta y sigue.

### Fase 4 · Análisis completo de Defender

```powershell
powershell -ExecutionPolicy Bypass -File "$SK\scripts\analisis-completo.ps1" -Log "$INC\analisis.txt" [-Apagar]
```

Lánzalo con `run_in_background: true`; tarda de 1 a 4 horas. El script:
- Evita la suspensión **solo con el equipo en corriente alterna**.
- Actualiza las firmas.
- Recopila las detecciones con su ruta y la acción que tomó Defender.
- Restaura la configuración de energía.
- Con `-Apagar`, programa un **apagado de respaldo** a los 30 minutos. Cuando termines de analizar los resultados, cancélalo con `shutdown /a` y apaga tú.

Defender no permite pausar un análisis: solo cancelarlo (`MpCmdRun.exe -Scan -Cancel`) y empezar de cero.

Analiza cada detección y explícala: qué familia es, si es grave, dónde estaba, si quedó en cuarentena y si puede volver. Por ejemplo, un archivo dentro de un repositorio SVN o Git vuelve a aparecer con un `update`.

### Fase 5 · Endurecimiento y pendientes del usuario

Comprueba lo que puedas y deja en una lista lo que solo el usuario puede hacer:
- **Protección contra alteraciones:** solo se activa a mano. Pásale `windowsdefender://threatsettings`, pídele que la active y luego verifica con `(Get-MpComputerStatus).IsTamperProtected`.
- **SmartScreen y bloqueo de aplicaciones no deseadas** en `edge://settings/privacy/security`.
- **Contraseñas y sesiones:** si hubo una extensión con permiso de cookies o un RAT, deben cambiarse **desde otro dispositivo** y **cerrar todas las sesiones**; cambiar la contraseña sola no invalida las cookies robadas. Usa la lista de `references/indicadores.md` (sección "Cuentas a rotar").
- **Actualizaciones pendientes:** instálalas y reinicia, avisando antes.
- **Herramientas legítimas pero riesgosas:** actualizarlas o poner sus servicios en inicio manual.
- **Avisar a TI** con el informe.
- **Revisión de seguimiento** unos días después: `& "$SK\scripts\seguimiento.ps1" -Indicadores "$INC\indicadores.json"`. Guarda en ese JSON los dominios, nombres de tareas y rutas del caso.

### Fase 6 · Informe

Escribe `$INC\informe.md` y entrega en el chat un resumen con esta estructura:

```markdown
# Informe de limpieza — <equipo> — <fecha>
## Veredicto
## Qué era (familia, cómo persistía, qué hacía, desde cuándo)
## Línea de tiempo
## Lo que se eliminó (con rutas y hashes)
## Manipulaciones del antivirus encontradas y revertidas
## Resultado del análisis completo
## Indicadores de compromiso (hashes, dominios, IP) para TI
## Pendientes del usuario
## Nivel de confianza y recomendación (¿reinstalar?)
```

Al terminar, si se usaron permisos de administrador, recuérdale al usuario que vuelva a abrir Claude Code sin ellos.

## Referencias

- `references/indicadores.md`: qué es malicioso, qué es ruido normal, familias conocidas y cuentas a rotar. Léelo al clasificar los hallazgos de la auditoría.
- `references/trampas.md`: problemas técnicos ya resueltos (PowerShell 5.1, arnés, Edge, energía, WMI). Léelo antes de escribir comandos propios o si algo falla de forma rara.
- `references/caso-neoreblamy.md`: un caso real completo de principio a fin, útil como modelo de razonamiento.
