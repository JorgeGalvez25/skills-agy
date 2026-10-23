param([string]$Mes = (Get-Location).Path, [string[]]$TT, [hashtable]$Desc = @{})
$ErrorActionPreference = 'Stop'
$para = 'jorgeorduno@imagensoft.com.mx'
$procesos = 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx'

$archivos = @(Get-ChildItem "$Mes\CambiosInternos" -Recurse -Filter 'HorasCambioTT*.xlsx' | Where-Object { -not $TT -or ($_.BaseName -replace 'HorasCambio', '') -in $TT })
if ($archivos.Count -eq 0) { throw "No hay HorasCambioTT*.xlsx en $Mes\CambiosInternos$(if ($TT) { " para $($TT -join ', ')" })" }

# El Excel debe estar guardado y cerrado para adjuntar la versión editada
foreach ($x in $archivos) {
  try { $s = [IO.File]::Open($x.FullName, 'Open', 'Read', 'None'); $s.Close() }
  catch { throw "$($x.Name) está abierto; guárdalo y ciérralo antes de generar el correo" }
}

# Títulos de CambiosProceso
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false
try {
  $wp = $xl.Workbooks.Open($procesos, 0, $true)
  $ur = $wp.Worksheets.Item(1).UsedRange; $v = $ur.Value2; $n = $ur.Rows.Count
  $wp.Close($false)
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
$titulos = @{}
for ($r = 2; $r -le $n; $r++) { $id = ([string]$v[$r,1]).Trim(); if ($id) { $titulos[$id] = (([string]$v[$r,2]).Trim() -replace '\s*-\s*', '-') } }

$ol = New-Object -ComObject Outlook.Application
$borradores = $ol.GetNamespace('MAPI').GetDefaultFolder(16)
foreach ($x in $archivos) {
  $tt = $x.BaseName -replace 'HorasCambio', ''
  if (-not $titulos[$tt]) { throw "$tt no está en CambiosProceso.xlsx" }
  $asunto = "Autorización comisiones cambio interno $tt"
  $solicitud = "Ingeniero buen día, solicito de su autorización para el pago de comisiones del cambio interno $($titulos[$tt]), realizado por $($x.Directory.Name)$(if ($Desc[$tt]) { ', ' + $Desc[$tt].TrimEnd('.') })."

  # Borrador en Outlook con el Excel actual adjunto (no se envía); reemplaza el borrador previo del mismo TT
  $previos = @($borradores.Items | Where-Object { $_.Subject -eq $asunto })
  foreach ($p in $previos) { $p.Delete() }
  $m = $ol.CreateItem(0)
  $m.To = $para; $m.Subject = $asunto
  $m.Body = "$solicitud`r`n`r`n`r`nJorge Armando Gálvez Martínez`r`nAnalista - Desarrollador`r`n"
  $m.Attachments.Add($x.FullName) | Out-Null
  $m.Save()
  "$tt -> borrador$(if ($previos.Count) { ' (reemplazó el anterior)' })  [guardado $($x.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))]"
}
