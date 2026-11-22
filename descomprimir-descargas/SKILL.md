---
name: descomprimir-descargas
description: Espera a que termine la descarga de un archivo comprimido (RAR, ZIP, 7z, tar.gz, partes .part1.rar/.r00/.z01/.001, o ZIP que trae RAR dentro), sin importar el origen (navegador, JDownloader, IDM, FDM, qBittorrent, uTorrent, aria2...) ni la carpeta destino; lo descomprime con WinRAR, borra los comprimidos y deja solo el contenido. Usar cuando digan "/descomprimir-descargas", "tengo una descarga en proceso", "cuando termine de descargar descomprimes", "monitorea la descarga", "descomprime y borra los rar", "deja solo lo importante" o mencionen que están bajando un comprimido con cualquier gestor.
argument-hint: "[archivo o carpeta opcional] [contraseña opcional]"
---

# Descomprimir descargas (/descomprimir-descargas)

Vigila las carpetas de descarga, espera a que cada comprimido esté **completo**, lo extrae con WinRAR, **borra los volúmenes una vez extraídos** y deja solo el contenido junto a donde se descargó.

- **Script:** `C:\Users\jorge\.gemini\config\skills\descomprimir-descargas\scripts\procesar-descarga.ps1` (PowerShell 5.1 y 7, UTF-8 con BOM).
- **Herramientas:** `C:\Program Files\WinRAR\WinRAR.exe` para extraer (RAR, ZIP, 7z, tar, gz, bz2, xz, cab) y `UnRAR.exe` para comprobar que un RAR multiparte esté completo.

## Cómo ejecutarlo

La espera puede durar horas, así que **siempre se lanza en segundo plano** (usando `run_command` con `WaitMsBeforeAsync: 500`). Avisa al usuario que quedó monitoreando y espera la notificación de término; no hagas sondeos.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jorge\.gemini\config\skills\descomprimir-descargas\scripts\procesar-descarga.ps1"
```

Sin argumentos vigila `Downloads` con sus subcarpetas, más la carpeta configurada en JDownloader y en qBittorrent si están instalados. Si el usuario dice dónde descarga (otro disco, la carpeta de IDM, etc.) o qué archivo es, pásalo como primer argumento; se aceptan varios separados por coma:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "...\procesar-descarga.ps1" "D:\Descargas\Juego", "Pelicula.part1.rar"
```

- **Archivo:** se procesa ese conjunto, esté en curso o ya descargado.
- **Carpeta:** se procesan las descargas en curso dentro de ella; si no hay ninguna, todos los comprimidos que contenga.

Parámetros opcionales:
- `-Password "<clave>"`: si el comprimido tiene contraseña. Sin ella falla de inmediato con un mensaje claro, no se queda esperando.
- `-MinutosSinAvance <n>` (60): si una descarga no cambia en ese tiempo, se detiene con error. Cubre las esperas entre partes de los servidores gratuitos.
- `-TimeoutMinutos <n>` (720): límite total.
- `-SegundosEstable <n>` (30): tiempo sin cambios antes de intentar extraer.
- `-NoBorrar`: extrae sin borrar los comprimidos (solo si el usuario lo pide).
- `-Notificar`: muestra una notificación de Windows al terminar, con lo conservado o con el error.
- `-Apagar`: **solo si el usuario lo pide explícitamente** ("apaga al terminar"). Al terminar programa el apagado en 2 minutos (`shutdown /a` lo cancela). Con error también apaga, siempre que las descargas ya hubieran finalizado; si una seguía incompleta o detenida, no apaga. Normalmente va con el modo independiente; avisa al usuario que el equipo se apagará.

### Modo independiente (opcional)

Úsalo solo si el usuario dice que va a cerrar la ventana o que lo deje corriendo solo ("déjalo corriendo", "voy a cerrar Antigravity"). En segundo plano el proceso muere al cerrar la ventana; así queda como proceso propio, oculto, y termina al acabar el trabajo. Lánzalo en primer plano (regresa de inmediato) con los mismos argumentos de siempre más `-Notificar`:

