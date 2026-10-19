# /mtto-revpr paso 1: casos del Excel de acuerdos → PR de Azure DevOps → código base/head/diff, informes internos y cruces entre PR
param(
  [Parameter(Mandatory)][string]$Carpeta,
  [Parameter(Mandatory)][string]$Salida
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
$script:H = Get-Headers
$version = Split-Path $Carpeta -Leaf
$excel = Join-Path $Carpeta 'Acuerdos_IGAS_RSP.xlsx'
if (-not (Test-Path $excel)) { throw "SIN_ACUERDOS: no existe $excel (generarlo antes con /mtto-acuerdos)." }
New-Item -ItemType Directory -Force $Salida | Out-Null

# --- 1. Casos del Excel y de la nota de atención especial ---
$filas = @(Read-XlsxHoja $excel 'RSP' | Where-Object { Get-NumTT $_.ID })
$nota = Join-Path $Carpeta "Atencion_Especial_$version.md"
$notaLineas = if (Test-Path $nota) { @(Get-Content $nota -Encoding UTF8) } else { @() }

# Nivel según la nota de /mtto-acuerdos: columna 2 de la tabla (Crítico/Atención), viñeta bajo "También con una señal" (Señal)
# o la línea "El resto son cambios acotados" (Acotado)
function Get-Nivel([int]$num) {
  $seccion = ''
  foreach ($l in $notaLineas) {
    if ($l -match '(?i)con una señal') { $seccion = 'Señal' }
    if ($l -notmatch "TT0*$num(?!\d)") { continue }
    if ($l -match '^\s*\|') { return (($l -split '\|')[2] -replace '[*\s]', '') }
    if ($l -match '(?i)acotad') { return 'Acotado' }
    if ($seccion) { return $seccion }
  }
  if ($notaLineas) { 'Sin mención' } else { '—' }
}

# --- 2. Informes internos (.md de /mtto-docu) de los comprimidos; ruta corta para no rebasar 260 caracteres ---
# Los comprimidos traen carpetas con el título del TT: se extraen a "crudo" y cada .md se copia sin carpetas a "informes"
# con rutas \\?\ (Remove-Item y Get-ChildItem de PS 5.1 fallan pasando los 260 caracteres).
if (-not $env:TEMP) { throw 'Variable TEMP vacía.' }
$dirInf = Join-Path $env:TEMP "mttorev\$version"
if (Test-Path $dirInf) { cmd /c rd /s /q "\\?\$dirInf" }
foreach ($a in Get-ChildItem $Carpeta -File | Where-Object { $_.Extension -in '.zip', '.rar', '.7z' }) {
  $crudo = Join-Path $dirInf "crudo\$($a.BaseName)"; $plano = Join-Path $dirInf "informes\$($a.BaseName)"
  New-Item -ItemType Directory -Force $crudo, $plano | Out-Null
  $ErrorActionPreference = 'Continue'
  & "$env:SystemRoot\System32\tar.exe" -xf $a.FullName -C $crudo --include '*.md' 2>$null
  $ErrorActionPreference = 'Stop'
  foreach ($m in [IO.Directory]::EnumerateFiles("\\?\$crudo", '*.md', 'AllDirectories')) { [IO.File]::Copy($m, (Join-Path $plano ([IO.Path]::GetFileName($m))), $true) }
}
if (Test-Path "$dirInf\crudo") { cmd /c rd /s /q "\\?\$dirInf\crudo" }
$informes = @(if (Test-Path "$dirInf\informes") { Get-ChildItem "$dirInf\informes" -Recurse -File -Filter *.md })

# --- 3. Pull requests de la organización (todos los estados, más recientes primero) ---
$prs = @((Invoke-Ado "$Org/_apis/git/pullrequests?searchCriteria.status=all&`$top=1000&api-version=7.1").value)

function Save-Version($proj, $repo, $path, $commit, $dest) {
  $u = "$Org/$proj/_apis/git/repositories/$repo/items?path=$([uri]::EscapeDataString($path))&versionDescriptor.version=$commit&versionDescriptor.versionType=commit&download=true&api-version=7.1"
  try { $r = Invoke-WebRequest -Uri $u -Headers $script:H -UseBasicParsing } catch { return $false }
  $b = if ($r.Content -is [string]) { [Text.Encoding]::UTF8.GetBytes($r.Content) } else { $r.Content }
  Write-Utf8 $dest ((ConvertTo-Texto $b) -replace "`r`n", "`n")
  return $true
}

# --- 4. Por caso: PR activos (se descargan), completados y abandonados (solo se listan) ---
$casos = @(); $archivosPorPR = @()
foreach ($f in $filas) {
  $num = Get-NumTT $f.ID; $tt = "TT$num"
  $mios = @($prs | Where-Object { (Get-NumTT ($_.sourceRefName + ' ')) -eq $num -or (Get-NumTT $_.title) -eq $num })
  $infTT = @($informes | Where-Object { (Get-NumTT $_.Name) -eq $num } | Sort-Object Name -Descending | ForEach-Object FullName)
  $c = [ordered]@{
    id = $tt; descripcion = $f.'Descripción'; responsable = $f.Responsable; tester = $f.Tester
    complejidad = $f.Complejidad; acuerdos = $f.Acuerdos; modulos = $f.Modulos
    nota = @($notaLineas | Where-Object { $_ -match "TT0*$num(?!\d)" })
    nivel = Get-Nivel $num
    informes = $infTT; prs = @(); completados = @(); abandonados = @()
  }
  foreach ($pr in $mios) {
    $resumen = [ordered]@{ id = $pr.pullRequestId; repo = $pr.repository.name; proyecto = $pr.repository.project.name; titulo = $pr.title; destino = $pr.targetRefName -replace 'refs/heads/', '' }
    if ($pr.status -eq 'completed') { $c.completados += $resumen; continue }
    if ($pr.status -eq 'abandoned') { $c.abandonados += $resumen; continue }
    $proj = $pr.repository.project.id; $repo = $pr.repository.id; $id = $pr.pullRequestId
    $base = "$Org/$proj/_apis/git/repositories/$repo/pullRequests/$id"
    $it = @((Invoke-Ado "$base/iterations?api-version=7.1").value)[-1]
    $bc = $it.commonRefCommit.commitId; $hc = $it.sourceRefCommit.commitId
    $ch = @((Invoke-Ado "$base/iterations/$($it.id)/changes?`$top=2000&api-version=7.1").changeEntries)
    $commits = @((Invoke-Ado "$base/commits?api-version=7.1").value)
    $hilos = @((Invoke-Ado "$base/threads?api-version=7.1").value)
    $raiz = Join-Path $Salida "prs\$tt\PR$id"
    $url = "$Org/$([uri]::EscapeDataString($pr.repository.project.name))/_git/$([uri]::EscapeDataString($pr.repository.name))/pullrequest/$id"
    $info = @("# PR $id - $($pr.title)", "Repo: $($pr.repository.project.name)/$($pr.repository.name)",
      "Rama: $($pr.sourceRefName -replace 'refs/heads/','') -> $($resumen.destino)", "Autor: $($pr.createdBy.displayName)  Creado: $($pr.creationDate)",
      "Base (merge-base): $bc", "Head: $hc", "URL: $url", '', '## Descripción', $pr.description, '', '## Commits') +
      @($commits | ForEach-Object { "- $($_.commitId.Substring(0,8)) $($_.author.name): $($_.comment -replace '\s+',' ')" }) +
      @('', '## Comentarios existentes') +
      @($hilos | ForEach-Object { $_.comments } | Where-Object { $_.commentType -eq 'text' } | ForEach-Object { "- $($_.author.displayName): $($_.content)" }) +
      @('', '## Archivos')
    $diffs = @()
    foreach ($e in $ch) {
      $p = $e.item.path; $tipo = "$($e.changeType)"
      if ($e.item.isFolder) { continue }
      $info += "- [$tipo] $p"
      $rel = $p.TrimStart('/') -replace '/', '\'
      $fb = Join-Path $raiz "base\$rel"; $fh = Join-Path $raiz "head\$rel"
      $hayB = ($tipo -notmatch 'add') -and (Save-Version $proj $repo $p $bc $fb)
      $hayH = ($tipo -notmatch 'delete') -and (Save-Version $proj $repo $p $hc $fh)
      $relU = $p.TrimStart('/')
      $a = if ($hayB) { "base/$relU" } else { '/dev/null' }; $b = if ($hayH) { "head/$relU" } else { '/dev/null' }
      $diffs += ((Invoke-Git -C $raiz diff --no-index --no-color -U8 -- $a $b) -join "`n")
      $archivosPorPR += [pscustomobject]@{ tt = $tt; pr = $id; clave = "$($pr.repository.name)|$p"; base = $(if ($hayB) { $fb }); head = $(if ($hayH) { $fh }) }
    }
    Write-Utf8 (Join-Path $raiz 'pr.md') ($info -join "`n")
    $textoDiff = $diffs -join "`n"
    Write-Utf8 (Join-Path $raiz 'diff.patch') $textoDiff
    $resumen.autor = $pr.createdBy.displayName; $resumen.url = $url; $resumen.ruta = $raiz
    $resumen.archivos = $ch.Count; $resumen.lineasDiff = ($textoDiff -split "`n").Count
    $resumen.sinDescripcion = [string]::IsNullOrWhiteSpace($pr.description) -or $pr.title -match '^\s*TT\d+\s*$'
    $c.prs += $resumen
  }
  $casos += $c
}

# --- 5. Archivos que tocan varios casos: merge de prueba cuando comparten la misma base ---
$cruces = @()
foreach ($g in ($archivosPorPR | Group-Object clave | Where-Object { @($_.Group.tt | Select-Object -Unique).Count -gt 1 })) {
  $l = @($g.Group)
  for ($i = 0; $i -lt $l.Count; $i++) { for ($j = $i + 1; $j -lt $l.Count; $j++) {
    $x = $l[$i]; $y = $l[$j]; if ($x.tt -eq $y.tt) { continue }
    $res = 'sin base común (revisar a mano)'
    if ($x.base -and $y.base -and $x.head -and $y.head -and ((Get-FileHash $x.base).Hash -eq (Get-FileHash $y.base).Hash)) {
      $m = Invoke-Git merge-file -p $x.head $x.base $y.head
      $n = @($m | Where-Object { $_ -match '^<{7}' }).Count
      $res = if ($n) { "CONFLICTO en $n bloque(s)" } else { 'se integra sin conflicto' }
    }
    $cruces += [ordered]@{ archivo = $g.Name; a = "$($x.tt) PR$($x.pr)"; b = "$($y.tt) PR$($y.pr)"; resultado = $res }
  } }
}

# --- 6. PR activos que parecen de la versión pero no están en el Excel ---
$nums = @($casos | ForEach-Object { Get-NumTT $_.id })
$minFecha = @($casos.prs | ForEach-Object { $p = $_; ($prs | Where-Object pullRequestId -eq $p.id).creationDate } | Sort-Object)[0]
$ajenos = @($prs | Where-Object { $_.status -eq 'active' -and $minFecha -and ([datetime]$_.creationDate) -ge ([datetime]$minFecha).AddDays(-3) } |
  Where-Object { $n = Get-NumTT ($_.sourceRefName + ' ' + $_.title); $n -and $nums -notcontains $n } |
  ForEach-Object { [ordered]@{ id = $_.pullRequestId; repo = $_.repository.name; titulo = $_.title; autor = $_.createdBy.displayName } })

$datos = [ordered]@{ version = $version; carpeta = $Carpeta; salida = $Salida; casos = $casos; cruces = $cruces; ajenos = $ajenos }
Write-Utf8 (Join-Path $Salida 'casos.json') ($datos | ConvertTo-Json -Depth 8)

# --- 7. Digest ---
$o = @("# Digest /mtto-revpr — versión $version", '', '| TT | Responsable → Tester | Compl. | Nivel nota | PR activos (archivos / líneas de diff) | Informe |', '|---|---|---|---|---|---|')
foreach ($c in $casos) {
  $nivel = $c.nivel
  $p = if ($c.prs) { ($c.prs | ForEach-Object { "$($_.id) $($_.repo) ($($_.archivos)/$($_.lineasDiff))" }) -join '; ' } else { 'NINGUNO' }
  $o += "| $($c.id) | $($c.responsable) → $($c.tester) | $($c.complejidad) | $nivel | $p | $(if ($c.informes) { 'sí' } else { 'NO' }) |"
}
$o += '', '## Avisos'
foreach ($c in $casos) {
  foreach ($x in $c.completados) { $o += "- $($c.id): PR $($x.id) ($($x.repo)) ya está completado; no se revisa." }
  foreach ($x in $c.abandonados) { $o += "- $($c.id): PR $($x.id) ($($x.repo)) está abandonado." }
  if (-not $c.prs -and -not $c.completados) { $o += "- $($c.id): sin PR en ningún estado." }
  foreach ($x in $c.prs) {
    if ($x.destino -ne 'main') { $o += "- $($c.id): PR $($x.id) apunta a '$($x.destino)', no a main." }
    if ($x.sinDescripcion) { $o += "- $($c.id): PR $($x.id) sin título descriptivo ni descripción." }
    if ($x.lineasDiff -gt 3000) { $o += "- $($c.id): PR $($x.id) tiene $($x.lineasDiff) líneas de diff (¿.dfm re-guardado por el IDE?)." }
  }
  if (-not $c.informes) { $o += "- $($c.id): sin informe interno en los comprimidos." }
}
foreach ($x in $ajenos) { $o += "- PR $($x.id) ($($x.repo), $($x.autor)) está activo y no está en el Excel: $($x.titulo)" }
if (-not $notaLineas) { $o += "- No existe Atencion_Especial_$version.md; no hay H1/H2 que seguir." }
$o += '', '## Archivos compartidos entre casos'
$o += if ($cruces) { $cruces | ForEach-Object { "- $($_.archivo): $($_.a) × $($_.b) → $($_.resultado)" } } else { '- Ninguno.' }
Write-Utf8 (Join-Path $Salida 'digest.md') ($o -join "`n")
$o -join "`n"
