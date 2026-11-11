# Registra el cambio en CambiosProceso.xlsm y deja el borrador "TT##### ACA" en Outlook (guardar en UTF-8 con BOM: PowerShell 5.1)
param(
  [Parameter(Mandatory)][string]$TT,
  [Parameter(Mandatory)][string]$Titulo,
  [Parameter(Mandatory)][string]$Desarrollador,
  [Parameter(Mandatory)][string]$Imagen,
  [switch]$SoloCorreo
)
$ErrorActionPreference = 'Stop'
$procesos = 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm'
# Colaboradores (nombre -> correo) y copia del correo: mtto-comun\equipo.json
. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'mtto-comun\equipo.ps1')
$cc = $MttoDatos.ccAsignacion
$colaboradores = [ordered]@{}
foreach ($p in $MttoEquipo) { $colaboradores[$p.nombre] = $p.correo }

# VTiger escribe los nombres sin acentos; se comparan sin acentos ni mayúsculas
function SinAcentos([string]$s) { (($s.Normalize('FormD').ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }) -join '').Trim().ToLower() }
$dev = $colaboradores.Keys | Where-Object { (SinAcentos $_) -eq (SinAcentos $Desarrollador) } | Select-Object -First 1
if (-not $dev) { throw "Desarrollador '$Desarrollador' no está en la lista de colaboradores ($($colaboradores.Keys -join ', '))" }
$TT = $TT.Trim().ToUpper(); $Titulo = $Titulo.Trim()
if (-not (Test-Path $Imagen)) { throw "No existe la imagen $Imagen" }

if (-not $SoloCorreo) {
  try { $s = [IO.File]::Open($procesos, 'Open', 'ReadWrite', 'None'); $s.Close() }
  catch { throw "CambiosProceso.xlsm está abierto; guárdalo y ciérralo antes de registrar el cambio" }

  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.EnableEvents = $false
  try {
    $wb = $xl.Workbooks.Open($procesos, 0, $false)
    $lo = $wb.Worksheets.Item(1).ListObjects.Item('Tabla1')
    $v = $lo.DataBodyRange.Value2
    for ($r = 1; $r -le $v.GetLength(0); $r++) {
      if (([string]$v[$r,1]).Trim() -eq $TT) { throw "$TT ya está registrado: Desarrollador '$($v[$r,3])', Estatus '$($v[$r,4])'" }
    }
    # Fila nueva al final de Tabla1 con los valores por omisión
    $fila = $lo.ListRows.Add().Range
    $c = 1; foreach ($t in @($TT, $Titulo, $dev, 'Proceso')) { $fila.Cells.Item(1, $c++).Value2 = $t }
    $fila.Cells.Item(1, 6).Value2 = 'No'      # Autorizado
    $fila.Cells.Item(1, 7).Value2 = 'No'      # SCRUM
    $fila.Cells.Item(1, 8).Value2 = [double]0 # Cobrado 0%
    $fila.Cells.Item(1, 9).Value2 = [double](Get-Date).Date.ToOADate() # Fecha asignación
    # Tabla2 (rangos de descuento) siempre dos filas vacías debajo de Tabla1
    $lo2 = $wb.Worksheets.Item(1).ListObjects.Item('Tabla2')
    $destino = $lo.Range.Row + $lo.Range.Rows.Count + 2
    if ($lo2.Range.Row -ne $destino) { [void]$lo2.Range.Cut($lo2.Parent.Cells.Item($destino, $lo2.Range.Column)) }
    $wb.Save()
    "$TT registrado en CambiosProceso.xlsm (fila $($fila.Row))"
  } finally {
    if ($wb) { $wb.Close($false) }
    $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl)
  }
}

# Borrador en Outlook (no se envía); reemplaza el borrador previo del mismo TT
$ol = New-Object -ComObject Outlook.Application
$borradores = $ol.GetNamespace('MAPI').GetDefaultFolder(16)
$asunto = "$TT ACA"
$previos = @($borradores.Items | Where-Object { $_.Subject -eq $asunto })
foreach ($p in $previos) { $p.Delete() }

$saludo = if ((Get-Date).Hour -lt 12) { 'buen día' } else { 'buenas tardes' }
$nombre = $dev.Split(' ')[0]
$cid = "aca$($TT.ToLower())"
$firma = "style='color:#2F5496'"
# Ancho máximo de 1320 px (ancho del cuerpo del correo en pantalla de 1080p) para que la captura quepa completa en la ventana del correo
Add-Type -AssemblyName System.Drawing
$img = [Drawing.Image]::FromFile((Resolve-Path $Imagen).Path)
$ancho = [Math]::Min($img.Width, 1320); $alto = [Math]::Round($img.Height * $ancho / $img.Width)
# Estilo "Rectángulo con sombra": sombra difusa abajo a la derecha, dibujada en un PNG con fondo transparente
$d = 3; $blur = 5
$bmp = New-Object Drawing.Bitmap ([int]($ancho + $d + $blur * 2)), ([int]($alto + $d + $blur * 2))
$g = [Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'AntiAlias'
$capa = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](110 / ($blur + 1)), 0, 0, 0))
for ($k = 0; $k -le $blur; $k++) { $g.FillRectangle($capa, $blur + $d - $k, $blur + $d - $k, $ancho + 2 * $k, $alto + 2 * $k) }
$g.DrawImage($img, $blur, $blur, $ancho, $alto)
$g.Dispose(); $img.Dispose()
$png = Join-Path $env:TEMP "$cid.png"
$bmp.Save($png, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$ancho = $ancho + $d + $blur * 2; $alto = $alto + $d + $blur * 2
$m = $ol.CreateItem(0)
$m.To = $colaboradores[$dev]; $m.CC = $cc; $m.Subject = $asunto
$adj = $m.Attachments.Add($png, 1, 0)
$adj.PropertyAccessor.SetProperty('http://schemas.microsoft.com/mapi/proptag/0x3712001F', $cid)
$m.HTMLBody = @"
<html><body style="font-family:Calibri,sans-serif;font-size:11pt">
<p style="margin:0">$nombre $saludo, favor de darle seguimiento a la siguiente solicitud de cambio.</p>
<p style="margin:0">&nbsp;</p>
<p style="margin:0"><img width=$ancho height=$alto style="width:${ancho}px;height:${alto}px" src="cid:$cid"></p>
<p style="margin:0">&nbsp;</p>
<p style="margin:0"><b><i><span $firma>Jorge Armando Gálvez Martínez</span></i></b></p>
<p style="margin:0"><b><i><u><span $firma>Analista - Desarrollador</span></u></i></b></p>
</body></html>
"@
$m.Save()
Remove-Item $png
"Borrador '$asunto' para $($m.To) (CC $cc)$(if ($previos.Count) { ' - reemplazó el anterior' })"
