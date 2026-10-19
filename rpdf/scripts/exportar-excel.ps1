param([string]$Dir, [string]$Out)
# Exporta cada .xlsx de $Dir a $Out\<nombre>.pdf (solo hojas visibles, una página por hoja).
# Los ajustes se hacen en memoria: el libro se abre de solo lectura y se cierra sin guardar.
Add-Type -AssemblyName System.Drawing
$m = 36  # márgenes de 0.5"
# Papeles del más chico al más grande (xlPaperLetter=1, Legal=5, Tabloid=3), en puntos
$papeles = @(@{Id=1;W=612;H=792;N='Carta'}, @{Id=5;W=612;H=1008;N='Oficio'}, @{Id=3;W=792;H=1224;N='Tabloide'})
$g = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1,1))
$g.PageUnit = [System.Drawing.GraphicsUnit]::Point

# Ancho aproximado en puntos del texto de una celda con su fuente
function AnchoTexto($c) {
  $st = [System.Drawing.FontStyle]::Regular
  if ($c.Font.Bold -eq $true) { $st = [System.Drawing.FontStyle]::Bold }
  $fn = New-Object System.Drawing.Font([string]$c.Font.Name, [single]$c.Font.Size, $st, [System.Drawing.GraphicsUnit]::Point)
  $w = $g.MeasureString([string]$c.Text, $fn, 100000, [System.Drawing.StringFormat]::GenericTypographic).Width; $fn.Dispose(); $w
}

$x = New-Object -ComObject Excel.Application; $x.Visible=$false; $x.DisplayAlerts=$false
try {
foreach ($f in Get-ChildItem (Join-Path $Dir "*.xlsx") | Where-Object { $_.Name -notlike '~$*' }) {
  $wb = $x.Workbooks.Open($f.FullName, 0, $true)
  foreach ($ws in $wb.Worksheets) {
    if ($ws.Visible -ne -1) { "OMITIDA (oculta) {0} [{1}]" -f $f.Name, $ws.Name; continue }
    # Área de impresión: rango usado ampliado para incluir gráficas e imágenes grandes
    $ur = $ws.UsedRange
    $r1 = $ur.Row; $c1 = $ur.Column
    $r2 = $r1 + $ur.Rows.Count - 1; $c2 = $c1 + $ur.Columns.Count - 1
    foreach ($s in $ws.Shapes) {
      if ($s.Width -lt 20) { continue }
      $br = $s.BottomRightCell
      if ($br.Row -gt $r2) { $r2 = $br.Row }; if ($br.Column -gt $c2) { $c2 = $br.Column }
    }
    # Texto que no cabe: en tablas simples se ensancha la columna; en hojas con gráficas o celdas combinadas se reduce la fuente
    $vals = $ws.Range($ws.Cells.Item($r1,$c1), $ws.Cells.Item($r2,$c2+1)).Value2
    $conGraficas = $ws.ChartObjects().Count -gt 0
    $anchos = @{}
    for ($r=$r1; $r -le $r2; $r++) {
      for ($c=$c1; $c -le $c2; $c++) {
        $v = $vals[($r-$r1+1), ($c-$c1+1)]
        if ($null -eq $v -or "$v" -eq '') { continue }
        $cel = $ws.Cells.Item($r,$c)
        if ($cel.EntireRow.Hidden -or $cel.EntireColumn.Hidden) { continue }
        $txt = AnchoTexto $cel
        if ($cel.MergeCells) {
          $ma = $cel.MergeArea
          $lineas = [Math]::Max(1, [Math]::Floor($ma.Height / ($cel.Font.Size * 1.3)))
          $cabe = if ($cel.WrapText -eq $true) { $ma.Width * $lineas } else { $ma.Width }
          if ($txt + 4 -gt $cabe) { $cel.WrapText = $false; $cel.ShrinkToFit = $true; "  reduce fuente {0}!{1}: {2}" -f $ws.Name, $cel.Address(0,0), $cel.Text }
          continue
        }
        if ($cel.WrapText -eq $true) { continue }
        $vecino = $vals[($r-$r1+1), ($c-$c1+2)]
        $libre = ($c -lt $c2) -and ($null -eq $vecino -or "$vecino" -eq '') -and ($cel.HorizontalAlignment -in 1,-4131)
        if ($libre -or $txt + 4 -le $cel.Width) { continue }
        if ($conGraficas) { $cel.ShrinkToFit = $true; "  reduce fuente {0}!{1}: {2}" -f $ws.Name, $cel.Address(0,0), $cel.Text }
        elseif (-not $anchos.ContainsKey($c) -or $anchos[$c] -lt $txt) { $anchos[$c] = $txt }
      }
    }
    foreach ($c in $anchos.Keys) {
      $col = $ws.Columns.Item($c); $ant = $col.Width
      $col.ColumnWidth = $col.ColumnWidth * ($anchos[$c] + 8) / $col.Width
      "  ensancha {0}!col {1}: {2:N0} -> {3:N0}pt" -f $ws.Name, $c, $ant, $col.Width
    }

    $area = $ws.Range($ws.Cells.Item($r1,$c1), $ws.Cells.Item($r2,$c2))
    $w = $area.Width; $h = $area.Height
    # Papel más chico con escala >= 70% (mejor orientación); si ninguno, el de mayor escala
    $mejor = $null
    foreach ($p in $papeles) {
      $local = $null
      foreach ($o in @(@{Id=1;W=$p.W;H=$p.H;N='vertical'}, @{Id=2;W=$p.H;H=$p.W;N='horizontal'})) {
        $esc = [Math]::Min([double]1, [Math]::Min([double](($o.W-2*$m)/$w), [double](($o.H-2*$m)/$h)))
        if ($null -eq $local -or $esc -gt $local.E) { $local = @{P=$p;O=$o;E=$esc} }
      }
      if ($null -eq $mejor -or $local.E -gt $mejor.E) { $mejor = $local }
      if ($mejor.E -ge 0.7) { break }
    }
    # PrintCommunication apagado acelera mucho los cambios de PageSetup
    $x.PrintCommunication = $false
    $ps = $ws.PageSetup
    $ps.PrintArea = $area.Address()
    $ps.PaperSize = $mejor.P.Id
    $ps.Orientation = $mejor.O.Id
    $ps.LeftMargin = $m; $ps.RightMargin = $m; $ps.TopMargin = $m; $ps.BottomMargin = $m
    $ps.HeaderMargin = 18; $ps.FooterMargin = 18
    $ps.CenterHorizontally = $true
    $ps.Zoom = $false; $ps.FitToPagesWide = 1; $ps.FitToPagesTall = 1
    $x.PrintCommunication = $true
    "HOJA {0} [{1}] {2} {3:N0}x{4:N0}pt -> {5} {6}, escala ~{7:P0}" -f $f.Name, $ws.Name, $area.Address(0,0), $w, $h, $mejor.P.N, $mejor.O.N, $mejor.E
  }
  $pdf = Join-Path $Out ($f.BaseName + ".pdf")
  $wb.ExportAsFixedFormat(0, $pdf, 0, $true, $false)
  $wb.Close($false)
  "PDF  $pdf"
}
} finally { $x.Quit() }
