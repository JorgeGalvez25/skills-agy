param(
  [Parameter(Mandatory=$true)][string]$Carpeta,   # carpeta de la versión (contiene los .zip/.rar y, si ya existe, Acuerdos_IGAS_RSP.xlsx)
  [Parameter(Mandatory=$true)][string]$Salida     # carpeta de trabajo (scratchpad)
)
# Extrae los .md de /mtto-docu de los comprimidos y genera:
#  - casos.json: columnas A-F por caso (del Excel si existe; si no, de las fichas de los informes)
#  - digest.md: secciones 1-4 de cada informe (ficha, resumen, entregables, hallazgos)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

# Solo se extraen los .md, sin subcarpetas y en una ruta corta (los nombres de los informes son largos)
$ext = Join-Path $env:TEMP 'mttoacu'
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
New-Item -ItemType Directory -Force $ext | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$unrar = @('C:\Program Files\WinRAR\UnRAR.exe', 'C:\Program Files\7-Zip\7z.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
$docx = @{}; $informes = @{}; $nombres = @{}
$i = 0
foreach ($a in Get-ChildItem $Carpeta -File | Where-Object { $_.Extension -in '.zip', '.rar', '.7z' }) {
  $i++; $dest = Join-Path $ext $i
  New-Item -ItemType Directory -Force $dest | Out-Null
  if ($a.Extension -eq '.zip') {
    $z = [IO.Compression.ZipFile]::OpenRead($a.FullName)
    try {
      foreach ($en in $z.Entries) {
        if ($en.Name -notmatch 'TT(\d+)') { continue }
        $tt = 'TT' + $Matches[1]
        if ($en.Name -like '*.md') {
          $p = Join-Path $dest "$tt.md"
          [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $p, $true)
          $informes[$tt] = $p; $nombres[$tt] = $en.Name
        } elseif ($en.Name -like '*.docx') { $docx[$tt] = $a.Name }
      }
    } finally { $z.Dispose() }
  } else {
    if ($unrar -like '*UnRAR.exe') { & $unrar e -o+ -inul $a.FullName '*.md' "$dest\" | Out-Null; $lista = & $unrar lb $a.FullName }
    else { & $unrar e -y "-o$dest" $a.FullName '*.md' -r | Out-Null; $lista = & $unrar l -ba -slt $a.FullName | Where-Object { $_ -like 'Path = *' } }
    foreach ($l in $lista) { if ($l -like '*.docx' -and $l -match 'TT(\d+)') { $docx['TT' + $Matches[1]] = $a.Name } }
    foreach ($f in Get-ChildItem $dest -Filter *.md) {
      if ($f.Name -match 'TT(\d+)') { $informes['TT' + $Matches[1]] = $f.FullName; $nombres['TT' + $Matches[1]] = $f.Name }
    }
  }
}

# Ficha del informe -> columnas A-F
function Get-Ficha($tt) {
  $lineas = Get-Content -LiteralPath $informes[$tt] -Encoding UTF8
  $campo = { param($n) ($lineas | Where-Object { $_ -match "^\|\s*$n\s*\|" } | Select-Object -First 1) -replace "^\|\s*$n\s*\|\s*", '' -replace '\s*\|\s*$', '' }
  $tipo = if ((& $campo 'Tipo') -match 'Cambio') { 'Cambio' } else { 'Fallo' }
  $ticket = & $campo 'Ticket VTiger'
  $soporte = '-'
  if ($tipo -eq 'Fallo') { $m = [regex]::Matches($ticket, 'TT\d+') | Where-Object { $_.Value -ne $tt } | Select-Object -First 1; if ($m) { $soporte = $m.Value } }
  $desc = [IO.Path]::GetFileNameWithoutExtension($nombres[$tt])
  if ($desc -match '_IC_(.+)$') { $desc = $Matches[1] }
  $desc = ($desc -replace '^(TT\d+)\s*-\s*', '$1 - ').Trim()
  [pscustomobject]@{ id = $tt; soporte = $soporte; desc = $desc; tipo = $tipo; resp = (Normalize-Persona ((& $campo 'Desarrollador\(es\)') -split '[,/y]\s' | Select-Object -First 1)); tester = ''; fila = $null; informe = $true }
}

$xlsx = Join-Path $Carpeta 'Acuerdos_IGAS_RSP.xlsx'
$existe = Test-Path $xlsx
$casos = @()
if ($existe) {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try {
    $wb = $xl.Workbooks.Open($xlsx, 0, $true); $ws = $wb.Worksheets.Item(1)
    $n = $ws.UsedRange.Rows.Count
    for ($r = 2; $r -le $n; $r++) {
      $id = $ws.Cells.Item($r, 1).Text.Trim()
      if ($id -eq '') { continue }
      $casos += [pscustomobject]@{ id = $id; soporte = $ws.Cells.Item($r, 2).Text; desc = $ws.Cells.Item($r, 3).Text; tipo = $ws.Cells.Item($r, 4).Text
        resp = $ws.Cells.Item($r, 5).Text; tester = $ws.Cells.Item($r, 6).Text; fila = $r; informe = $informes.ContainsKey($id)
        lleno = (($ws.Cells.Item($r, 7).Text + $ws.Cells.Item($r, 8).Text) -ne '') }
    }
    $wb.Close($false)
  } finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
} else {
  # Orden del archivo: desarrollador (orden del equipo), Fallos antes que Cambios, número de TT
  $casos = @($informes.Keys | ForEach-Object { Get-Ficha $_ } | Sort-Object @{ e = { Get-OrdenPersona $_.resp } }, @{ e = { if ($_.tipo -eq 'Fallo') { 0 } else { 1 } } }, @{ e = { [int]($_.id -replace '\D', '') } })
}
$jsonCasos = Join-Path $Salida 'casos.json'
[IO.File]::WriteAllText($jsonCasos, (ConvertTo-Json -InputObject $casos -Depth 3), (New-Object Text.UTF8Encoding $false))

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Digest acuerdos - $Carpeta")
[void]$sb.AppendLine("Excel: $(if ($existe) { 'existe (A-F tomadas del archivo)' } else { 'NO existe: se creara desde la plantilla con A-F de los informes' })")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Fila | ID | ID Soporte | Tipo | Responsable | Tester | Informe .md | G/H ya llenos |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
foreach ($f in $casos) {
  $inf = if ($informes.ContainsKey($f.id)) { 'si' } elseif ($docx.ContainsKey($f.id)) { "NO (solo .docx en $($docx[$f.id]))" } else { 'NO' }
  [void]$sb.AppendLine("| $($f.fila) | $($f.id) | $($f.soporte) | $($f.tipo) | $($f.resp) | $($f.tester) | $inf | $(if ($f.lleno) {'si'} else {''}) |")
}
$sobran = $informes.Keys | Where-Object { $_ -notin $casos.id }
if ($sobran) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("Informes sin fila en el Excel: $($sobran -join ', ')") }
$sinMd = $docx.Keys | Where-Object { -not $informes.ContainsKey($_) -and $_ -notin $casos.id }
if ($sinMd) { [void]$sb.AppendLine("Informes solo .docx (sin .md, no se incluyen): $($sinMd -join ', ')") }

foreach ($f in $casos) {
  if (-not $informes.ContainsKey($f.id)) { continue }
  $lineas = Get-Content -LiteralPath $informes[$f.id] -Encoding UTF8
  [void]$sb.AppendLine(''); [void]$sb.AppendLine("################ $($f.id) - $($f.desc)")
  $dentro = $false; $sec = ''
  foreach ($l in $lineas) {
    if ($l -match '^## (\d)\.') { $sec = $Matches[1]; $dentro = ($sec -in '1', '2', '3', '4') }
    elseif ($l -match '^## ') { $dentro = $false }
    if (-not $dentro) { continue }
    # Se omiten la tabla de ejecutables (3.2), filas vacías y campos sin valor útil
    if ($l -match '^### 3\.2') { $sec = '3.2'; continue }
    if ($l -match '^### 3\.3') { $sec = '3' }
    if ($sec -eq '3.2') { continue }
    if ($l -match '^\s*$' -or $l -match '^\|---' -or $l -match 'Revisor asignado|^\| Campo \| Valor|^\*\*Ruido en el diff') { continue }
    if ($l.Length -gt 450) { $l = $l.Substring(0, 450) + '...' }
    [void]$sb.AppendLine($l)
  }
}
$out = Join-Path $Salida 'digest.md'
[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Output "digest: $out | casos: $jsonCasos ($($casos.Count) casos, $($informes.Count) informes, Excel $(if ($existe) {'existe'} else {'NO existe'}))"
