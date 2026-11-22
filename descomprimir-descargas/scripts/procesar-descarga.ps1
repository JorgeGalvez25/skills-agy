<#
.SYNOPSIS
    Espera a que termine la descarga de un comprimido (de cualquier navegador o gestor y en cualquier carpeta),
    lo descomprime con WinRAR, borra sus volúmenes y deja solo el contenido.
#>
[CmdletBinding()]
param (
    # Archivos o carpetas a vigilar; por omisión Descargas y las carpetas configuradas en JDownloader y qBittorrent
    [Parameter(Position = 0)]
    [string[]]$Ruta,
    [string]$Password,
    [int]$TimeoutMinutos = 720,
    [int]$MinutosSinAvance = 60,
    [int]$SegundosEstable = 30,
    [switch]$NoBorrar,
    # Muestra una notificación de Windows al terminar, con éxito o con error
    [switch]$Notificar,
    # Apaga el equipo al terminar; con error solo si las descargas ya habían finalizado
    [switch]$Apagar
)

$ErrorActionPreference = 'Stop'

function Show-Notificacion([string]$texto, [string]$icono = 'Info') {
    if (-not $Notificar) { return }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $n = [System.Windows.Forms.NotifyIcon]::new()
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    $n.ShowBalloonTip(10000, 'Descomprimir descargas', $texto, $icono)
    # El globo desaparece si el proceso termina antes de mostrarlo
    Start-Sleep -Seconds 5
    $n.Dispose()
}

function Close-Proceso([string]$texto, [string]$icono, [bool]$apagar) {
    if ($apagar) {
        shutdown.exe /s /t 120 /c 'Descomprimir descargas terminó. Usa "shutdown /a" para cancelar.'
        $texto += ' El equipo se apagará en 2 minutos (shutdown /a para cancelar).'
    }
    Show-Notificacion $texto $icono
}

# Con error se apaga solo si todas las descargas pendientes estaban completas
trap {
    $completas = $pendientes -and -not @($pendientes | Where-Object { try { -not (Test-Completo $_) } catch { $false } }).Count
    Close-Proceso "Error: $_" 'Error' ($Apagar -and $completas)
    break
}
$winrar = 'C:\Program Files\WinRAR\WinRAR.exe'
$unrar = 'C:\Program Files\WinRAR\UnRAR.exe'
foreach ($exe in $winrar, $unrar) { if (-not (Test-Path -LiteralPath $exe)) { throw "No se encontró $exe" } }

# Sufijos de descarga en curso: Chrome/Edge, Firefox/JDownloader, Opera, Safari, FDM, qBittorrent, uTorrent/BitTorrent, aria2
$sufijosTemp = '.crdownload', '.part', '.partial', '.download', '.opdownload', '.fdmdownload', '.!qb', '.!ut', '.!bt', '.aria2'
# Basura publicitaria que se borra de lo extraído
$extBasura = '.url', '.website'
# Lo que acompaña a los volúmenes dentro de un contenedor sin que valga la pena conservarlo
$extIntermedia = '.url', '.website', '.txt', '.nfo', '.sfv', '.md5'

$conservados = [System.Collections.Generic.List[string]]::new()
$eliminados = [System.Collections.Generic.List[string]]::new()

function Format-Tamano([double]$bytes) {
    if ($bytes -ge 1GB) { '{0:N2} GB' -f ($bytes / 1GB) } else { '{0:N1} MB' -f ($bytes / 1MB) }
}

# Conjunto de volúmenes al que pertenece un nombre de archivo, o $null si no es un comprimido
function Get-Conjunto([string]$nombre) {
    switch -Regex ($nombre) {
        '(?i)^(.+)\.part(\d+)\.rar$' { return @{ Base = $Matches[1]; Tipo = 'rar'; Primero = [int]$Matches[2] -eq 1 } }
        '(?i)^(.+)\.(rar|r\d{2,3})$' { return @{ Base = $Matches[1]; Tipo = 'rar'; Primero = $Matches[2] -ieq 'rar' } }
        '(?i)^(.+)\.(zip|z\d{2,3})$' { return @{ Base = $Matches[1]; Tipo = 'zip'; Primero = $Matches[2] -ieq 'zip' } }
        '(?i)^(.+)\.(7z|zip|rar|tar)\.(\d{3})$' { return @{ Base = $Matches[1]; Tipo = 'num'; Primero = [int]$Matches[3] -eq 1 } }
        '(?i)^(.+)\.(7z|tar|tgz|gz|bz2|xz|cab)$' { return @{ Base = $Matches[1]; Tipo = 'simple'; Primero = $true } }
    }
    $null
}

