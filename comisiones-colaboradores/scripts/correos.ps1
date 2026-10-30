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
