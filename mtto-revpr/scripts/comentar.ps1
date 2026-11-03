# /mtto-revpr: comentarios de un PR desde comentarios_PR####.md. Sin -Publicar solo valida y muestra las líneas ancladas;
# con -Publicar crea los hilos en Azure DevOps (solo después de que Jorge aprobó los textos en el chat)
param(
  [Parameter(Mandatory)][string]$Archivo,
  [Parameter(Mandatory)][int]$PR,
  [switch]$Publicar
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
$script:H = Get-Headers
$infoPR = Invoke-Ado "$Org/_apis/git/pullrequests/$PR`?api-version=7.1"
$proj = $infoPR.repository.project.id; $repo = $infoPR.repository.id
$base = "$Org/$proj/_apis/git/repositories/$repo/pullRequests/$PR"

# Secciones: "## /ruta/Unidad.pas 512", "## /ruta/Unidad.pas 584-587" (líneas del head de la última iteración) o "## General"
$lista = @(); $act = $null; $enCodigo = $false
foreach ($l in Get-Content $Archivo -Encoding UTF8) {
  if ($l -match '^\s*```') { $enCodigo = -not $enCodigo }
  if (-not $enCodigo -and $l -match '^##\s+(.+?)\s*$') {
    $t = $Matches[1]
    if ($t -match '^(?<ruta>/.+?)\s+(?<ini>\d+)(?:\s*[-–]\s*(?<fin>\d+))?$') {
      $fin = if ($Matches.fin) { [int]$Matches.fin } else { [int]$Matches.ini }
      $act = [pscustomobject]@{ ruta = $Matches.ruta; ini = [int]$Matches.ini; fin = $fin; texto = '' }
    } elseif ($t -match '^(?i)general$') { $act = [pscustomobject]@{ ruta = $null; ini = 0; fin = 0; texto = '' } }
    else { throw "Encabezado no válido: '$l'. Usa '## /ruta/archivo línea', '## /ruta/archivo ini-fin' o '## General'." }
    $lista += $act; continue
  }
  if ($act) { $act.texto += $l + "`n" }
}
foreach ($c in $lista) { $c.texto = $c.texto.Trim() }
if (-not $lista) { throw "No hay comentarios en $Archivo." }

$ult = @((Invoke-Ado "$base/iterations?api-version=7.1").value)[-1]
$rutas = @((Invoke-Ado "$base/iterations/$($ult.id)/changes?`$top=2000&api-version=7.1").changeEntries | ForEach-Object { $_.item.path })
$previos = @((Invoke-Ado "$base/threads?api-version=7.1").value | ForEach-Object { $_.comments } | ForEach-Object { "$($_.content)".Trim() })

"PR $PR — $($infoPR.title) · iteración $($ult.id) ``$($ult.sourceRefCommit.commitId.Substring(0,8))``"
foreach ($c in $lista) {
  $c | Add-Member duplicado ($previos -contains $c.texto)
  if (-not $c.ruta) { "`n[General] $(if ($c.duplicado) { '(YA PUBLICADO)' })"; continue }
  if ($rutas -notcontains $c.ruta) { throw "$($c.ruta) no está entre los archivos del PR." }
  $u = "$Org/$proj/_apis/git/repositories/$repo/items?path=$([uri]::EscapeDataString($c.ruta))&versionDescriptor.version=$($ult.sourceRefCommit.commitId)&versionDescriptor.versionType=commit&download=true&api-version=7.1"
  $r = Invoke-WebRequest -Uri $u -Headers $script:H -UseBasicParsing
  $b = if ($r.Content -is [string]) { [Text.Encoding]::UTF8.GetBytes($r.Content) } else { $r.Content }
  $lineas = (ConvertTo-Texto $b) -split "`r?`n"
  if ($c.fin -gt $lineas.Count -or $c.ini -gt $c.fin) { throw "$($c.ruta): líneas $($c.ini)-$($c.fin) fuera del archivo ($($lineas.Count) líneas)." }
  "`n[$($c.ruta) $($c.ini)$(if ($c.fin -ne $c.ini) { "-$($c.fin)" })] $(if ($c.duplicado) { '(YA PUBLICADO)' })"
  for ($i = $c.ini; $i -le [Math]::Min($c.fin, $c.ini + 4); $i++) { "  $i | $($lineas[$i - 1])" }
}
if (-not $Publicar) { "`nVista previa: no se publicó nada."; return }

foreach ($c in $lista) {
  if ($c.duplicado) { "OMITIDO (ya existe) $($c.ruta) $($c.ini)"; continue }
  $cuerpo = @{ comments = @(@{ parentCommentId = 0; content = $c.texto; commentType = 1 }); status = 1 }
  if ($c.ruta) { $cuerpo.threadContext = @{ filePath = $c.ruta; rightFileStart = @{ line = $c.ini; offset = 1 }; rightFileEnd = @{ line = $c.fin; offset = 1 } } }
  $json = $cuerpo | ConvertTo-Json -Depth 6
  try { $t = Invoke-RestMethod -Method Post -Uri "$base/threads?api-version=7.1" -Headers $script:H -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) }
  catch {
    $s = $_.Exception.Response.StatusCode.value__
    if ($s -in 401, 403, 203) { throw 'TOKEN_SIN_ESCRITURA: el token no tiene permiso Code: Read & write.' }
    throw
  }
  "OK hilo $($t.id) $(if ($c.ruta) { "$($c.ruta) $($c.ini)" } else { 'general' })"
}
