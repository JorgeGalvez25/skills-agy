# Información para redactar la descripción breve de cada cambio (guardar en UTF-8 con BOM: PowerShell 5.1)
# Sin -Ado: título y actividades del HorasCambio. Con -Ado: ramas, commits y archivos en Azure DevOps.
param([string]$Mes = (Get-Location).Path, [string[]]$TT, [switch]$Ado)
$ErrorActionPreference = 'Stop'
. 'C:\Users\jorge\.claude\skills\mtto-revpr\scripts\comun.ps1'

$archivos = @(Get-ChildItem "$Mes\CambiosInternos" -Recurse -Filter 'HorasCambioTT*.xlsx' | Where-Object { -not $TT -or ($_.BaseName -replace 'HorasCambio', '') -in $TT })

if (-not $Ado) {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $false; $xl.DisplayAlerts = $false
  # Valores de la primera hoja
  $leer = { param($ruta) $wb = $xl.Workbooks.Open($ruta, 0, $true); $v = $wb.Worksheets.Item(1).UsedRange.Value2; $wb.Close($false); , $v }
  try {
    $v = & $leer 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\CambiosProceso.xlsx'
    $titulos = @{}
    for ($r = 2; $r -le $v.GetLength(0); $r++) { $id = ([string]$v[$r,1]).Trim(); if ($id) { $titulos[$id] = ([string]$v[$r,2]).Trim() } }
    foreach ($x in $archivos) {
      $tt = $x.BaseName -replace 'HorasCambio', ''
      "== $tt ($($x.Directory.Name)): $($titulos[$tt])"
      # Actividades: columna A = tarea, columna B = descripción
      $v = & $leer $x.FullName
      $(for ($r = 2; $r -le $v.GetLength(0); $r++) { if ($v[$r,1] -and $v[$r,2]) { "   $($v[$r,1]): $($v[$r,2])" } }) | Select-Object -Unique
    }
  } finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
  return
}

$script:H = Get-Headers
$nums = @($archivos | ForEach-Object { Get-NumTT $_.BaseName })
$repos = (Invoke-Ado "$Org/_apis/git/repositories?api-version=7.1").value
$hay = @{}
foreach ($rp in $repos) {
  try { $refs = (Invoke-Ado "$Org/$($rp.project.id)/_apis/git/repositories/$($rp.id)/refs?filter=heads/&api-version=7.1").value } catch { continue }
  foreach ($ref in $refs) {
    $n = Get-NumTT $ref.name
    if ($nums -notcontains $n) { continue }
    $hay[$n] = 1
    $rama = $ref.name -replace 'refs/heads/', ''
    $base = $rp.defaultBranch -replace 'refs/heads/', ''
    $d = Invoke-Ado "$Org/$($rp.project.id)/_apis/git/repositories/$($rp.id)/diffs/commits?baseVersion=$base&targetVersion=$rama&`$top=200&api-version=7.1"
    "== TT$n [$($rp.name) / $rama]"
    $c = (Invoke-Ado "$Org/$($rp.project.id)/_apis/git/repositories/$($rp.id)/commits?searchCriteria.itemVersion.version=$rama&searchCriteria.`$top=$([Math]::Max(1, $d.aheadCount))&api-version=7.1").value
    $c | ForEach-Object { '   * ' + ($_.comment -replace '\s+', ' ') }
    $d.changes | Where-Object { $_.item.gitObjectType -eq 'blob' } | Select-Object -First 30 | ForEach-Object { "   $($_.changeType) $($_.item.path)" }
  }
}
$nums | Where-Object { -not $hay[$_] } | ForEach-Object { "== TT$_ sin rama en Azure DevOps" }