```powershell
Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\jorge\.gemini\config\skills\descomprimir-descargas\scripts\procesar-descarga.ps1" -Notificar' -RedirectStandardOutput "$env:TEMP\descomprimir-descargas.log" -RedirectStandardError "$env:TEMP\descomprimir-descargas.err.log"
```

Las rutas, `-Password` o `-Apagar` van dentro de la misma cadena de `-ArgumentList`, entre comillas dobles. No hay notificación de término para ti: dile al usuario que puede cerrar la ventana, que recibirá una notificación de Windows al terminar y que el detalle queda en `%TEMP%\descomprimir-descargas.log` (errores en `descomprimir-descargas.err.log`).

**JDownloader:** si su extractor está activo (`"enabled":true` en `%LOCALAPPDATA%\JDownloader 2\cfg\org.jdownloader.extensions.extraction.ExtractionExtension.json`), avisa al usuario antes de lanzar. Los dos extraerían el mismo paquete y el contenido quedaría duplicado (`Juego` y `Juego (2)`). Que desactive uno de los dos.

## Cómo decide

1. **Qué descargas atender:** las que tuvieron actividad en la última hora (`-MinutosSinAvance`) o aparecen mientras corre, porque los gestores encolan partes y paquetes. Los comprimidos viejos de esas carpetas no se tocan. Si no hay ninguna, termina con error e indica cuál es el comprimido más reciente, para preguntarle al usuario si es ese.
2. **Cuándo está completa:** no quedan temporales de descarga (`.crdownload`, `.part`, `.partial`, `.download`, `.opdownload`, `.fdmdownload`, `.!qB`, `.!ut`, `.!bt`, `.aria2`), no hubo cambios en `-SegundosEstable` y, en RAR, UnRAR encuentra todos los volúmenes. Eso cubre también a los gestores que escriben el nombre final directamente (IDM, torrents sin sufijo).
3. **Extracción segura:** extrae en `<nombre>.extrayendo` junto a la descarga. Si WinRAR falla porque todavía faltaba algo, borra esa carpeta y reintenta cuando cambie algún volumen. Si falla con la descarga ya detenida, informa el error.
4. **Contenedores:** si lo extraído son solo comprimidos más `.txt`, `.nfo`, `.url`, `.sfv` o `.md5` (repacks que meten los RAR en un ZIP, o `.tar.gz`), extrae lo de adentro y descarta el contenedor.
5. **Resultado:** un solo elemento raíz queda tal cual junto a la descarga. Si hay varios, quedan en una carpeta con el nombre del comprimido; si el nombre ya existe, se agrega ` (2)`. Se borran los `.url`/`.website` publicitarios de lo extraído.
6. **Limpieza:** solo después de extraer bien se borran los volúmenes de ese conjunto. Nunca otros comprimidos.

El script imprime `=== CONSERVADO ===` (`ruta | tamaño`) y `=== ELIMINADO ===`.

## Respuesta al usuario

Muestra lo conservado con enlaces clicables `[nombre](file:///C:/ruta/...)` y su tamaño, y un resumen breve de lo eliminado (cuántos volúmenes y contenedores; no hace falta listar cada parte).

## Errores comunes

- **Contraseña incorrecta o faltante:** pide la contraseña al usuario (suele venir en la página de descarga o en un `.txt`) y relanza indicando el archivo y `-Password`.
- **Archivo dañado (CRC):** una parte llegó mal; indica cuál volver a descargar.
- **Falta un volumen:** falta una parte o Defender la puso en cuarentena. Revisa el historial de protección.
- **"No hay descargas de comprimidos en curso":** pregunta dónde está descargando o qué archivo es, y relanza con esa ruta.
- **"La descarga no avanza":** descarga pausada, caída o esperando al servidor más de una hora; avisa y relanza cuando la reanude.
