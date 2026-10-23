param([string]$Mes = (Get-Location).Path, [switch]$Sobrescribir)
$ErrorActionPreference = 'Stop'
$sk = Split-Path $PSScriptRoot
$tplHoras = "$sk\plantillas\HorasCambio.xlsx"
$procesos = 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx'

if (-not (Test-Path "$Mes\CambiosInternos")) { throw "No existe $Mes\CambiosInternos" }

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false
$resumen = @(); $procesados = @()
try {
  # Títulos y estatus de CambiosProceso
  $wp = $xl.Workbooks.Open($procesos, 0, $true)
  $ur = $wp.Worksheets.Item(1).UsedRange; $v = $ur.Value2; $n = $ur.Rows.Count
  $wp.Close($false)
  $titulos = @{}; $estatus = @{}
  for ($r = 2; $r -le $n; $r++) {
    $id = ([string]$v[$r,1]).Trim()
    if ($id) { $titulos[$id] = (([string]$v[$r,2]).Trim() -replace '\s*-\s*', '-'); $estatus[$id] = [string]$v[$r,4] }
  }

  foreach ($dir in Get-ChildItem "$Mes\CambiosInternos" -Directory) {
    foreach ($raw in Get-ChildItem $dir.FullName -Filter 'Reporte Hrs Caso*.xls') {
      $wr = $xl.Workbooks.Open($raw.FullName, 0, $true)
      $v = $wr.Worksheets.Item(1).UsedRange.Value2
      $n = $wr.Worksheets.Item(1).UsedRange.Rows.Count
      $wr.Close($false)
      $tt = [string]$v[2,1]
      if (-not $titulos[$tt]) { throw "$tt ($($raw.Name)) no está en CambiosProceso.xlsx" }
      $tareas = @(); $ultima = $null; $dev = $null
      for ($r = 2; $r -le $n; $r++) {
        $tarea = [string]$v[$r,2]; $desc = [string]$v[$r,3]; $hr = [double]$v[$r,9]
        $fs = [string]$v[$r,10]
        $f = [datetime]::ParseExact($fs, 'dd-MM-yyyy', $null)
        $tareas += ,@($tarea, $desc, $hr, $f.ToOADate())
        if ($ultima -eq $null -or $f -gt $ultima) { $ultima = $f }
        if ($tarea -like 'Codificaci*') { $dev = [string]$v[$r,11] }
      }

      # Archivo de horas del cambio
      $dest = Join-Path $dir.FullName "HorasCambio$tt.xlsx"
      if ((Test-Path $dest) -and -not $Sobrescribir) { throw "Ya existe $dest" }
      $wb = $xl.Workbooks.Open($tplHoras)
      $ws = $wb.Worksheets.Item(1)
      $ws.Rows('3:11').Delete() | Out-Null
      $k = $tareas.Count
      if ($k -gt 1) { $ws.Rows(2).Copy() | Out-Null; $ws.Rows("3:$($k+1)").Insert() | Out-Null }
      # Fecha de cada registro en D; el concentrado toma la primera
      $ws.Range("C1:C$($k+1)").Copy($ws.Range('D1')) | Out-Null
      $ws.Range('D1').Value2 = 'Fecha'
      $ws.Range("D2:D$($k+1)").NumberFormatLocal = 'dd/mm/aaaa'
      $ws.Columns.Item('D').ColumnWidth = 12
      $arr = New-Object 'object[,]' $k, 4
      for ($i = 0; $i -lt $k; $i++) { for ($j = 0; $j -lt 4; $j++) { $arr[$i,$j] = $tareas[$i][$j] } }
      $ws.Range("A2:D$($k+1)").Value2 = $arr
      $t = $k + 2; $u = $k + 1
      $ws.Cells.Item($t,3).Formula = "=SUMIF(A2:A$u,""Codificación"",C2:C$u)+SUMIF(A2:A$u,""Codificacion"",C2:C$u)"
      $ws.Cells.Item($t+2,6).Value2 = $dev
      $c = $t + 6
      $ws.Cells.Item($c,6).Formula = "=C$t*(1-C$($t+1))"
      $ws.Cells.Item($c,8).Formula = "=F$c*G$c"
      $ws.Cells.Item($c,9).Formula = "=H$c*0.15"
      $ws.Cells.Item($c,10).Formula = "=I$c*0.75"
      $ws.Cells.Item($c,11).Formula = "=I$c*0.25"
      $ws.Range('A1').Select() | Out-Null
      $wb.SaveAs($dest, 51)
      $imp = [double]$ws.Cells.Item($c,8).Value2
      $hrs = [double]$ws.Cells.Item($c,6).Value2
      $wb.Close($false)
      $resumen += [pscustomobject]@{ Carpeta = $dir.Name; TT = $tt; Archivo = $raw.Name; Codifico = $dev; Horas = $hrs; Importe = $imp; Ultima = $ultima.ToString('dd/MM/yyyy'); Estatus = $estatus[$tt]; Titulo = $titulos[$tt] }
      $procesados += $raw.FullName
    }
  }
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
# Solo si todos se generaron bien: se borran los .xls base de VTiger
foreach ($p in $procesados) { Remove-Item -LiteralPath $p }
$resumen | Format-List
if ($procesados.Count) { "Se eliminaron $($procesados.Count) archivo(s) .xls base." }
