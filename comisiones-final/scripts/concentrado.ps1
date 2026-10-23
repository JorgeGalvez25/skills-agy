param([string]$Mes = (Get-Location).Path, [string]$Externos, [switch]$Sobrescribir)
$ErrorActionPreference = 'Stop'
$procesos = 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx'
# Columna de porcentaje por beneficiario
$col = @{ Jorge = 'J'; Susana = 'K'; Martin = 'L'; Saulo = 'M'; Miguel = 'N' }

# Mes y año a partir de la carpeta YYYYMM-Mes
$dir = Get-Item $Mes
if ($dir.Name -notmatch '^(\d{4})\d{2}-(.+)$') { throw "La carpeta $($dir.Name) no tiene el formato YYYYMM-Mes" }
$anio = $Matches[1]; $nombre = $Matches[2]
$dest = "$Mes\Mantenimiento_Comisiones_$($nombre)_$anio.xlsx"
if ((Test-Path $dest) -and -not $Sobrescribir) { throw "Ya existe $dest" }

# Concentrado del mes anterior (en enero se busca en la carpeta del año anterior)
$meses = @(Get-ChildItem (Split-Path $dir.Parent.FullName) -Directory | Where-Object Name -match '^\d{4}$' |
  ForEach-Object { Get-ChildItem $_.FullName -Directory } | Where-Object Name -match '^\d{6}-' | Sort-Object Name)
$ant = $meses | Where-Object { $_.Name -lt $dir.Name } | Select-Object -Last 1
if (-not $ant) { throw 'No se encontró la carpeta del mes anterior' }
$ant.Name -match '^(\d{4})\d{2}-(.+)$' | Out-Null
$base = "$($ant.FullName)\Mantenimiento_Comisiones_$($Matches[2])_$($Matches[1]).xlsx"
if (-not (Test-Path $base)) { throw "No existe $base" }

