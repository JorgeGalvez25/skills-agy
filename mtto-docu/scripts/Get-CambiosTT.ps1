<#
.SYNOPSIS
  Recolecta desde Git todos los cambios de un ticket (TT#####) y genera un paquete
  de análisis (resumen.json, resumen.md y los diffs) para documentar la corrección/cambio.

.DESCRIPTION
  - Busca la rama del ticket (local o remota: TT#####, TT#####_algo) en el repo indicado
    y en los repos hermanos de la misma carpeta (un ticket suele tocar varios repos).
  - Si la rama ya se integró/borró, busca los commits cuyo mensaje contiene el ticket.
  - Mapea cada unidad Delphi modificada a los proyectos (.dpr) que la compilan.
  - Detecta indicios de cambios en base de datos (campos persistentes nuevos en .dfm,
    DDL/DML en código, scripts .sql, constantes de versión de BD).
  - Detecta código pendiente de versionar (cambios sin commit, archivos sin rastrear,
    commits sin push o rama sin publicar) en los repos del ticket.
  - Lista otros TT mencionados en los commits (posible ticket origen de soporte).
  - No modifica nada en los repositorios (solo lectura; opcionalmente hace git fetch).

.EXAMPLE
  .\Get-CambiosTT.ps1 -Rutas "C:\Rama Azure" -Ticket TT100075
.EXAMPLE
  .\Get-CambiosTT.ps1 -Rutas "C:\Rama Azure\Imagen Ib Gas"      # toma el TT de la rama actual
.EXAMPLE
  .\Get-CambiosTT.ps1 -Rutas "C:\Rama Azure\Imagen Ib Gas" -Rama "feature/TT96079"
#>
[CmdletBinding()]
param(
  [string[]]$Rutas = @('C:\Rama Azure'),
  [string]$Ticket,
  [string]$Rama,       # nombre exacto de la rama (local o remota); si se omite, se busca por el patrón TT#####
  [string]$RamaBase = 'origin/main',
  [string]$Salida,
  [switch]$SinFetch,
  [switch]$SoloRutas   # no buscar en repos hermanos
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

function Invoke-Git {
  param([string]$Repo, [string[]]$Arguments)
  $out = & git -C $Repo -c core.quotepath=off -c i18n.logOutputEncoding=UTF-8 @Arguments 2>$null
  $script:GitExit = $LASTEXITCODE
  if ($null -eq $out) { return @() }
  return @($out)
}

# Lee bytes y los decodifica como UTF-8; si no es UTF-8 válido usa Windows-1252 (fuentes Delphi).
function Read-TextSmart {
  param([byte[]]$Bytes)
  try {
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    return $utf8.GetString($Bytes)
  } catch {
    return [Text.Encoding]::GetEncoding(1252).GetString($Bytes)
  }
}

function Convert-FileToUtf8 {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return }
  $txt = Read-TextSmart ([IO.File]::ReadAllBytes($Path))
  [IO.File]::WriteAllText($Path, $txt, (New-Object System.Text.UTF8Encoding($true)))
}

function Get-GitFileText {
  param([string]$Repo, [string]$Ref, [string]$Path)
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath git -ArgumentList @('-C', "`"$Repo`"", 'show', "`"$($Ref):$Path`"") `
          -RedirectStandardOutput $tmp -NoNewWindow -Wait -PassThru -RedirectStandardError ([IO.Path]::GetTempFileName())
    if ($p.ExitCode -ne 0) { return $null }
    return Read-TextSmart ([IO.File]::ReadAllBytes($tmp))
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

function Test-GitRepo { param([string]$Dir) return (Test-Path (Join-Path $Dir '.git')) }

# ---------------------------------------------------------------- 1. Repositorios
$repos = New-Object System.Collections.Generic.List[string]
$raices = New-Object System.Collections.Generic.List[string]
$explicitos = New-Object System.Collections.Generic.List[string]   # repos indicados directamente en -Rutas
foreach ($r in $Rutas) {
  if (-not (Test-Path $r)) { Write-Warning "La ruta no existe: $r"; continue }
  $full = (Resolve-Path $r).Path.TrimEnd('\')
  if (Test-GitRepo $full) {
    $repos.Add($full); $explicitos.Add($full)
    $parent = Split-Path $full -Parent
    if (-not $SoloRutas -and $parent) { $raices.Add($parent) }
  } else {
    $raices.Add($full)
  }
}
foreach ($raiz in ($raices | Select-Object -Unique)) {
  Get-ChildItem $raiz -Directory -ErrorAction SilentlyContinue | Where-Object { Test-GitRepo $_.FullName } |
    ForEach-Object { $repos.Add($_.FullName) }
}
$repos = @($repos | Select-Object -Unique)
if ($repos.Count -eq 0) { throw "No se encontraron repositorios Git en: $($Rutas -join ', ')" }

# ---------------------------------------------------------------- 2. Ticket
if (-not $Ticket -and $Rama -match '(TT\d+)') { $Ticket = $Matches[1] }
if (-not $Ticket) {
  foreach ($r in $repos) {
    $b = (Invoke-Git $r @('branch', '--show-current')) | Select-Object -First 1
    if ($b -match '(TT\d+)') { $Ticket = $Matches[1]; break }
  }
}
if (-not $Ticket) { throw "No se indicó -Ticket y la rama actual no contiene un TT#####." }
$Ticket = $Ticket.ToUpper()
if ($Ticket -notmatch '^TT\d+$') { $Ticket = 'TT' + ($Ticket -replace '\D', '') }

if (-not $Salida) { $Salida = Join-Path $env:TEMP "InformesTT\$Ticket" }
New-Item -ItemType Directory -Force -Path $Salida | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Salida 'diffs') | Out-Null

Write-Host "Ticket: $Ticket   Repos a revisar: $($repos.Count)   Salida: $Salida"

# ---------------------------------------------------------------- 3. Índice de proyectos .dpr / .csproj (todos los repos)
$unitToDpr = @{}      # UNIDAD -> lista de "Repo|ruta.dpr"
$dprInfo   = @{}      # "Repo|ruta.dpr" -> objeto
$csprojs   = @{}      # repo -> lista de rutas .csproj
foreach ($r in $repos) {
  $repoName = Split-Path $r -Leaf
  foreach ($dpr in (Invoke-Git $r @('ls-files', '*.dpr', '*.DPR'))) {
    $key = "$repoName|$dpr"
    $disk = Join-Path $r $dpr
    $dprInfo[$key] = [pscustomobject]@{ Repo = $repoName; RepoPath = $r; Ruta = $dpr; Modulo = [IO.Path]::GetFileNameWithoutExtension($dpr).ToUpper() }
    if (Test-Path $disk) {
      foreach ($line in (Get-Content $disk -Encoding Default -ErrorAction SilentlyContinue)) {
        if ($line -match "^\s*(\w+)\s+in\s+'") {
          $u = $Matches[1].ToUpper()
          if (-not $unitToDpr.ContainsKey($u)) { $unitToDpr[$u] = New-Object System.Collections.Generic.List[string] }
          $unitToDpr[$u].Add($key)
        }
      }
    }
  }
  $csprojs[$r] = @(Invoke-Git $r @('ls-files', '*.csproj'))
}

$usersCache = @{}
function Get-UnitUsers {
  param([string]$Unit)
  if ($usersCache.ContainsKey($Unit)) { return $usersCache[$Unit] }
  $res = @()
  foreach ($rr in $repos) {
    $res += @(Invoke-Git $rr @('grep', '-l', '-i', '-w', $Unit, '--', '*.pas', '*.dpr') |
      Where-Object { [IO.Path]::GetFileNameWithoutExtension($_).ToUpper() -ne $Unit } | ForEach-Object { "$(Split-Path $rr -Leaf)/$_" })
  }
  $usersCache[$Unit] = $res
  return $res
}

function Get-DofVersion {
  param($Info, [string]$RefEnRepo)
  $dof = [IO.Path]::ChangeExtension($Info.Ruta, '.dof')
  $txt = $null
  if ($RefEnRepo) { $txt = Get-GitFileText $Info.RepoPath $RefEnRepo $dof }
  if (-not $txt) {
    $disk = Join-Path $Info.RepoPath $dof
    if (Test-Path $disk) { $txt = [IO.File]::ReadAllText($disk, [Text.Encoding]::GetEncoding(1252)) }
  }
  if ($txt -and $txt -match '(?m)^FileVersion=([\d\.]+)') { return $Matches[1] }
  return $null
}

# ---------------------------------------------------------------- 4. Recolección por repo
if (-not $SinFetch) {
  foreach ($r in $repos) { Invoke-Git $r @('fetch', '--prune', '--quiet', 'origin') | Out-Null }
}

$reDDL = '(?i)\b(ALTER\s+TABLE|CREATE\s+(OR\s+ALTER\s+)?(TABLE|PROCEDURE|TRIGGER|VIEW|GENERATOR|SEQUENCE|INDEX|DOMAIN|EXCEPTION)|RECREATE\s+(TABLE|PROCEDURE|VIEW)|DROP\s+(TABLE|PROCEDURE|TRIGGER|VIEW|INDEX|GENERATOR)|ADD\s+\w+\s+(VARCHAR|INTEGER|SMALLINT|BIGINT|NUMERIC|DECIMAL|DATE|TIMESTAMP|CHAR|BLOB|DOUBLE|FLOAT)|SET\s+GENERATOR|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|EXECUTE\s+PROCEDURE)\b'
$reTabla = '(?i)\b(?:FROM|JOIN|INTO|UPDATE|TABLE)\s+([A-Z_][A-Z0-9_]{3,})\b'
$reField = '^\+\s*object\s+(\w+)\s*:\s*T(\w*)Field\b'
$reVersionConst = "(?i)\b(Version\w*)\s*[:=]+\s*'([\d\.]+)'"

$resultado = [ordered]@{
  ticket       = $Ticket
  generado     = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  ramaBase     = $RamaBase
  repos        = @()
  archivos     = @()
  commits      = @()
  autores      = @()
  modulos      = @()
  bd           = [ordered]@{ camposPersistentesNuevos = @(); sentenciasSQL = @(); tablasReferenciadas = @(); scriptsSQL = @(); constantesVersion = @() }
  configuracion= @()
  pendientes   = @()   # código pendiente de versionar, por repo
  ticketsRelacionados = @()   # otros TT mencionados en los commits
  advertencias = @()
}
$sinPush = @{}   # repo -> @{ rama; remota; commits; publicada }

foreach ($r in $repos) {
  $repoName = Split-Path $r -Leaf
  # Se clasifica por espacio de nombres (refs/heads vs refs/remotes), no por si el nombre trae '/':
  # una rama local "feature/TT96079" también tiene '/'.
  $refs = Invoke-Git $r @('for-each-ref', '--format=%(refname)', 'refs/heads', 'refs/remotes')
  $locTodas = @($refs | Where-Object { $_ -like 'refs/heads/*' } | ForEach-Object { $_.Substring(11) })
  $remTodas = @($refs | Where-Object { $_ -like 'refs/remotes/*' -and $_ -notmatch '/HEAD$' } | ForEach-Object { $_.Substring(13) })
  if ($Rama) {
    $locales = @($locTodas | Where-Object { $_ -eq $Rama })
    $remotas = @($remTodas | Where-Object { $_ -eq $Rama -or $_ -match ('^[^/]+/' + [regex]::Escape($Rama) + '$') })
  } else {
    $pat = "(^|/)$Ticket([_\-\.][^/]*)?$"
    $locales = @($locTodas | Where-Object { $_ -match $pat })
    $remotas = @($remTodas | Where-Object { $_ -match $pat })
  }
  if ($locales.Count -gt 0) {
    # Primero la remota que corresponde a la local elegida.
    $remotas = @($remotas | Sort-Object { if ($_ -match ('^[^/]+/' + [regex]::Escape($locales[0]) + '$')) { 0 } else { 1 } })
  }

  $base = $RamaBase
  Invoke-Git $r @('rev-parse', '--verify', '--quiet', $base) | Out-Null
  if ($script:GitExit -ne 0) {
    $base = $null
    foreach ($c in 'origin/main', 'main', 'origin/master', 'master') {
      Invoke-Git $r @('rev-parse', '--verify', '--quiet', $c) | Out-Null
      if ($script:GitExit -eq 0) { $base = $c; break }
    }
  }
  if (-not $base) { continue }

  $rama = $null
  if ($locales.Count -gt 0) { $rama = $locales[0] } elseif ($remotas.Count -gt 0) { $rama = $remotas[0] }
  if ($locales.Count -gt 0 -and $remotas.Count -gt 0) {
    $adelante = [int]((Invoke-Git $r @('rev-list', '--count', "$($remotas[0])..$($locales[0])")) | Select-Object -First 1)
    $atras    = [int]((Invoke-Git $r @('rev-list', '--count', "$($locales[0])..$($remotas[0])")) | Select-Object -First 1)
    if ($adelante -gt 0) { $sinPush[$r] = @{ rama = $locales[0]; remota = $remotas[0]; commits = $adelante; publicada = $true } }
    if ($atras -gt 0) { $resultado.advertencias += "[$repoName] La remota $($remotas[0]) tiene $atras commit(s) que la local $($locales[0]) no tiene (¿falta pull?). Se usó la local." }
  } elseif ($locales.Count -gt 0) {
    $n = [int]((Invoke-Git $r @('rev-list', '--count', "$base..$($locales[0])")) | Select-Object -First 1)
    if ($n -gt 0) { $sinPush[$r] = @{ rama = $locales[0]; remota = $null; commits = $n; publicada = $false } }
  }

  $modo = $null; $hashes = @(); $tip = $null; $mb = $null
  if ($rama) {
    $mb = (Invoke-Git $r @('merge-base', $base, $rama)) | Select-Object -First 1
    $hashes = @(Invoke-Git $r @('rev-list', '--no-merges', '--reverse', "$mb..$rama"))
    if ($hashes.Count -gt 0) { $modo = 'rama'; $tip = $rama }
  }
  if (-not $modo) {
    $hashes = @(Invoke-Git $r @('log', '--all', '--no-merges', '--reverse', '-i', "--grep=$Ticket", '--format=%H') | Select-Object -Unique)
    if ($hashes.Count -gt 0) {
      $modo = 'commits'; $tip = $hashes[-1]
      if ($rama) { $resultado.advertencias += "[$repoName] La rama $rama ya está integrada en $base; se documentan los commits que mencionan $Ticket." }
    }
  }
  if (-not $modo) { continue }

  Write-Host "  [$repoName] modo=$modo rama=$rama commits=$($hashes.Count)"

  # --- commits
  foreach ($h in $hashes) {
    $l = (Invoke-Git $r @('show', '-s', '--format=%h%x1f%an%x1f%ae%x1f%ad%x1f%s', '--date=format:%Y-%m-%d %H:%M', $h)) | Select-Object -First 1
    $p = $l -split [char]0x1f
    $resultado.commits += [pscustomobject]@{ repo = $repoName; hash = $p[0]; autor = $p[1]; email = $p[2]; fecha = $p[3]; mensaje = $p[4] }
  }

  # --- archivos y diff
  $patch = Join-Path $Salida "diffs\$($repoName -replace '[^\w\-]', '_').patch"
  $numstat = @(); $status = @{}
  if ($modo -eq 'rama') {
    $numstat = Invoke-Git $r @('diff', '--numstat', '--no-renames', $mb, $rama)
    foreach ($s in (Invoke-Git $r @('diff', '--name-status', '--no-renames', $mb, $rama))) { $x = $s -split "`t"; $status[$x[1]] = $x[0] }
    Invoke-Git $r @('diff', '-U8', '--no-renames', "--output=$patch", $mb, $rama) | Out-Null
  } else {
    $agg = @{}
    $parts = New-Object System.Collections.Generic.List[byte]
    foreach ($h in $hashes) {
      foreach ($n in (Invoke-Git $r @('show', '--numstat', '--no-renames', '--format=', $h))) {
        $x = $n -split "`t"; if ($x.Count -lt 3) { continue }
        if (-not $agg.ContainsKey($x[2])) { $agg[$x[2]] = @(0, 0) }
        if ($x[0] -ne '-') { $agg[$x[2]][0] += [int]$x[0]; $agg[$x[2]][1] += [int]$x[1] }
      }
      foreach ($s in (Invoke-Git $r @('show', '--name-status', '--no-renames', '--format=', $h))) { $x = $s -split "`t"; if ($x.Count -ge 2 -and -not $status.ContainsKey($x[1])) { $status[$x[1]] = $x[0] } }
      $tmp = [IO.Path]::GetTempFileName()
      Invoke-Git $r @('show', '-U8', '--no-renames', '--format=fuller', "--output=$tmp", $h) | Out-Null
      $parts.AddRange([IO.File]::ReadAllBytes($tmp)); Remove-Item $tmp
    }
    [IO.File]::WriteAllBytes($patch, $parts.ToArray())
    $numstat = $agg.Keys | ForEach-Object { "$($agg[$_][0])`t$($agg[$_][1])`t$_" }
  }
  Convert-FileToUtf8 $patch

  $resultado.repos += [pscustomobject]@{ repo = $repoName; ruta = $r; modo = $modo; rama = $rama; base = $base; mergeBase = $mb; tip = $tip; commits = $hashes.Count; diff = $patch }

  foreach ($n in $numstat) {
    $x = $n -split "`t"; if ($x.Count -lt 3) { continue }
    $file = $x[2]; $ext = [IO.Path]::GetExtension($file).ToLower()
    $unit = [IO.Path]::GetFileNameWithoutExtension($file).ToUpper()
    $mods = @(); $refsUnit = @()
    switch -Regex ($ext) {
      '^\.(pas|dfm|inc)$' {
        if ($unitToDpr.ContainsKey($unit)) { $mods = @($unitToDpr[$unit] | ForEach-Object { $dprInfo[$_].Modulo } | Select-Object -Unique) }
        else {
          $refsUnit = @(Get-UnitUsers $unit)
          # Resolución indirecta: módulos de las unidades que usan a esta (hasta 2 niveles).
          $indirectos = New-Object System.Collections.Generic.List[string]
          $nivel = @($refsUnit | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_).ToUpper() } | Select-Object -Unique)
          for ($d = 0; $d -lt 2 -and $nivel.Count -gt 0 -and $nivel.Count -le 15; $d++) {
            $sig = @()
            foreach ($u2 in $nivel) {
              if ($unitToDpr.ContainsKey($u2)) { $unitToDpr[$u2] | ForEach-Object { $indirectos.Add($dprInfo[$_].Modulo) } }
              elseif ($d -eq 0) { $sig += @(Get-UnitUsers $u2 | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_).ToUpper() }) }
            }
            $nivel = @($sig | Select-Object -Unique)
          }
          $mods = @($indirectos | Select-Object -Unique | ForEach-Object { "$_ (indirecto)" })
        }
      }
      '^\.dpr$' { $mods = @($unit) }
      '^\.(cs|aspx|ascx|asmx|cshtml|resx|config|csproj)$' {
        $dir = ($file -replace '/[^/]*$', '')
        $best = $csprojs[$r] | Where-Object { $dir.StartsWith(($_ -replace '/[^/]*$', '')) } | Sort-Object Length -Descending | Select-Object -First 1
        if ($best) { $mods = @([IO.Path]::GetFileNameWithoutExtension($best)) }
      }
      '^\.(java|kt|xml|gradle)$' { if ($repoName -match 'Tablet|Android') { $mods = @('Tablet Android') } }
    }
    $tipo = switch -Regex ($ext) {
      '^\.pas$' { 'Unidad Delphi' } '^\.dfm$' { 'Formulario/DataModule Delphi' } '^\.dpr$' { 'Proyecto Delphi' }
      '^\.dof$|^\.res$|^\.cfg$' { 'Configuración de proyecto/versión' } '^\.sql$' { 'Script SQL' }
      '^\.(ini|config|json|xml)$' { 'Configuración' } '^\.cs$' { 'Código C#' } default { $ext }
    }
    $resultado.archivos += [pscustomobject]@{
      repo = $repoName; archivo = $file; estado = $status[$file]; tipo = $tipo
      agregadas = $x[0]; eliminadas = $x[1]; modulos = $mods; referenciadaPor = @($refsUnit | Select-Object -First 25)
    }
    foreach ($mRaw in $mods) {
      $m = $mRaw -replace ' \(indirecto\)$', ''
      $key = ($dprInfo.Keys | Where-Object { $dprInfo[$_].Modulo -eq $m } | Sort-Object { if ($dprInfo[$_].Repo -eq $repoName) { 0 } else { 1 } } | Select-Object -First 1)
      if (-not $key -and $ext -eq '.dpr') { $key = "$repoName|$file" }
      $ver = $null; if ($key -and $dprInfo.ContainsKey($key)) { $ref = $null; if ($dprInfo[$key].Repo -eq $repoName) { $ref = $tip }; $ver = Get-DofVersion $dprInfo[$key] $ref }
      $resultado.modulos += [pscustomobject]@{ modulo = $m; indirecto = ($mRaw -ne $m); proyecto = $(if ($key) { $key -replace '\|', '/' } else { '' }); version = $ver; porArchivo = "$repoName/$file" }
    }
    if ($ext -eq '.sql') { $resultado.bd.scriptsSQL += "$repoName/$file" }
    if ($ext -match '^\.(ini|config|json)$' -or ($ext -eq '.xml' -and $repoName -notmatch 'Tablet')) { $resultado.configuracion += "$repoName/$file" }
  }

  # --- heurísticas de BD sobre las líneas agregadas del diff
  $archivoActual = $null; $pendienteCampo = $null
  $dfmCache = @{}
  foreach ($line in [IO.File]::ReadAllLines($patch)) {
    if ($line -match '^\+\+\+ b/(.+)$') { $archivoActual = $Matches[1]; continue }
    if ($line -notmatch '^\+' -or $line -match '^\+\+\+') { continue }
    if ($line -match $reField) {
      $comp = $Matches[1]; $tipoCampo = $Matches[2]
      $tabla = $null; $aliasBD = $null
      if ($archivoActual -match '\.dfm$') {
        if (-not $dfmCache.ContainsKey($archivoActual)) { $dfmCache[$archivoActual] = Get-GitFileText $r $tip $archivoActual }
        $dfm = $dfmCache[$archivoActual]
        if ($dfm) {
          $mejor = $null
          foreach ($mm in [regex]::Matches($dfm, '(?ms)^\s*object\s+(\w+)\s*:\s*T\w*(Table|Query|DataSet|ClientDataSet)\b(.*?)(?=^\s*object\s+\w+\s*:)')) {
            $ds = $mm.Groups[1].Value
            if ($comp.StartsWith($ds, [StringComparison]::OrdinalIgnoreCase) -and ((-not $mejor) -or $ds.Length -gt $mejor.ds.Length)) {
              $tn = $null; if ($mm.Groups[3].Value -match "TableName\s*=\s*'([^']+)'") { $tn = $Matches[1] }
              $dbn = $null; if ($mm.Groups[3].Value -match "DatabaseName\s*=\s*'([^']+)'") { $dbn = $Matches[1] }
              $mejor = @{ ds = $ds; tabla = $tn; db = $dbn }
            }
          }
          if ($mejor) { $tabla = $mejor.tabla; $aliasBD = $mejor.db; if (-not $tabla) { $tabla = "(dataset $($mejor.ds))" } }
        }
      }
      $pendienteCampo = [pscustomobject]@{ repo = $repoName; archivo = $archivoActual; componente = $comp; tipo = "T$($tipoCampo)Field"; campo = $null; tabla = $tabla; aliasBD = $aliasBD; tamano = $null }
      $resultado.bd.camposPersistentesNuevos += $pendienteCampo
      continue
    }
    if ($pendienteCampo -and $line -match "^\+\s*FieldName\s*=\s*'([^']+)'") { $pendienteCampo.campo = $Matches[1]; continue }
    if ($pendienteCampo -and $line -match '^\+\s*Size\s*=\s*(\d+)') { $pendienteCampo.tamano = [int]$Matches[1]; continue }
    if ($line -match '^\+\s*end\s*$') { $pendienteCampo = $null }
    if ($line -match $reDDL) {
      $resultado.bd.sentenciasSQL += [pscustomobject]@{ repo = $repoName; archivo = $archivoActual; linea = $line.Substring(1).Trim() }
    }
    foreach ($t in [regex]::Matches($line, $reTabla)) { $resultado.bd.tablasReferenciadas += $t.Groups[1].Value.ToUpper() }
    if ($line -match $reVersionConst) { $resultado.bd.constantesVersion += "$repoName/$($archivoActual): $($Matches[1]) = $($Matches[2])" }
  }
}

