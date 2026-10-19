# Indicadores: qué es malicioso y qué es ruido

## Contenido
1. Señales fuertes de compromiso
2. Señales a investigar (dependen del contexto)
3. Falsos positivos habituales (no alarmar)
4. Familias vistas y su firma
5. Cuentas a rotar

## 1. Señales fuertes de compromiso

| Señal | Por qué es grave |
|---|---|
| **Exclusiones de Defender** de `C:\`, de extensiones `.exe`, `.dll` o `.wsf`, o de carpetas con nombre aleatorio | El antivirus queda ciego. Casi siempre las pone un activador, crack o malware |
| **Exclusiones bajo `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions`** en un equipo sin dominio ni MDM | Están escondidas como política de grupo para que el usuario no pueda quitarlas desde la interfaz |
| **`ThreatIDDefaultAction` = 6** (Permitir), por política o en preferencias | Defender detecta la amenaza y la deja pasar. Busca el nombre de cada ID: ahí sale la familia |
| Tarea en la raíz `\`, **sin autor**, con nombre aleatorio, que lanza `forfiles … /c "cmd /C … wscript /e:vbscript <archivo sin extensión>"` | Es un patrón LOLBin: `forfiles` rompe la cadena de procesos padre para despistar |
| Tarea que ejecuta `rundll32 "<Program Files (x86)>\<NombreAleatorio>\<Aleatorio>.dll",#1` | Carga un DLL malicioso por número de exportación |
| Archivos **sin extensión** en `C:\ProgramData\<16 letras aleatorias>\` | Son scripts VBS o JS camuflados; se ejecutan con `/e:vbscript` |
| Carpeta con **regla Deny para Todos** y dueño `SYSTEM` en Program Files, ProgramData o una extensión de navegador | Táctica para impedir el borrado. Las uniones de Windows ("Datos de programa", "Menú Inicio") también tienen Deny, pero son ReparsePoint y no cuentan |
| Extensión de navegador que **imita una de Google o Microsoft** ("Google Sheets Offline", "Docs Offline") con permisos `<all_urls>` + `cookies` + `webRequest` + `management`, y que **no aparece** en la página de extensiones | Roba sesiones y modifica páginas. La auténtica de Google es `ghbmnnjooekpmoecnnnilnnbdlolhkhi` ("Documentos de Google sin conexión") |
| Programa en "Agregar o quitar" **sin fabricante** cuyo desinstalador es `rundll32 <dll>,#1` | Un desinstalador falso que en realidad ejecuta el malware; nunca lo ejecutes |
| Política `ExtensionManifestV2Availability = 2` o `ExtensionInstallAllowlist` con ID desconocidos, en un equipo no gestionado | Mantiene vivas extensiones maliciosas. Es lo que causa "Administrado por su organización" |
| Script que descarga `.jpg` o `.png` y lo guarda como `.exe` | Es un descargador: la "imagen" es un ejecutable cifrado |
| **Carpetas vacías con nombre aleatorio en `%LOCALAPPDATA%\VirtualStore\Program Files (x86)`** | Rastro histórico de cada reinstalación. Sus fechas dicen **cuánto tiempo** lleva la infección |

## 2. Señales a investigar

- **Software de control remoto:** RealVNC, TightVNC, AnyDesk, TeamViewer, EShare/ESystemRemoteService, WonderCast (Hikvision, `HControlSystemService` sin firma), ScreenConnect. Pueden ser legítimos. Pregunta si el usuario los instaló y revisa versión, si arrancan solos y si escuchan en `0.0.0.0` (5900 y 5800 en VNC).
- **Keygens o cracks** en carpetas de utilerías (`HackTool:Win32/Keygen`, `PUA:Win32/Presenoker`, `Program:Win32/Wacapew`). Casi nunca son la infección activa, pero son una puerta típica de entrada. Si están dentro de un repositorio SVN o Git, volverán con el siguiente `update`: hay que borrarlos del repositorio.
- **Herramientas de recuperación de contraseñas** de NirSoft (Mail PassView, WebBrowserPassView). Defender las marca como HackTool. Pueden ser del usuario o de un atacante.
- **Servicios sin firma** de software vertical o interno (Firebird, servicios propios en `C:\ImagenCo`, `bin\Debug` del usuario). Normalmente legítimos; confírmalo con el usuario.
- **Certificados raíz nuevos.** El de NordVPN Threat Protection es legítimo. Cualquier otro de un emisor desconocido es sospechoso de interceptar HTTPS.

