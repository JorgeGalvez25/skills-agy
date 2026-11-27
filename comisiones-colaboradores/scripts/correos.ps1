param([string]$Mes = (Get-Location).Path)
$ErrorActionPreference = 'Stop'

# Mes del reporte y mes de pago (el siguiente) a partir de la carpeta YYYYMM-Mes
$dir = Get-Item $Mes
if ($dir.Name -notmatch '^(\d{4})(\d{2})-(.+)$') { throw "La carpeta $($dir.Name) no tiene el formato YYYYMM-Mes" }
$anio = $Matches[1]; $nombre = $Matches[3]
$pago = (Get-Date -Year $anio -Month $Matches[2] -Day 1).AddMonths(1)
$mesPago = $pago.ToString('MMMM', [Globalization.CultureInfo]'es-MX')

$archivos = @(Get-ChildItem "$Mes\PorBeneficiario" -Filter "Mantenimiento_Comisiones_$($nombre)_$($anio)_*.xlsx")
if ($archivos.Count -eq 0) { throw "No hay archivos por beneficiario en $Mes\PorBeneficiario" }

# El Excel debe estar guardado y cerrado para adjuntarlo
foreach ($x in $archivos) {
  try { $s = [IO.File]::Open($x.FullName, 'Open', 'Read', 'None'); $s.Close() }
  catch { throw "$($x.Name) está abierto; guárdalo y ciérralo antes de generar el correo" }
}
# El concentrado y CambiosProceso también, para actualizar el porcentaje pagado
$conc = "$Mes\Mantenimiento_Comisiones_$($nombre)_$anio.xlsx"
$procesos = 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsm'
foreach ($f in $conc, $procesos) {
  try { $s = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None'); $s.Close() }
  catch { throw "$(Split-Path $f -Leaf) no existe o está abierto; guárdalo y ciérralo antes de generar el correo" }
}

$asunto = "Reporte de comisiones $($nombre.ToLower()) $anio"
$ol = New-Object -ComObject Outlook.Application
$borradores = $ol.GetNamespace('MAPI').GetDefaultFolder(16)
foreach ($x in $archivos) {
  # Nombre_Apellido -> nombreapellido@igas.com.mx, sin acentos
  $persona = $x.BaseName.Substring("Mantenimiento_Comisiones_$($nombre)_$($anio)_".Length)
  $para = ($persona -replace '_', '').Normalize('FormD') -replace '\p{Mn}', ''
  $para = "$($para.ToLower())@igas.com.mx"

  # Borrador en Outlook con el Excel adjunto (no se envía); reemplaza el borrador previo de la misma persona
  $previos = @($borradores.Items | Where-Object { $_.Subject -eq $asunto -and $_.To -like "*$para*" })
  foreach ($p in $previos) { $p.Delete() }
  $m = $ol.CreateItem(0)
  $m.To = $para; $m.Subject = $asunto
  $m.Body = "Comisiones de $($nombre.ToLower()) pagadas en $mesPago $($pago.Year).`r`n`r`n`r`nJorge Armando Gálvez Martínez`r`nAnalista - Desarrollador`r`n"
  $m.Attachments.Add($x.FullName) | Out-Null
  $m.Save()
  "$($persona -replace '_', ' ') -> $para$(if ($previos.Count) { ' (reemplazó el anterior)' })  [guardado $($x.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))]"
}

# Porcentaje pagado de cada cambio interno en CambiosProceso (Cobrado): k/N si va "(Pago k de N)", si no 100 %
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.AutomationSecurity = 3
try {
  $wb = $xl.Workbooks.Open($conc, 0, $true)
  $v = $wb.Worksheets.Item(1).Range('A1:F28').Value2
  $wb.Close($false)
  $wb = $xl.Workbooks.Open($procesos, 0, $false)
  $lo = $wb.Worksheets.Item(1).ListObjects.Item('Tabla1')
  $col = $lo.ListColumns.Item('Cobrado').Index
  $ids = $lo.ListColumns.Item('ID').DataBodyRange.Value2
  ''
  foreach ($r in 16..28) {
    $tt = [string]$v[$r,2]
    if ($tt -notmatch '^TT\d+$') { continue }
    $pct = [double]$(if ([string]$v[$r,6] -match '\(Pago (\d+) de (\d+)\)\s*$') { [int]$Matches[1] / [int]$Matches[2] } else { 1 })
    $i = 0; for ($k = 1; $k -le $ids.GetLength(0); $k++) { if ($ids[$k,1] -eq $tt) { $i = $k; break } }
    if (-not $i) { "$tt no está en CambiosProceso.xlsm; no se actualizó el porcentaje"; continue }
    $fila = $lo.ListRows.Item($i).Range
    $fila.Cells.Item(1,$col).Value2 = $pct
    # Pagado completo: se quita el amarillo de la fila
    if ($pct -eq 1) { foreach ($c in $fila.Cells) { if ($c.Interior.Color -eq 65535) { $c.Interior.ColorIndex = -4142 } } }
    "{0} -> Cobrado {1:P0}{2}" -f $tt, $pct, $(if ($pct -eq 1) { ' (sin amarillo)' })
  }
  $wb.Save(); $wb.Close($false)
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