function Get-Clave([string]$carpeta, $c) { "$carpeta|$($c.Tipo)|$($c.Base)".ToLower() }

# Agrupa por conjunto los volúmenes y temporales de descarga que hay en las carpetas indicadas
function Get-Conjuntos([string[]]$carpetas, [switch]$IncluirExtrayendo) {
    $mapa = @{}
    foreach ($raiz in $carpetas) {
        foreach ($f in Get-ChildItem -LiteralPath $raiz -Recurse -File -ErrorAction SilentlyContinue) {
            if (-not $IncluirExtrayendo -and $f.FullName -match '\.extrayendo\d*\\') { continue }
            $nombre = $f.Name
            $suf = $sufijosTemp | Where-Object { $nombre.ToLower().EndsWith($_) } | Select-Object -First 1
            if ($suf) { $nombre = $nombre.Substring(0, $nombre.Length - $suf.Length) }
            $c = Get-Conjunto $nombre
            if (-not $c) { continue }
            $clave = Get-Clave $f.DirectoryName $c
            if (-not $mapa.ContainsKey($clave)) {
                $mapa[$clave] = [pscustomobject]@{
                    Clave = $clave; Carpeta = $f.DirectoryName; Base = $c.Base; Tipo = $c.Tipo; Primero = $null
                    Volumenes = [System.Collections.Generic.List[object]]::new()
                    Temporales = [System.Collections.Generic.List[object]]::new()
                    UltimoCambio = [datetime]::MinValue
                }
            }
            $s = $mapa[$clave]
            if ($suf) { $s.Temporales.Add($f) } else { $s.Volumenes.Add($f); if ($c.Primero) { $s.Primero = $f } }
            if ($f.LastWriteTime -gt $s.UltimoCambio) { $s.UltimoCambio = $f.LastWriteTime }
        }
    }
    $mapa
}

function Get-ArgPassword { if ($Password) { "-p$Password" } else { '-p-' } }

function Get-MensajeError([int]$codigo) {
    switch ($codigo) {
        3 { 'archivo dañado (CRC); hay que volver a descargar la parte afectada' }
        6 { 'falta un volumen o no se pudo abrir (¿Defender lo puso en cuarentena?)' }
        { $_ -in 10, 11 } { 'contraseña incorrecta o faltante; usa -Password' }
        default { "WinRAR terminó con código $codigo" }
    }
}

# Descarga completa: sin temporales y, en RAR, con todos los volúmenes presentes
function Test-Completo($s) {
    if ($s.Temporales.Count -or -not $s.Primero) { return $false }
    if ($s.Tipo -eq 'rar') {
        $ErrorActionPreference = 'Continue'
        $salida = & $unrar lb -v (Get-ArgPassword) $s.Primero.FullName 2>&1
        if ($LASTEXITCODE -eq 11) { throw "$($s.Primero.Name): $(Get-MensajeError 11)" }
        if ($LASTEXITCODE -ne 0 -or ($salida | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { return $false }
    }
    $true
}

# Listo para extraer: completo y sin cambios recientes
function Test-Listo($s) {
    ((Get-Date) - $s.UltimoCambio).TotalSeconds -ge $SegundosEstable -and (Test-Completo $s)
}

function Invoke-WinRar([string]$archivo, [string]$destino) {
    $p = Start-Process -FilePath $winrar -WorkingDirectory $destino -Wait -PassThru `
        -ArgumentList 'x', '-ibck', '-inul', '-y', "`"$(Get-ArgPassword)`"", "`"$archivo`""
    $p.ExitCode
}

# Deja lo extraído en $destino: un solo elemento raíz se sube tal cual; varios quedan en una carpeta con el nombre del conjunto
function Complete-Extraccion([string]$temporal, [string]$destino, [string]$base) {
    Get-ChildItem -LiteralPath $temporal -Recurse -File |
        Where-Object { $extBasura -contains $_.Extension.ToLower() } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force; $eliminados.Add($_.FullName) }
    $hijos = @(Get-ChildItem -LiteralPath $temporal)
    if ($hijos.Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $destino $hijos[0].Name))) {
        $final = Join-Path $destino $hijos[0].Name
        Move-Item -LiteralPath $hijos[0].FullName -Destination $final
        Remove-Item -LiteralPath $temporal -Force
    } else {
        $final = Join-Path $destino $base
        $n = 2
        while (Test-Path -LiteralPath $final) { $final = Join-Path $destino "$base ($n)"; $n++ }
        Move-Item -LiteralPath $temporal -Destination $final
    }
    $conservados.Add($final)
}

