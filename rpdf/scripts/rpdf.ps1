param([string]$Dir = (Get-Location).Path, [string]$Png)
# Orquesta la exportación de los reportes de $Dir (por omisión, la carpeta actual) a $Dir\PDF y su renderizado a PNG.
# Cada paso corre en un proceso aparte con límite de tiempo; al final se cierran las instancias de Office que haya abierto.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Dir -PathType Container)) { "ERROR: no existe la carpeta $Dir"; exit 1 }
$dir = (Resolve-Path $Dir).Path
$out = Join-Path $dir 'PDF'
if (-not $Png) { $Png = Join-Path $env:TEMP ("rpdf_" + (Split-Path $dir -Leaf)) }
New-Item -ItemType Directory -Force $Png | Out-Null
Get-ChildItem $Png -Filter *.png | Remove-Item -Force
$sc = $PSScriptRoot

$xlsx = @(Get-ChildItem (Join-Path $dir '*.xlsx') | Where-Object { $_.Name -notlike '~$*' })
$docx = @(Get-ChildItem (Join-Path $dir '*.docx') | Where-Object { $_.Name -notlike '~$*' })
"ENTRADA {0} Excel, {1} Word en {2}" -f $xlsx.Count, $docx.Count, $dir
$xlsx + $docx | ForEach-Object { "  - " + $_.Name }
if (-not ($xlsx.Count + $docx.Count)) { "ERROR: la carpeta no tiene archivos .xlsx ni .docx"; exit 1 }
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null; "CREADA $out" }

$antes = @(Get-Process EXCEL, WINWORD -ErrorAction SilentlyContinue | ForEach-Object Id)

function Paso($nombre, $script, $argsPaso, $minutos) {
  "== $nombre"
  # Start-Job: modo de ejecución en el que la automatización COM de Word responde
  $j = Start-Job -FilePath "$sc\$script" -ArgumentList $argsPaso
  if (-not (Wait-Job $j -Timeout ($minutos * 60))) { Stop-Job $j; "ERROR: $nombre excedió $minutos min y se detuvo" }
  Receive-Job $j -ErrorVariable errs 2>$null
  foreach ($e in $errs) { "ERROR en ${nombre}: $e" }
  Remove-Job $j -Force
}

if ($xlsx.Count) { Paso 'excel' 'exportar-excel.ps1' @($dir, $out) 15 }
if ($docx.Count) { Paso 'word' 'exportar-word.ps1' @($dir, $out, (Join-Path $Png 'tmp')) 5 }

# Instancias de Office abiertas por este proceso que hayan quedado vivas
Get-Process EXCEL, WINWORD -ErrorAction SilentlyContinue |
  Where-Object { $antes -notcontains $_.Id -and $_.MainWindowHandle -eq 0 } |
  ForEach-Object { "Cerrando $($_.Name) residual ($($_.Id))"; Stop-Process -Id $_.Id -Force }

Paso 'render' 'render.ps1' @($out, $Png) 5
"SALIDA $out"
Get-ChildItem $out -Filter *.pdf | ForEach-Object { "  {0}  {1:N0} KB" -f $_.Name, ($_.Length/1KB) }
