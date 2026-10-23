---
name: comisiones-correos
description: Prepara los correos de autorización de comisiones de los cambios internos de Mantenimiento. Se ejecuta desde la carpeta del mes (C:\Users\jorge\Dropbox\MTTO\Reportes Mensuales\Comisiones\<año>\YYYYMM-Mes), toma los HorasCambioTT#####.xlsx de CambiosInternos\<colaborador> tal como estén guardados (incluso si el usuario los editó) y deja un borrador en Outlook con ese Excel adjunto. Usar cuando digan "/comisiones-correos", "genera los correos de autorización", "prepara los borradores de comisiones", "ya edité el archivo, haz el correo" o "vuelve a adjuntar el Excel".
argument-hint: "[TT##### ...]"
---

# Correos de autorización de comisiones (/comisiones-correos)

Preparas el correo con el que Jorge pide la autorización del pago de comisiones de cada cambio interno.
Los `HorasCambioTT#####.xlsx` los genera `/comisiones-internos`. El usuario puede editarlos después; esta skill **siempre adjunta el archivo como esté guardado en ese momento**, nunca lo regenera ni lo modifica.

- **Carpeta de la skill** (`$SK`): `C:\Users\jorge\.gemini\config\skills\comisiones-correos`.
- **Carpeta del mes** (`$MES`): la carpeta de trabajo actual, con nombre `YYYYMM-Mes`.
- **Títulos de los cambios:** `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx` (columna A = ID, columna B = Descripción).
- El script corre en PowerShell 5.1, usa Excel y Outlook por COM y está guardado en UTF-8 con BOM. Si lo editas, consérvalo con BOM; sin él, los acentos salen corruptos.

## Paso 1 — Redactar la descripción breve de cada cambio

Es una frase corta que resume qué hace el cambio y va al final del primer párrafo. Por ejemplo: `son diversas mejoras solicitadas al monitor de servicios para mostrar más información solicitadas por soporte y algunos distribuidores`. Empieza en minúscula, no lleva punto final y no repite el título.

Sigue este orden de fuentes:

1. **Archivo HorasCambio de cada TT.** Revisa el título y las actividades de cada uno:
   ```powershell
   & 'C:\Users\jorge\.gemini\config\skills\comisiones-correos\scripts\cambios.ps1'          # o -TT TT105878,...
   ```
2. **Azure DevOps.** Úsalo solo si las actividades no alcanzan (por ejemplo, si solo dicen "Codificación"). Muestra ramas, commits y archivos de los TT indicados. Usa el token de /mtto-revpr (`AZURE_DEVOPS_EXT_PAT`).
   ```powershell
   & 'C:\Users\jorge\.gemini\config\skills\comisiones-correos\scripts\cambios.ps1' -TT TT105876 -Ado
   ```
3. **Si tampoco hay rama ni PR**, redacta una descripción verosímil con lo que tengas (título, colaborador, actividades). Jorge la revisa en el borrador antes de enviar. En el chat, indica qué descripciones son deducidas.

No pidas aprobación de las descripciones antes de generar los borradores. Muéstralas en la entrega.

## Paso 2 — Generar

Pasa las descripciones con `-Desc`. Para todos los cambios del mes:

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-correos\scripts\correos.ps1' -Desc @{ TT105878 = 'agrega ...'; TT102841 = 'permite ...' }
```

Si el usuario nombra uno o varios TT (por ejemplo, los que editó), pásalos con `-TT`:

```powershell
& 'C:\Users\jorge\.gemini\config\skills\comisiones-correos\scripts\correos.ps1' -TT TT105878,TT102841 -Desc @{ ... }
```

Usa la herramienta PowerShell con un timeout amplio (unos 120000 ms).

Por cada `HorasCambioTT#####.xlsx`, el script:

1. **Revisa que el Excel no esté abierto.** Si lo está, se detiene. Pídele al usuario que lo guarde y lo cierre, y vuelve a correrlo.
2. **Prepara el borrador en Outlook** (Borradores) con el Excel actual adjunto. **No lo envía.** Si ya había un borrador con el mismo asunto, lo borra (queda en Elementos eliminados) y crea uno nuevo. Así el adjunto siempre es la versión editada y no se duplican borradores.

Imprime cada TT con la fecha y hora en que se guardó el Excel adjunto.

Si falla con `no está en CambiosProceso.xlsx`, pregunta al usuario el título del caso. No lo inventes.

## Redacción fija del correo

Tomada del que Jorge envía cada mes:

- **Para:** `jorgeorduno@imagensoft.com.mx`
- **Asunto:** `Autorización comisiones cambio interno TT#####`
- **Cuerpo:**

```
Ingeniero buen día, solicito de su autorización para el pago de comisiones del cambio interno <TÍTULO>, realizado por <Colaborador>, <descripción breve>.


Jorge Armando Gálvez Martínez
Analista - Desarrollador
```

En el cuerpo:

- `<TÍTULO>` es el título de CambiosProceso sin espacios alrededor de los guiones, por ejemplo `TT105878-IMAGENSOFT-CAMBIO-CARTAPORTE UBICACION Y MERCANCIA`.
- `<Colaborador>` es el nombre de pila, es decir, el nombre de la carpeta en `CambiosInternos`.

## Paso 3 — Entregar (en el chat, breve)

1. Los TT procesados, con la fecha de guardado del Excel adjunto y la descripción usada (y de qué fuente salió).
2. Cuáles borradores se reemplazaron.
3. Que los borradores están en Outlook, listos para revisar y enviar.