# Extrae el conjunto en una carpeta temporal junto a $destino; si falla la borra y regresa el código de WinRAR
function Expand-Conjunto($s, [string]$destino) {
    $temporal = Join-Path $destino "$($s.Base).extrayendo"
    $n = 2
    while (Test-Path -LiteralPath $temporal) { $temporal = Join-Path $destino "$($s.Base).extrayendo$n"; $n++ }
    [void][System.IO.Directory]::CreateDirectory($temporal)
    Write-Host "Extrayendo $($s.Primero.FullName) ..."
    $codigo = Invoke-WinRar $s.Primero.FullName $temporal
    if ($codigo -ne 0) {
        Remove-Item -LiteralPath $temporal -Recurse -Force
        return $codigo
    }

    # Contenedor (p. ej. un ZIP que solo trae los RAR): se extrae lo de adentro y se descarta el contenedor
    $archivos = @(Get-ChildItem -LiteralPath $temporal -Recurse -File | Where-Object { $extIntermedia -notcontains $_.Extension.ToLower() })
    $internos = @((Get-Conjuntos $temporal -IncluirExtrayendo).Values | Where-Object { $_.Primero })
    $esContenedor = $archivos.Count -and -not @($archivos | Where-Object { -not (Get-Conjunto $_.Name) }).Count
    if ($esContenedor) {
        foreach ($i in $internos) {
            $c = Expand-Conjunto $i $destino
            if ($c -ne 0) { throw "$($i.Primero.Name): $(Get-MensajeError $c)" }
        }
        if ($NoBorrar) { Complete-Extraccion $temporal $destino $s.Base }
        else { Remove-Item -LiteralPath $temporal -Recurse -Force }
    } else {
        Complete-Extraccion $temporal $destino $s.Base
    }

    if (-not $NoBorrar) {
        foreach ($v in $s.Volumenes) {
            if (Test-Path -LiteralPath $v.FullName) { Remove-Item -LiteralPath $v.FullName -Force; $eliminados.Add($v.FullName) }
        }
    }
    0
}

