param([string]$Mes = (Get-Location).Path, [switch]$Sobrescribir)
$ErrorActionPreference = 'Stop'
$tpl = "$(Split-Path $PSScriptRoot)\plantillas\Beneficiario.xlsx"

# Mes y año a partir de la carpeta YYYYMM-Mes
$dir = Get-Item $Mes
if ($dir.Name -notmatch '^(\d{4})\d{2}-(.+)$') { throw "La carpeta $($dir.Name) no tiene el formato YYYYMM-Mes" }
$anio = $Matches[1]; $nombre = $Matches[2]
$conc = "$Mes\Mantenimiento_Comisiones_$($nombre)_$anio.xlsx"
if (-not (Test-Path $conc)) { throw "No existe $conc" }
$salida = "$Mes\PorBeneficiario"
New-Item -ItemType Directory -Force $salida | Out-Null

# Fila donde está un texto en la columna indicada (Find no funciona con las celdas combinadas)
function Fila($ws, $col, $texto) { for ($r = 1; $r -le 80; $r++) { if ($ws.Cells.Item($r,$col).Value2 -eq $texto) { return $r } }; throw "No se encontró '$texto' en la plantilla" }

# Ajusta las filas de datos de una tabla y escribe B:J; sin filas queda solo el total en ceros
function Llenar($ws, $titulo, $filas) {
  $ini = (Fila $ws 2 $titulo) + 2
  $fin = $ini; while ($ws.Cells.Item($fin,7).Formula -notlike '=SUM(*') { $fin++ }
  $n = $filas.Count; $act = $fin - $ini
  if ($n -eq 0) {
    $ws.Rows("$($ini):$($fin-1)").Delete() | Out-Null
    foreach ($c in 'G', 'I', 'J') { $ws.Range("$c$ini").Value2 = 0 }
    return
  }
  if ($n -gt $act) { $ws.Rows($ini).Copy() | Out-Null; $ws.Rows("$($ini+1):$($ini+$n-$act)").Insert() | Out-Null }
  elseif ($n -lt $act) { $ws.Rows("$($ini+$n):$($fin-1)").Delete() | Out-Null }
  $ws.Range("B$($ini):J$($ini+$n-1)").ClearContents() | Out-Null
  $arr = New-Object 'object[,]' $n, 9
  for ($i = 0; $i -lt $n; $i++) { for ($j = 0; $j -lt 9; $j++) { $arr[$i,$j] = $filas[$i][$j] } }
  $ws.Range("B$($ini):J$($ini+$n-1)").Value2 = $arr
  foreach ($c in 'G', 'I', 'J') { $ws.Range("$c$($ini+$n)").Formula = "=SUM($c$($ini):$c$($ini+$n-1))" }
}

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false
try {
  # Valores calculados del concentrado: B:I de cada fila y lo que le toca a cada quien en R:V
  $wb = $xl.Workbooks.Open($conc, 0, $true)
  $xl.Calculate()
  $v = $wb.Worksheets.Item(1).Range('A1:Y36').Value2
  $wb.Close($false)
  $total = [double]$v[36,9]

  "{0,-18} {1,12}  {2}" -f 'Beneficiario', 'Total', 'Archivo'
  $suma = 0
  # Lo de cada persona está en R:V (columnas 18 a 22); su número en la fila 5 y su nombre en la 6
  for ($cp = 18; $cp -le 22; $cp++) {
    if ([double]$v[36,$cp] -eq 0) { continue }
    $persona = [string]$v[6,$cp]; $no = $v[5,$cp]
    # Jorge no recibe archivo; su parte se descuenta del total a cuadrar
    if ($persona -eq 'Jorge Gálvez') { $total -= [double]$v[36,$cp]; continue }
    $dest = "$salida\Mantenimiento_Comisiones_$($nombre)_$($anio)_$($persona -replace ' ', '_').xlsx"
    if ((Test-Path $dest) -and -not $Sobrescribir) { throw "Ya existe $dest" }

    # Filas con importe para esta persona: B:I tal cual y su parte en J
    $ext = @(); $int = @()
    foreach ($r in 7..9 + 15..28) {
      $imp = [double]$v[$r,$cp]
      if (-not $v[$r,6] -or $imp -eq 0) { continue }
      $fila = @(); for ($c = 2; $c -le 9; $c++) { $fila += $v[$r,$c] }; $fila += $imp
      if ($r -le 9) { $ext += ,$fila } else { $int += ,$fila }
    }

    $wp = $xl.Workbooks.Open($tpl, 0, $true)
    $wp.SaveAs($dest, 51)
    $hp = $wp.Worksheets.Item(1)
    $hp.Range('A2').Value2 = "Cálculo de comisiones del mes de $($nombre.ToLower()) de $anio"
    Llenar $hp 'Cambios Internos' $int
    Llenar $hp 'Cambios Externos' $ext
    # Nombre y número de la persona en los encabezados y en el resumen final
    $hp.UsedRange.Replace('Jorge Gálvez', $persona, 1) | Out-Null
    for ($r = 1; $r -le $hp.UsedRange.Rows.Count; $r++) {
      $b = [string]$hp.Cells.Item($r,2).Value2
      if ($b -in 'Cambios Externos', 'Cambios Internos', 'Resumen de Comisiones') { $hp.Cells.Item($r,10).Value2 = $no }
      if ($b -eq 'No') { $hp.Cells.Item($r+1,2).Value2 = $no }
    }
    $hp.Activate(); $hp.Range('A1').Select() | Out-Null
    $xl.Calculate()
    $tot = [double]$hp.Cells.Item((Fila $hp 5 'Importe') + 2, 5).Value2
    $wp.Save()
    $wp.Close($false)
    $suma += $tot
    "{0,-18} {1,12:N2}  {2}" -f $persona, $tot, (Split-Path $dest -Leaf)
  }
  ''
  'Suma: {0:N2}   Total del concentrado sin Jorge Gálvez: {1:N2}' -f $suma, $total
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
