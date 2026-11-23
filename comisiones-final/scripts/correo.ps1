param([string]$Mes = (Get-Location).Path)
$ErrorActionPreference = 'Stop'

# Mes del concentrado y mes de pago (el siguiente) a partir de la carpeta YYYYMM-Mes
$dir = Get-Item $Mes
if ($dir.Name -notmatch '^(\d{4})(\d{2})-(.+)$') { throw "La carpeta $($dir.Name) no tiene el formato YYYYMM-Mes" }
$anio = $Matches[1]; $nombre = $Matches[3]
$pago = (Get-Date -Year $anio -Month $Matches[2] -Day 1).AddMonths(1)
$mesPago = $pago.ToString('MMMM', [Globalization.CultureInfo]'es-MX')
$mesTxt = $nombre.ToLower()

$xlsx = "$Mes\Mantenimiento_Comisiones_$($nombre)_$anio.xlsx"
if (-not (Test-Path $xlsx)) { throw "No existe $xlsx" }
try { $s = [IO.File]::Open($xlsx, 'Open', 'Read', 'None'); $s.Close() }
catch { throw "$([IO.Path]::GetFileName($xlsx)) está abierto; guárdalo y ciérralo antes de generar el correo" }

$asunto = "Resumen de comisiones de $mesTxt de $anio"
$ol = New-Object -ComObject Outlook.Application
$borradores = $ol.GetNamespace('MAPI').GetDefaultFolder(16)
$previos = @($borradores.Items | Where-Object { $_.Subject -eq $asunto })
foreach ($p in $previos) { $p.Delete() }

# Borrador con el concentrado adjunto (no se envía)
$m = $ol.CreateItem(0)
$m.To = "'rosaescalante@imagensoft.com.mx'; Ma. Esther Ahumada (estherahumada@imagensoft.com.mx)"
$m.CC = "'jorgeorduno@imagensoft.com.mx'"
$m.Subject = $asunto
$m.Body = "Buen día,`r`n`r`nEnvío resumen de comisiones correspondientes al mes de $mesTxt de $anio a pagar en $mesPago de $($pago.Year).`r`n`r`nCualquier duda o comentario quedo a la orden.`r`n`r`nSaludos…`r`n`r`n`r`nJorge Armando Gálvez Martínez`r`nAnalista - Desarrollador`r`n"
$m.Attachments.Add($xlsx) | Out-Null
$m.Save()
"Borrador '$asunto'$(if ($previos.Count) { ' (reemplazó el anterior)' })  [Excel guardado $((Get-Item $xlsx).LastWriteTime.ToString('dd/MM/yyyy HH:mm'))]"