# ---------------------------------------------------------------- 4b. Código pendiente de versionar
# Se revisan los repos con cambios del TT, los indicados en -Rutas y los que tienen la rama del TT activa.
# Los artefactos de compilación y del IDE no cuentan (no se versionan).
$reRuido = '(?i)(\.(dcu|exe|dll|bpl|dcp|map|drc|rsm|ddp|dsk|identcache|local|bak|tmp|log|obj|pdb|cache)$|\.~[^/]*$|(^|/)(__history|__recovery|bin|obj|Debug|Release)/)'
foreach ($r in $repos) {
  $repoName = Split-Path $r -Leaf
  $actual = (Invoke-Git $r @('branch', '--show-current')) | Select-Object -First 1
  $esDelTT = ($resultado.repos | Where-Object { $_.ruta -eq $r }) -or ($explicitos -contains $r) -or
             ($actual -match "(^|/)$Ticket([_\-\.]|$)") -or ($Rama -and $actual -eq $Rama)
  if (-not $esDelTT) { continue }
  $sinCommit = @(); $sinRastrear = @(); $ruido = 0
  foreach ($s in (Invoke-Git $r @('status', '--porcelain=v1'))) {
    if ($s.Length -lt 4) { continue }
    $xy = $s.Substring(0, 2); $ruta = $s.Substring(3).Trim('"')
    if ($ruta -match $reRuido) { $ruido++; continue }
    if ($xy -eq '??') { $sinRastrear += $ruta } else { $sinCommit += "$($xy.Trim()) $ruta" }
  }
  $sp = $sinPush[$r]
  if ($sinCommit.Count -or $sinRastrear.Count -or $sp) {
    $resultado.pendientes += [pscustomobject]@{
      repo = $repoName; ruta = $r; ramaActual = $(if ($actual) { $actual } else { '(HEAD separado)' })
      sinCommit = $sinCommit; sinRastrear = $sinRastrear
      sinPush = $(if ($sp) { [pscustomobject]$sp } else { $null }); artefactosIgnorados = $ruido
    }
  }
}
if ($resultado.pendientes.Count) {
  $resultado.advertencias += "Hay código pendiente de versionar en: $(@($resultado.pendientes | ForEach-Object { $_.repo }) -join ', '). Ver la sección 'Código pendiente de versionar'."
}

