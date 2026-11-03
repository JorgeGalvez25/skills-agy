# /mtto-revpr seguimiento: PR activos de un TT ya revisado → cambios desde lo revisado e integración con el destino actual
param(
  [Parameter(Mandatory)][string]$Carpeta,
  [Parameter(Mandatory)][string]$TT,
  [Parameter(Mandatory)][string]$Salida
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
$script:H = Get-Headers
$num = Get-NumTT $TT; if (-not $num) { throw "TT inválido: $TT" }
$TT = "TT$num"
$dirTT = Join-Path $Salida $TT
if (Test-Path $dirTT) { cmd /c rd /s /q "\\?\$dirTT" }

# Lo ya revisado: columna Head de la tabla de PR del informe o, si no la tiene, la última iteración anterior a la fecha más
# reciente de revisión o seguimiento del informe
$informe = Join-Path $Carpeta "Revision_PR\$TT.md"
$txtInf = if (Test-Path $informe) { @(Get-Content $informe -Encoding UTF8) } else { @() }
$fechaRev = @($txtInf | Where-Object { $_ -match 'Fecha de revisión|Seguimiento' } |
  ForEach-Object { [regex]::Matches($_, '\b\d{2}/\d{2}/\d{4}\b') | ForEach-Object { [datetime]::ParseExact($_.Value, 'dd/MM/yyyy', $null) } } | Sort-Object)[-1]

$prs = @((Invoke-Ado "$Org/_apis/git/pullrequests?searchCriteria.status=active&`$top=1000&api-version=7.1").value |
  Where-Object { (Get-NumTT ($_.sourceRefName + ' ')) -eq $num -or (Get-NumTT $_.title) -eq $num })
$o = @("# Seguimiento /mtto-revpr — $TT", '')
if (-not $txtInf) { $o += "- No existe $informe; es una primera revisión, no un seguimiento." }
if (-not $prs) { $o += '- No hay PR activos de este TT.' }

foreach ($pr in $prs) {
  $proj = $pr.repository.project.id; $repo = $pr.repository.id; $id = $pr.pullRequestId
  $rep = "$Org/$proj/_apis/git/repositories/$repo"; $base = "$rep/pullRequests/$id"
  $dir = Join-Path $dirTT "PR$id"
  $its = @((Invoke-Ado "$base/iterations?api-version=7.1").value)
  $ult = $its[-1]; $hc = $ult.sourceRefCommit.commitId

  $prev = $null; $fila = @($txtInf | Where-Object { $_ -match "^\|\s*$id\s*\|.*``([0-9a-f]{7,40})``" })[0]
  if ($fila -and $fila -match '`([0-9a-f]{7,40})`') { $c8 = $Matches[1]; $prev = @($its | Where-Object { $_.sourceRefCommit.commitId.StartsWith($c8) })[0] }
  $origen = 'columna Head del informe'
  if (-not $prev -and $fechaRev) { $prev = @($its | Where-Object { ([datetime]$_.createdDate).Date -le $fechaRev })[-1]; $origen = "fecha del informe ($($fechaRev.ToString('dd/MM/yyyy')))" }
  if (-not $prev -and $its.Count -gt 1) { $prev = $its[-2]; $origen = 'iteración anterior (sin datos en el informe)' }

  $todos = @((Invoke-Ado "$base/iterations/$($ult.id)/changes?`$top=2000&api-version=7.1").changeEntries | Where-Object { -not $_.item.isFolder })
  $nuevos = @()
  if ($prev -and $prev.id -ne $ult.id) {
    $nuevos = @((Invoke-Ado "$base/iterations/$($ult.id)/changes?`$compareTo=$($prev.id)&`$top=2000&api-version=7.1").changeEntries | Where-Object { -not $_.item.isFolder })
  }

  # Destino actual y base común con él (la del PR puede haber quedado atrás si el destino avanzó)
  $mc = @((Invoke-Ado "$rep/refs?filter=heads/$($pr.targetRefName -replace '^refs/heads/','')&api-version=7.1").value | Where-Object name -eq $pr.targetRefName)[0].objectId
  $mb = @((Invoke-Ado "$rep/commits/$hc/mergebases?otherCommitId=$mc&api-version=7.1-preview.1").value)[0].commitId
  $fechaMb = (Invoke-Ado "$rep/commits/$mb`?api-version=7.1").committer.date

  $url = "$Org/$([uri]::EscapeDataString($pr.repository.project.name))/_git/$([uri]::EscapeDataString($pr.repository.name))/pullrequest/$id"
  $destino = $pr.targetRefName -replace 'refs/heads/', ''
  $o += "## PR $id — $($pr.title)", "- Repo: $($pr.repository.project.name)/$($pr.repository.name) · $url",
    "- Estado de integración en Azure: $($pr.mergeStatus)",
    "- Iteraciones: $(($its | ForEach-Object { "$($_.id) ``$($_.sourceRefCommit.commitId.Substring(0,8))`` $(([datetime]$_.createdDate).ToString('dd/MM'))" }) -join ' · ')",
    "- Ya revisado: $(if ($prev) { "iteración $($prev.id) ``$($prev.sourceRefCommit.commitId.Substring(0,8))`` (según $origen)" } else { 'no se pudo determinar' })",
    "- Head actual: iteración $($ult.id) ``$($hc.Substring(0,8))``",
    "- $destino actual: ``$($mc.Substring(0,8))`` · base común con la rama: ``$($mb.Substring(0,8))``"

  $commits = @((Invoke-Ado "$base/commits?api-version=7.1").value)
  if ($prev -and $prev.id -ne $ult.id) {
    $o += '', '### Commits nuevos'
    foreach ($c in $commits) { if ($c.commitId -eq $prev.sourceRefCommit.commitId) { break }; $o += "- ``$($c.commitId.Substring(0,8))`` $(([datetime]$c.author.date).ToString('dd/MM')) $($c.author.name): $($c.comment -replace '\s+',' ')" }
    $o += '', '### Archivos que cambiaron desde lo revisado (iteracion.patch)'
    $diffs = @()
    foreach ($e in $nuevos) {
      $p = $e.item.path; $rel = $p.TrimStart('/'); $relW = $rel -replace '/', '\'; $tipo = "$($e.changeType)"
      $hayP = ($tipo -notmatch 'add') -and (Save-Version $proj $repo $p $prev.sourceRefCommit.commitId (Join-Path $dir "previo\$relW"))
      $hayH = ($tipo -notmatch 'delete') -and (Save-Version $proj $repo $p $hc (Join-Path $dir "head\$relW"))
      $a = if ($hayP) { "previo/$rel" } else { '/dev/null' }; $b = if ($hayH) { "head/$rel" } else { '/dev/null' }
      $diffs += ((Invoke-Git -C $dir diff --no-index --no-color -U8 -- $a $b) -join "`n")
      $o += "- [$tipo] $p"
    }
    Write-Utf8 (Join-Path $dir 'iteracion.patch') ($diffs -join "`n")
  } elseif ($prev) { $o += '', '- **Sin iteraciones nuevas** desde lo revisado.' }

  # Archivos del PR completos en base común, head y destino, más la integración de prueba contra el destino
  $o += '', "### Integración con $destino actual"
  $diffs = @(); $hayCambios = $false
  foreach ($e in $todos) {
    $p = $e.item.path; $rel = $p.TrimStart('/'); $relW = $rel -replace '/', '\'; $tipo = "$($e.changeType)"
    $fb = Join-Path $dir "base\$relW"; $fh = Join-Path $dir "head\$relW"; $fm = Join-Path $dir "destino\$relW"
    $hayB = Save-Version $proj $repo $p $mb $fb
    $hayH = ($tipo -notmatch 'delete') -and ((Test-Path $fh) -or (Save-Version $proj $repo $p $hc $fh))
    $hayM = Save-Version $proj $repo $p $mc $fm
    $a = if ($hayB) { "base/$rel" } else { '/dev/null' }; $b = if ($hayH) { "head/$rel" } else { '/dev/null' }
    $diffs += ((Invoke-Git -C $dir diff --no-index --no-color -U8 -- $a $b) -join "`n")
    if (-not ($hayB -and $hayH -and $hayM) -or (Get-FileHash $fb).Hash -eq (Get-FileHash $fm).Hash) { continue }
    $hayCambios = $true
    $m = Invoke-Git merge-file -p $fh $fb $fm
    $n = @($m | Where-Object { $_ -match '^<{7}' }).Count
    if ($n) { Write-Utf8 (Join-Path $dir "integracion\$relW") ($m -join "`n") }
    $hist = @((Invoke-Ado "$rep/commits?searchCriteria.itemPath=$([uri]::EscapeDataString($p))&searchCriteria.itemVersion.version=$mc&searchCriteria.itemVersion.versionType=commit&searchCriteria.fromDate=$([uri]::EscapeDataString($fechaMb))&searchCriteria.`$top=20&api-version=7.1").value |
      Where-Object { $_.commitId -ne $mb } | ForEach-Object { "``$($_.commitId.Substring(0,8))`` $($_.author.name): $($_.comment -replace '\s+',' ')" })
    $o += "- $p → $(if ($n) { "**CONFLICTO en $n bloque(s)** (integracion\$relW)" } else { 'se integra sin conflicto' }). Commits de $destino en el archivo: $(if ($hist) { $hist -join '; ' } else { '—' })"
  }
  if (-not $hayCambios) { $o += "- $destino no ha modificado los archivos del PR desde la base común." }
  Write-Utf8 (Join-Path $dir 'diff.patch') ($diffs -join "`n")

  # Hilos del PR: los del revisor y las respuestas del desarrollador
  $o += '', '### Hilos de comentarios'
  $hilos = @((Invoke-Ado "$base/threads?api-version=7.1").value | Where-Object { @($_.comments | Where-Object commentType -eq 'text').Count })
  if (-not $hilos) { $o += '- Ninguno.' }
  foreach ($t in $hilos) {
    $cs = @($t.comments | Where-Object commentType -eq 'text')
    $donde = if ($t.threadContext) { "$($t.threadContext.filePath) $($t.threadContext.rightFileStart.line)" } else { 'general' }
    $o += "- Hilo $($t.id) [$($t.status)] $donde — $($cs[0].author.displayName): $(($cs[0].content -replace '\s+',' ').Substring(0, [Math]::Min(120, ($cs[0].content -replace '\s+',' ').Length)))"
    foreach ($r in ($cs | Select-Object -Skip 1)) { $o += "  - Respuesta de $($r.author.displayName): $($r.content -replace '\s+',' ')" }
  }
  $o += ''
}
Write-Utf8 (Join-Path $dirTT 'seguimiento.md') ($o -join "`n")
$o -join "`n"