# 1. Carpetas a vigilar
$explicitos = @{}
$carpetasExplicitas = @()
$raices = @()
if ($Ruta) {
    foreach ($r in $Ruta) {
        if (-not (Test-Path -LiteralPath $r)) { throw "No existe $r" }
        $item = Get-Item -LiteralPath $r
        if ($item.PSIsContainer) { $raices += $item.FullName; $carpetasExplicitas += $item.FullName; continue }
        $nombre = $item.Name
        $suf = $sufijosTemp | Where-Object { $nombre.ToLower().EndsWith($_) } | Select-Object -First 1
        if ($suf) { $nombre = $nombre.Substring(0, $nombre.Length - $suf.Length) }
        $c = Get-Conjunto $nombre
        if (-not $c) { throw "$($item.Name) no es un archivo comprimido." }
        $explicitos[(Get-Clave $item.DirectoryName $c)] = $true
        $raices += $item.DirectoryName
    }
} else {
    $raices += Join-Path $env:USERPROFILE 'Downloads'
    $cfgJd = @(Get-ChildItem -Path "$env:LOCALAPPDATA\JDownloader*\cfg", "$env:ProgramFiles\JDownloader*\cfg" -Filter 'org.jdownloader.settings.GeneralSettings.json' -File -ErrorAction SilentlyContinue)
    foreach ($j in $cfgJd) { $raices += (Get-Content -LiteralPath $j.FullName -Raw | ConvertFrom-Json).defaultdownloadfolder }
    $iniQb = Join-Path $env:APPDATA 'qBittorrent\qBittorrent.ini'
    if (Test-Path -LiteralPath $iniQb) {
        $m = Select-String -LiteralPath $iniQb -Pattern '^Session\\DefaultSavePath=(.+)$' | Select-Object -First 1
        if ($m) { $raices += $m.Matches[0].Groups[1].Value }
    }
}
$raices = @($raices | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
    ForEach-Object { (Resolve-Path -LiteralPath $_).ProviderPath.TrimEnd('\') } | Sort-Object -Unique)
$raices = @($raices | Where-Object { $r = $_; -not ($raices | Where-Object { $r.StartsWith("$_\", 'OrdinalIgnoreCase') }) })
Write-Host "Vigilando: $($raices -join '; ')"

# 2. Esperar, extraer cada conjunto cuando esté completo y repetir mientras sigan llegando descargas
$inicio = Get-Date
$umbral = $inicio.AddMinutes(-$MinutosSinAvance)
$procesados = @{}
$fallos = @{}
$ultimoProcesado = $null
$ultimoReporte = [datetime]::MinValue
$primeraVuelta = $true
while ($true) {
    $conjuntos = Get-Conjuntos $raices
    $activos = @($conjuntos.Values | Where-Object { $_.UltimoCambio -ge $umbral })
    if ($primeraVuelta) {
        # Sin descargas recientes en una carpeta indicada: se procesa todo lo que tenga
        if (-not $activos -and $carpetasExplicitas) {
            $conjuntos.Values | Where-Object { $s = $_; $carpetasExplicitas | Where-Object { "$($s.Carpeta)\".StartsWith("$_\", 'OrdinalIgnoreCase') } } |
                ForEach-Object { $explicitos[$_.Clave] = $true }
        }
        $primeraVuelta = $false
    }
    $pendientes = @($conjuntos.Values | Where-Object {
        -not $procesados.ContainsKey($_.Clave) -and ($explicitos.ContainsKey($_.Clave) -or $_.UltimoCambio -ge $umbral) })

    if (-not $pendientes) {
        if (-not $procesados.Count) {
            $reciente = $conjuntos.Values | Sort-Object UltimoCambio -Descending | Select-Object -First 1
            $pista = if ($reciente) { " El comprimido más reciente es $(Join-Path $reciente.Carpeta $reciente.Base) ($($reciente.UltimoCambio))." } else { '' }
            throw "No hay descargas de comprimidos en curso en: $($raices -join '; ').$pista"
        }
        # Gracia por si el gestor tiene más descargas en cola
        if (((Get-Date) - $ultimoProcesado).TotalSeconds -ge 30) { break }
    }

    foreach ($s in $pendientes) {
        $sinAvance = ((Get-Date) - $s.UltimoCambio).TotalMinutes -ge $MinutosSinAvance
        if ($fallos.ContainsKey($s.Clave) -and $fallos[$s.Clave].Cambio -eq $s.UltimoCambio) {
            if ($sinAvance) { throw "$($s.Base): $(Get-MensajeError $fallos[$s.Clave].Codigo)" }
            continue
        }
        if (-not (Test-Listo $s)) {
            if ($sinAvance) { throw "$($s.Base): la descarga no avanza desde hace $MinutosSinAvance minutos (faltan partes o está pausada)." }
            continue
        }
        $codigo = Expand-Conjunto $s $s.Carpeta
        if ($codigo -eq 0) {
            $procesados[$s.Clave] = $true
            $ultimoProcesado = Get-Date
        } elseif ($codigo -in 10, 11) {
            throw "$($s.Primero.Name): $(Get-MensajeError $codigo)"
        } else {
            # Puede que el gestor aún no termine de escribir: se reintenta cuando cambie algún volumen
            $fallos[$s.Clave] = @{ Cambio = $s.UltimoCambio; Codigo = $codigo }
            Write-Host "$($s.Base): no se pudo extraer todavía ($(Get-MensajeError $codigo)); espero cambios."
        }
    }

    if (((Get-Date) - $inicio).TotalMinutes -ge $TimeoutMinutos) { throw "Se excedió el límite de $TimeoutMinutos minutos." }
    if ($pendientes -and ((Get-Date) - $ultimoReporte).TotalSeconds -ge 60) {
        foreach ($s in $pendientes) {
            $bytes = (@($s.Volumenes) + @($s.Temporales) | Measure-Object Length -Sum).Sum
            Write-Host "En espera: $($s.Base) | $($s.Volumenes.Count) volumen(es), $($s.Temporales.Count) descargando | $(Format-Tamano $bytes) | $($s.Carpeta)"
        }
        $ultimoReporte = Get-Date
    }
    Start-Sleep -Seconds 10
}

# 3. Reporte
Write-Host "`n=== CONSERVADO ==="
foreach ($c in $conservados | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    $item = Get-Item -LiteralPath $c
    $bytes = if ($item.PSIsContainer) { (Get-ChildItem -LiteralPath $c -Recurse -File | Measure-Object Length -Sum).Sum } else { $item.Length }
    Write-Host "$($item.FullName) | $(Format-Tamano $bytes)"
}
Write-Host "`n=== ELIMINADO ==="
$eliminados | Select-Object -Unique | ForEach-Object { Write-Host $_ }

$nombres = @($conservados | Select-Object -Unique | ForEach-Object { Split-Path $_ -Leaf })
Close-Proceso "Listo: $($nombres -join ', ')" 'Info' $Apagar