## 3. Falsos positivos habituales

- **Cientos de ejecutables "NotSigned" en `C:\Program Files\WindowsApps\`** (apps de la Store) y en `Windows Kits`. Se firman por catálogo, no con Authenticode.
- DLL de depuración de DirectX en `SysWOW64` (`d3d11sdklayers.dll`, `DXGIDebug.dll`): vienen del SDK de Windows.
- `SHA1:0x…` en el Administrador de tareas: es una agrupación interna de servicios de Windows.
- `tail.exe`, `grep.exe`, `sleep.exe` de `C:\Program Files\Git\usr\bin` lanzados por `claude.exe`: son las sesiones de Claude Code.
- `mscorsvw.exe` y "Microsoft .NET Framework optimization service" consumiendo CPU después de actualizar: es normal y pasa solo.
- En Windows de 64 bits, `HKLM\SOFTWARE\Policies\…` y `HKLM\SOFTWARE\WOW6432Node\Policies\…` son la **misma clave**. Al borrar una desaparece la otra, y los errores de "no existe" al borrar la segunda son inofensivos.
- Carpetas de Visual Studio en `Temp`: `MetadataAsSource`, `NuGetScratch`, `VSGitHubCopilotLogs`.
- `WorkplaceJoined: YES` en `dsregcmd` solo significa que hay una cuenta de trabajo agregada. No es MDM.

## 4. Familias vistas

| Familia o detección | Qué es | Firma observada |
|---|---|---|
| **VideoAdsBlocker / Neoreblamy** (`Trojan:Win32/Neoreblamy`, `BrowserModifier:JS/NeoreblamyExtension`) | Adware y descargador con extensión de navegador falsa | Tareas `forfiles→cmd→wscript` y `rundll32 …dll,#1`; carpetas aleatorias; 3–4 DLL de ~6.6 MB; reinstalación cada 1–2 meses; dominios `rapidfilestorage.com`, `helsinki-dtc.com`, `*.trace-monitors.com` |
| `Trojan:VBS/Remcos` | Troyano de acceso remoto (RAT): registra lo que se teclea, roba credenciales y permite control remoto | Si aparece en la lista de "permitidas", asume robo de credenciales aunque no haya rastro activo |
| `Trojan:Win32/Wacatac`, `Casur`, `Boxter`, `Vigorf` | Descargadores y troyanos genéricos (detección por aprendizaje automático) | Frecuentes junto a activadores y cracks |
| `Behavior:Win32/Persistence.*`, `Execution.*` | Detección por comportamiento de la persistencia | Si están "permitidas", el malware se protegió de que lo delataran |
| `Trojan:Win32/Commando.A!ml` | Detección de la línea de comandos `forfiles … wscript` | Que Defender lo detecte varias veces y vuelva indica que la persistencia sigue intacta |

## 5. Cuentas a rotar

Pídelo **desde otro dispositivo** y **cerrando todas las sesiones**, porque las cookies robadas siguen sirviendo después de cambiar la contraseña. Activa la verificación en dos pasos donde se pueda. Orden sugerido:

1. Correo personal y de trabajo (Microsoft 365, Gmail). Con el correo se recuperan todas las demás cuentas.
2. Banca y pagos (bancos, PayPal, tarjetas guardadas en el navegador).
3. Cuenta Microsoft y Google del sistema operativo y del navegador (contraseñas sincronizadas).
4. Herramientas de trabajo: Slack, GitHub, GitLab, Jira o Atlassian, CRM (VTiger), Dropbox, OneDrive, VPN, consolas en la nube.
5. Gestor de contraseñas: la contraseña maestra.
6. Redes sociales y mensajería (WhatsApp Web: cierra los dispositivos vinculados).
7. Revisa en cada servicio las sesiones activas, los dispositivos vinculados, los tokens de API o de acceso personal y las reglas de reenvío del correo.
