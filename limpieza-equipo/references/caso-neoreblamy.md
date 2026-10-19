# Caso resuelto: VideoAdsBlocker / Neoreblamy (octubre de 2026)

Ejemplo completo de razonamiento. Úsalo como modelo, no como receta: cada infección cambia nombres y rutas.

## Cómo empezó
El usuario compartió una grabación del Administrador de tareas. Lo único raro eran **3 procesos "Microsoft ® Windows Based Script Host"** (`wscript.exe`). Todo lo demás era software conocido.

## Cómo se desenredó
1. **Proceso padre:** `svchost` (servicio Schedule) → `forfiles.exe` → `cmd.exe` → `wscript.exe`. Esa cadena la lanza una tarea programada.
2. **Línea de comandos** (necesitó administrador): `wscript /e:vbscript "C:\ProgramData\dJOlmHytACCTVMVB\gAWTaiY"`, un archivo sin extensión.
3. **Tarea:** `\nQJCnXfwYUhlL2`, sin autor, en la raíz.
4. **Script decodificado** sin ejecutarlo: XOR con base 37777 y esquema `k+i+1`. Consultaba `version.txt` en 3 dominios; si había una versión nueva, bajaba `update_e.jpg` (un ejecutable cifrado), lo guardaba en `C:\Windows\Temp\<aleatorio>\<aleatorio>.exe` y lo ejecutaba con `/S /UPDATE`.
5. **Programa:** "VideoAdsBlocker 2.0.0.4004", sin fabricante. Su desinstalador era `rundll32 C:\Program Files (x86)\GbcrGbfJBMUn\RAYKUcH.dll,#1`.
6. **Extensión de Edge:** "Google Sheets Offline" (`fileepgfmlpabmkbocijoaggdmlhenbf`), creada **el mismo minuto** que la carpeta. Tenía permisos sobre todos los sitios, cookies, historial, webRequest y management. No se veía en `edge://extensions` y su carpeta tenía **Deny para Todos**.
7. **Ventana de instalación:** al buscar todo lo creado entre las 08:14 y las 08:17 aparecieron **4 DLL** más en Program Files (x86), algunas con nombres que el patrón inicial no detectaba (13 y 19 letras), además de un `.exe` en `Windows\Temp`.
8. **VirtualStore:** había 14 carpetas vacías con nombre aleatorio, de febrero a octubre. La infección llevaba meses y se reinstalaba cada 1–2 meses.
9. **Defender ciego:** las exclusiones normales eran `C:\` y `E:\OInstall.exe` (un activador de Office). Además había **16 exclusiones como política de grupo** y **21 `ThreatIDDefaultAction = 6`**, entre ellas `Trojan:VBS/Remcos`, `Neoreblamy`, `Wacatac` y `Behavior:Persistence`.
10. **Eventos 5007:** fecharon el inicio exacto: el **14/01/2026 a las 10:47** se excluyeron `C:\` y las extensiones `.exe/.dll/.wsf` (típico de un activador), y a las **10:49** llegaron las exclusiones y las acciones "Permitir" del malware.
11. Un análisis "completo" anterior había durado **90 segundos**, por la exclusión de `C:\`. El real, ya sin exclusiones, tardó **233 minutos**.

## Remediación (en este orden)
Procesos → 5 tareas → scripts en ProgramData → 4 DLL → `.exe` en Windows\Temp → entrada de desinstalación → extensión (quitar la regla Deny con `icacls /remove:d *S-1-1-0`) → exclusiones normales → **clave de política** de Defender (Exclusions y Threats) → políticas de Edge (`ExtensionInstallAllowlist` y `ExtensionManifestV2Availability`) → PUA activado → firmas → análisis completo → Protección contra alteraciones (el usuario, desde la interfaz).

## Lo que se respetó
El usuario había instalado a propósito RealVNC 4 (de 2008) y Office con OInstall. No se quitaron: se explicó el riesgo y se recomendó actualizar VNC o ponerlo en inicio manual, conseguir una licencia legítima y no volver a ejecutar activadores.

## Resultado
El análisis completo no encontró ni rastro del malware. Solo detectó un keygen viejo en un repositorio SVN, que quedó en cuarentena con la recomendación de borrarlo del repositorio. Se recomendó rotar credenciales (por la extensión con permiso de cookies y por Remcos en la lista de permitidas), avisar a TI y valorar reinstalar Windows por los 9 meses de exposición.

## Lecciones
- La primera evidencia era mínima (3 procesos de script); todo salió de tirar del hilo.
- Buscar por **ventana de tiempo** encuentra lo que el patrón de nombres no ve.
- Revisar la **política** de Defender, no solo `Get-MpPreference`.
- Un análisis limpio con exclusiones no vale nada.