# Otros TT mencionados en los commits: candidatos a ticket origen de soporte.
$resultado.ticketsRelacionados = @($resultado.commits | ForEach-Object { [regex]::Matches($_.mensaje, '(?i)TT\s?\d{4,}') | ForEach-Object { ($_.Value -replace '\s', '').ToUpper() } } |
  Where-Object { $_ -ne $Ticket } | Sort-Object -Unique)

if ($resultado.repos.Count -eq 0) {
  $msg = "No se encontraron commits para $Ticket en ninguno de los repos revisados."
  foreach ($p in $resultado.pendientes) { $msg += "`n  [$($p.repo)] rama $($p.ramaActual): $($p.sinCommit.Count) archivo(s) sin commit, $($p.sinRastrear.Count) sin rastrear." }
  if ($resultado.pendientes.Count) { $msg += "`nEl código del ticket no está versionado: debe hacerse commit (y push) antes de documentar." }
  throw $msg
}

$resultado.autores = @($resultado.commits | Group-Object autor | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ autor = $_.Name; commits = $_.Count } })
$resultado.bd.tablasReferenciadas = @($resultado.bd.tablasReferenciadas | Where-Object { $_ -notmatch '^(SELECT|WHERE|VALUES|SET|NULL)$' } | Sort-Object -Unique)
$resultado.modulos = @($resultado.modulos | Sort-Object modulo, porArchivo -Unique)
$enTablas = @($resultado.bd.camposPersistentesNuevos | Where-Object { $_.tabla -and $_.tabla -notlike '(dataset*' })
$enQuerys = @($resultado.bd.camposPersistentesNuevos | Where-Object { -not $_.tabla -or $_.tabla -like '(dataset*' })
if ($enTablas.Count -gt 0 -and $resultado.bd.scriptsSQL.Count -eq 0) {
  $resultado.advertencias += "Campos persistentes nuevos sobre TABLAS ($(@($enTablas | ForEach-Object { "$($_.tabla).$($_.campo)" }) -join ', ')) y ningún script .sql versionado. Solicitar el script al desarrollador: sin él, los ejecutables que usan ese DataModule/forma fallarán al abrir la tabla."
}
if ($enQuerys.Count -gt 0) {
  $resultado.advertencias += "Campos persistentes nuevos sobre CONSULTAS ($(@($enQuerys | ForEach-Object { $_.componente }) -join ', ')). Verificar en el SQL de la consulta si las columnas ya existen en BD o si requieren script."
}

