param(
  [Parameter(Mandatory=$true)][string]$Carpeta,   # carpeta de la versión
  [Parameter(Mandatory=$true)][string]$Casos,     # casos.json (A-F, con tester asignado)
  [Parameter(Mandatory=$true)][string]$Json,      # acuerdos.json [{id,G,H,I,J}] en UTF-8
  [string]$Fecha = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Respaldo                               # carpeta para el respaldo (scratchpad)
)
# Si Acuerdos_IGAS_RSP.xlsx no existe se crea desde references\plantilla.xlsx con A-F de casos.json.
# Si existe, solo se escribe el tester (F) en las filas que no lo tienen.
# En ambos casos llena G-L: K = nombre de la carpeta (versión), L = fecha de reunión.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
$xlsx = Join-Path $Carpeta 'Acuerdos_IGAS_RSP.xlsx'
$version = Split-Path $Carpeta -Leaf
$d = [datetime]::ParseExact($Fecha, 'yyyy-MM-dd', $null)
$casosLista = Read-JsonArray $Casos
$data = Read-JsonArray $Json

$nuevo = -not (Test-Path $xlsx)
if ($nuevo) {
  Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'references\plantilla.xlsx') $xlsx
} else {
  try { $s = [IO.File]::Open($xlsx, 'Open', 'ReadWrite', 'None'); $s.Close() }
  catch { throw "El archivo esta abierto en Excel; cerrarlo y reintentar: $xlsx" }
  if ($Respaldo) { Copy-Item $xlsx (Join-Path $Respaldo 'Acuerdos_IGAS_RSP.backup.xlsx') -Force }
}

$xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
try {
  $wb = $xl.Workbooks.Open($xlsx); $ws = $wb.Worksheets.Item(1)
  if ($nuevo) {
    # La tabla de la plantilla tiene una fila vacía con el formato de datos; se extiende a todos los casos
    $ult = $casosLista.Count + 1
    $ws.ListObjects.Item(1).Resize($ws.Range("A1:L$ult"))
    # La fila 2 está vacía: copiarla al destino solo replica su formato (sin usar el portapapeles)
    if ($ult -gt 2) { $ws.Range('A2:L2').Copy($ws.Range("A3:L$ult")) | Out-Null }
    $r = 2
    foreach ($c in $casosLista) {
      $ws.Cells.Item($r, 1).Value2 = [string]$c.id
      $ws.Cells.Item($r, 2).Value2 = [string]$c.soporte
      $ws.Cells.Item($r, 3).Value2 = [string]$c.desc
      $ws.Cells.Item($r, 4).Value2 = [string]$c.tipo
      $ws.Cells.Item($r, 5).Value2 = (Normalize-Persona $c.resp)
      $ws.Cells.Item($r, 6).Value2 = (Normalize-Persona $c.tester)
      $r++
    }
  }
  $n = $ws.ListObjects.Item(1).Range.Rows.Count
  for ($r = 2; $r -le $n; $r++) {
    $id = $ws.Cells.Item($r, 1).Text.Trim()
    if ($id -eq '') { continue }
    $c = $casosLista | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $nuevo -and $c -and $c.tester -and $ws.Cells.Item($r, 6).Text.Trim() -eq '') { $ws.Cells.Item($r, 6).Value2 = (Normalize-Persona $c.tester) }
    # Responsable y Tester siempre con el nombre canónico del equipo
    foreach ($col in 5, 6) {
      $t = $ws.Cells.Item($r, $col).Text.Trim()
      if ($t -and (Normalize-Persona $t) -ne $t) { $ws.Cells.Item($r, $col).Value2 = (Normalize-Persona $t) }
    }
    $e = $data | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($e) {
      $ws.Cells.Item($r, 7).Value2 = [string]$e.G
      $ws.Cells.Item($r, 8).Value2 = ([string]$e.H -replace "`r", '')
      $ws.Cells.Item($r, 9).Value2 = ([string]$e.I -replace "`r", '')
      $ws.Cells.Item($r, 10).Value2 = ([string]$e.J -replace "`r", '')
    }
    $ws.Range("K$r").NumberFormat = '@'; $ws.Range("K$r").Value2 = $version
    $ws.Range("L$r").NumberFormat = 'dd/mm/aaaa;@'
    # Número de serie como texto: Excel lo guarda como constante numérica (asignar Double por COM falla en PS 5.1)
    $ws.Range("L$r").Formula = [string][int]$d.ToOADate()
    Write-Output ("{0} | {1} | {2} | T={3} | {4} | {5} | {6}" -f $r, $id, $ws.Cells.Item($r, 5).Text, $ws.Cells.Item($r, 6).Text, $(if ($e) { $e.G } else { 'SIN INFORME' }), $ws.Range("K$r").Text, $ws.Range("L$r").Text)
  }
  $ws.Range("H2:J$n").WrapText = $true
  $ws.Range("A2:L$n").VerticalAlignment = -4160
  $wb.Save(); $wb.Close()
  Write-Output $(if ($nuevo) { "Archivo creado desde la plantilla: $xlsx" } else { "Archivo actualizado: $xlsx" })
} catch {
  # Un archivo recién creado que no se terminó de llenar se elimina para poder reintentar
  if ($nuevo) { try { $wb.Close($false) } catch {}; Remove-Item $xlsx -Force -ErrorAction SilentlyContinue }
  throw
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