$ext = @(); if ($Externos) { $ext = Get-Content $Externos -Raw -Encoding UTF8 | ConvertFrom-Json; $ext = @($ext) }
if ($ext.Count -gt 3) { throw 'Hay más de 3 cambios externos; no caben en la tabla' }

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false
try {
  $wp = $xl.Workbooks.Open($procesos, 0, $true)
  $ur = $wp.Worksheets.Item(1).UsedRange; $v = $ur.Value2; $n = $ur.Rows.Count
  $wp.Close($false)
  $titulos = @{}
  for ($r = 2; $r -le $n; $r++) { $id = ([string]$v[$r,1]).Trim(); if ($id) { $titulos[$id] = (([string]$v[$r,2]).Trim() -replace '\s*-\s*', '-') } }

  # Cambios internos del mes con su importe tal como está guardado y la primera fecha de la columna D
  $cambios = foreach ($x in Get-ChildItem "$Mes\CambiosInternos" -Recurse -Filter 'HorasCambioTT*.xlsx') {
    $wh = $xl.Workbooks.Open($x.FullName, 0, $true)
    $ws = $wh.Worksheets.Item(1)
    $c = $ws.Range('H:H').Find('Importe Total').Row + 1
    $imp = [double]$ws.Cells.Item($c,8).Value2
    $fecha = [double]$xl.WorksheetFunction.Min($ws.Range('D:D'))
    $wh.Close($false)
    $tt = $x.BaseName -replace 'HorasCambio', ''
    if ($fecha -eq 0) { throw "$($x.Name) no tiene fechas en la columna D" }
    [pscustomobject]@{ TT = $tt; Num = [int]($tt -replace 'TT', ''); Carpeta = $x.Directory.Name; Importe = $imp; Fecha = $fecha }
  }
  $cambios = @($cambios | Sort-Object Num)
  if ($cambios.Count -gt 13) { throw 'Hay más de 13 cambios internos; no caben en la tabla' }

  $wb = $xl.Workbooks.Open($base, 0, $true)
  $ws = $wb.Worksheets.Item(1)
  $ws.Name = "$nombre $anio"
  $ws.Range('A2').Value2 = "Cálculo de comisiones del mes de $($nombre.ToLower()) de $anio"

  # Cambios externos; JAG siempre es de Martin
  $ws.Range('B7:H9').ClearContents() | Out-Null
  $ws.Range('J7:P9').ClearContents() | Out-Null
  $r = 7
  foreach ($e in $ext) {
    $jag = $e.Cliente -like '*JAG*'
    $ben = $(if ($e.Beneficiario) { $e.Beneficiario } elseif ($jag) { 'Martin' } else { throw "Falta el beneficiario de $($e.Factura)" })
    $fila = New-Object 'object[,]' 1, 7
    $fila[0,0] = $e.Factura
    $fila[0,1] = [datetime]::ParseExact($e.Fecha, 'dd/MM/yyyy', $null).ToOADate()
    $fila[0,2] = $e.Recibo
    $fila[0,3] = $e.Cliente
    $fila[0,4] = $(if ($jag) { 'Póliza Mantenimiento' } else { 'CAMBIO EXTERNO' })
    $fila[0,5] = [double]$e.Importe
    $fila[0,6] = [double]$e.Pct
    $ws.Range("B$($r):H$r").Value2 = $fila
    $ws.Range("I$r").Formula = "=G$r*H$r"
    $ws.Range("Q$r").Formula = "=SUM(J$($r):P$r)"
    $ws.Range("R$($r):X$r").Formula = "=`$I$r*J$r"
    $ws.Range("Y$r").Formula = "=SUM(R$($r):X$r)"
    $ws.Range("J$r").Value2 = 0.15
    $ws.Range("$($col[$ben])$r").Value2 = 0.85
    $r++
  }
  $ws.Range('A7:A9').EntireRow.Hidden = $true
  if ($r -gt 7) { $ws.Range("A7:A$($r-1)").EntireRow.Hidden = $false } else { $ws.Rows.Item(8).Hidden = $false }

  # Cambios internos (la fila 15 de Mejoras y la hoja Mejoras se conservan del mes anterior)
  $ws.Range('B16:H28').ClearContents() | Out-Null
  $ws.Range('J16:P28').ClearContents() | Out-Null
  for ($r = 16; $r -le 28; $r++) { $ws.Range("I$r").Formula = "=G$r*H$r" }
  $r = 16
  foreach ($c in $cambios) {
    if (-not $titulos[$c.TT]) { throw "$($c.TT) no está en CambiosProceso.xlsx" }
    $fila = New-Object 'object[,]' 1, 7
    $fila[0,0] = $c.TT
    $fila[0,1] = $c.Fecha
    $fila[0,2] = 'Ing. Jorge Orduño'
    $fila[0,3] = 'IMAGENSOFT'
    $fila[0,4] = $titulos[$c.TT]
    $fila[0,5] = $c.Importe
    $fila[0,6] = 0.15
    $ws.Range("B$($r):H$r").Value2 = $fila
    $ws.Range("J$r").Value2 = 0.25
    $ws.Range("$($col[$c.Carpeta])$r").Value2 = 0.75
    $r++
  }
  # Solo quedan visibles las filas con cambio
  $ws.Range('A16:A28').EntireRow.Hidden = $true
  if ($r -gt 16) { $ws.Range("A16:A$($r-1)").EntireRow.Hidden = $false }
  $ws.Range('G29').Formula = '=SUM(G16:G28)'
  $ws.Range('H34').Formula = '=IFERROR(AVERAGE(H7:H9),"")'
  $ws.Range('H35').Formula = '=IFERROR(AVERAGE(H16:H28),"")'

  $ws.Activate()
  $xl.Calculate()
  $wb.SaveAs($dest, 51)
  "Base: $base"
  ''
  "{0,-10} {1,-8} {2,-10} {3,12} {4,10}" -f 'TT', 'Colab.', 'Fecha', 'Importe', 'Comisión'
  for ($i = 16; $i -lt $r; $i++) { "{0,-10} {1,-8} {2,-10} {3,12:N2} {4,10:N2}" -f $ws.Range("B$i").Value2, ($cambios[$i-16].Carpeta), $ws.Range("C$i").Text, $ws.Range("G$i").Value2, $ws.Range("I$i").Value2 }
  ''
  'Externos: {0:N2}   Internos: {1:N2}   Total: {2:N2}' -f $ws.Range('I34').Value2, $ws.Range('I35').Value2, $ws.Range('I36').Value2
  ''
  'Resumen por beneficiario:'
  for ($i = 43; $i -le 50; $i++) { "{0,-16} {1,12:N2}" -f $ws.Range("C$i").Text, $ws.Range("E$i").Value2 }
  $wb.Close($false)
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