# ---------------------------------------------------------------- 5. Salidas
$jsonPath = Join-Path $Salida 'resumen.json'
[IO.File]::WriteAllText($jsonPath, ($resultado | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Resumen de cambios $Ticket")
[void]$md.AppendLine("Generado: $($resultado.generado)`n")
[void]$md.AppendLine("## Repositorios"); foreach ($x in $resultado.repos) { [void]$md.AppendLine("- **$($x.repo)** modo=$($x.modo) rama=$($x.rama) base=$($x.base) commits=$($x.commits) diff=``$($x.diff)`` ($([math]::Round((Get-Item $x.diff).Length/1KB,1)) KB)") }
[void]$md.AppendLine("`n## Commits"); foreach ($c in $resultado.commits) { [void]$md.AppendLine("- $($c.repo) $($c.hash) $($c.fecha) $($c.autor): $($c.mensaje)") }
[void]$md.AppendLine("`n## Archivos"); [void]$md.AppendLine("| Repo | Archivo | Est. | +/- | Módulos (.dpr) | Referenciada por |"); [void]$md.AppendLine("|---|---|---|---|---|---|")
foreach ($a in $resultado.archivos) { [void]$md.AppendLine("| $($a.repo) | $($a.archivo) | $($a.estado) | +$($a.agregadas)/-$($a.eliminadas) | $($a.modulos -join ', ') | $(@($a.referenciadaPor | Select-Object -First 6) -join ', ') |") }
[void]$md.AppendLine("`n## Módulos (ejecutables) afectados y versión actual (.dof)")
foreach ($g in ($resultado.modulos | Group-Object modulo)) {
  $f0 = $g.Group[0]; $dir = @($g.Group | Where-Object { -not $_.indirecto }).Count -gt 0
  $archs = @($g.Group | ForEach-Object { ($_.porArchivo -split '/')[-1] } | Select-Object -Unique) -join ', '
  [void]$md.AppendLine("- **$($g.Name)** v$($f0.version) ($($f0.proyecto))$(if (-not $dir) { ' — indirecto' }) <- $archs")
}
[void]$md.AppendLine("`n## Indicios de base de datos")
foreach ($f in $resultado.bd.camposPersistentesNuevos) { [void]$md.AppendLine("- Campo persistente nuevo: $($f.componente) ($($f.tipo)) campo=$($f.campo) tabla=$($f.tabla) aliasBD=$($f.aliasBD) tamaño=$($f.tamano) [$($f.archivo)]") }
foreach ($s in $resultado.bd.sentenciasSQL) { [void]$md.AppendLine("- SQL en $($s.archivo): ``$($s.linea)``") }
if ($resultado.bd.scriptsSQL.Count) { [void]$md.AppendLine("- Scripts .sql: $($resultado.bd.scriptsSQL -join ', ')") }
if ($resultado.bd.tablasReferenciadas.Count) { [void]$md.AppendLine("- Tablas referenciadas en líneas nuevas: $($resultado.bd.tablasReferenciadas -join ', ')") }
foreach ($v in $resultado.bd.constantesVersion) { [void]$md.AppendLine("- Constante de versión: $v") }
if ($resultado.configuracion.Count) { [void]$md.AppendLine("`n## Archivos de configuración`n- $($resultado.configuracion -join "`n- ")") }
[void]$md.AppendLine("`n## Código pendiente de versionar")
if (-not $resultado.pendientes.Count) { [void]$md.AppendLine('Ninguno.') }
foreach ($p in $resultado.pendientes) {
  [void]$md.AppendLine("- **$($p.repo)** (rama actual: $($p.ramaActual))")
  foreach ($f in $p.sinCommit) { [void]$md.AppendLine("  - Sin commit: ``$f``") }
  foreach ($f in $p.sinRastrear) { [void]$md.AppendLine("  - Sin rastrear: ``$f``") }
  if ($p.sinPush) {
    if ($p.sinPush.publicada) { [void]$md.AppendLine("  - Sin push: $($p.sinPush.commits) commit(s) de $($p.sinPush.rama) que no están en $($p.sinPush.remota)") }
    else { [void]$md.AppendLine("  - Rama $($p.sinPush.rama) sin publicar en el remoto ($($p.sinPush.commits) commit(s))") }
  }
  if ($p.artefactosIgnorados) { [void]$md.AppendLine("  - ($($p.artefactosIgnorados) artefacto(s) de compilación/IDE ignorados)") }
}
[void]$md.AppendLine("`n## Otros TT mencionados en los commits (posible ticket origen de soporte)")
[void]$md.AppendLine($(if ($resultado.ticketsRelacionados.Count) { $resultado.ticketsRelacionados -join ', ' } else { 'Ninguno.' }))
if ($resultado.advertencias.Count) { [void]$md.AppendLine("`n## Advertencias"); foreach ($w in $resultado.advertencias) { [void]$md.AppendLine("- $w") } }
[IO.File]::WriteAllText((Join-Path $Salida 'resumen.md'), $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`nListo. Resumen: $(Join-Path $Salida 'resumen.md')"
Write-Host "      Datos:   $jsonPath"
foreach ($w in $resultado.advertencias) { Write-Warning $w }
