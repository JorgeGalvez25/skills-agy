# Trampas técnicas ya resueltas

## PowerShell 5.1 (el predeterminado de Windows)
- **Acentos rotos y errores raros de sintaxis** ("Falta la cadena en el terminador"): el `.ps1` debe guardarse en **UTF-8 con BOM**. La herramienta Write guarda sin BOM; después de escribir, conviértelo:
  `$t=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8); [IO.File]::WriteAllText($f,$t,[Text.UTF8Encoding]::new($true))`
  Valida la sintaxis con `[System.Management.Automation.Language.Parser]::ParseFile(...)`.
- **Funciones de una letra:** `h` es alias de `Get-History` y `r` de `Invoke-History`, y los alias ganan a las funciones. El script falla en silencio y puede dar un resultado "limpio" falso. Usa nombres descriptivos y compruébalos con `Get-Alias <nombre>`.
- `ConvertFrom-Json` falla con claves duplicadas, como en `Secure Preferences` de Edge (`update_URL` y `update_url`). Busca el ID con `.Contains()` o una expresión regular sobre el texto.
- En PowerShell 5.1 las colecciones WinRT no exponen `.Add()`: hay que usar `[ICollection[T]].GetMethod('Add').Invoke(...)`.
- No existen `&&`, `||`, `?:` ni `??`.

## Arnés de Claude Code
- `reg export ... /y` queda bloqueado porque interpreta `/y` como una ruta de sistema. Exporta a un archivo nuevo, sin `/y`.
- `Start-Sleep` largo seguido de otro comando se bloquea. Usa `run_in_background` y espera la notificación.
- Los comandos de más de 2 minutos pasan solos a segundo plano. Para el análisis completo usa `run_in_background: true` desde el principio.
- Cuando el usuario pega texto de su consola, no ejecuta nada por ti: pídele los comandos exactos.

## Permisos
- Sin permisos de administrador, `Win32_Process.CommandLine` y `ExecutablePath` salen **vacíos** para los procesos elevados, y `Get-ScheduledTask` no muestra las tareas creadas como SYSTEM. Que no aparezcan no significa que no existan.
- `C:\Windows\System32\Tasks` y `C:\Windows\Temp` dan "Acceso denegado" sin administrador.
- Si el prompt dice `PS C:\Users\<usuario>>`, lo más probable es que **no** sea una consola de administrador; esa suele abrirse en `C:\WINDOWS\system32`. Verifícalo con `IsInRole`.
- `Remove-MpPreference` no quita las exclusiones puestas como **política**: hay que borrar la clave del registro.
- Con la Protección contra alteraciones activa no se pueden cambiar las exclusiones ni la configuración de Defender. Para limpiar puede hacer falta desactivarla y volver a activarla al terminar. Se hace solo desde la interfaz: `windowsdefender://threatsettings`.

## Defender
- `Get-MpThreatCatalog -ThreatID x` tarda mucho por llamada. Úsalo solo cuando aporte (nombres de amenazas "permitidas") y en segundo plano.
- El análisis completo **no se puede pausar**; solo cancelar con `MpCmdRun.exe -Scan -Cancel` (`-Cancel` solo da error).
- Si Defender se actualiza durante el script, puede dar error de RPC (`0x800706be`) o de proveedor (`0x80041013`). Espera un minuto y repite.
- Un "análisis completo" que dura minutos indica exclusiones enormes, como `C:\`. Uno real tarda de 1 a 4 horas con unos 300 GB.
- El historial `Get-MpThreatDetection` puede estar vacío. El registro de eventos `Microsoft-Windows-Windows Defender/Operational` (1116, 1117 y 5007) conserva más tiempo y es la mejor línea de tiempo.

## Edge y navegadores
- Edge **sigue corriendo en segundo plano** tras cerrar las ventanas, con unos 10 procesos `msedge`, y bloquea o restaura archivos. Antes de borrar una extensión, ciérralo del todo con `Stop-Process -Name msedge -Force`, o desactiva "Arranque de inicio" y "Seguir ejecutando en segundo plano" en `edge://settings/system`.
- Una extensión puede no aparecer en `edge://extensions` y seguir en el disco. Comprueba si está registrada buscando su ID en `Preferences` y `Secure Preferences`. Si solo sale en `extension_telemetry_file_data`, ya no está instalada.
- En `Preferences`, `safebrowsing.enabled=false` **no** equivale a SmartScreen apagado. Verifica en `edge://settings/privacy/security` ("Protegerse de descargas y sitios dañinos").

## Energía
- Los portátiles con **espera moderna** se suspenden al cerrar la tapa, y con batería **hibernan** al agotar su presupuesto. Ese apagado congela el análisis y las tareas programadas no se ejecutan. `analisis-completo.ps1` lo evita en corriente alterna.
- La acción de la tapa es una opción oculta: `powercfg /query` no la muestra, pero `/setacvalueindex` sí la cambia. Su GUID es `4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936`.
- Si programas un apagado, usa una cuenta regresiva (`shutdown /s /t 120`) y avisa de que se perderá lo no guardado.

## Windows Update
- Un reinicio no siempre instala lo "descargado". Instálalo primero con el COM `Microsoft.Update.Session` (`CreateUpdateInstaller().Install()`) y luego reinicia.
- Al reiniciar se cierra la sesión de Claude Code. Guarda antes el estado en memoria para poder retomar.
