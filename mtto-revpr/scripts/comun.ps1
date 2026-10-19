# Funciones compartidas por los scripts de /mtto-revpr (guardar en UTF-8 con BOM: PowerShell 5.1)

$Org = 'https://dev.azure.com/igasmxproyectos'

# Token de Azure DevOps: variable de la sesión o, si la sesión se abrió antes de crearla, la del usuario
function Get-Pat {
  $p = $env:AZURE_DEVOPS_EXT_PAT
  if (-not $p) { $p = [Environment]::GetEnvironmentVariable('AZURE_DEVOPS_EXT_PAT', 'User') }
  if (-not $p) { throw 'SIN_TOKEN: no existe la variable AZURE_DEVOPS_EXT_PAT (ver "Token" en SKILL.md).' }
  return $p.Trim()
}

function Get-Headers {
  @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + (Get-Pat))) }
}

function Invoke-Ado([string]$Url) {
  try { Invoke-RestMethod -Uri $Url -Headers $script:H }
  catch {
    $c = $_.Exception.Response.StatusCode.value__
    if ($c -eq 401 -or $c -eq 203) { throw 'TOKEN_INVALIDO: Azure DevOps rechazó el token (vencido, revocado o sin permiso Code: Read).' }
    throw
  }
}

# Número del TT para comparar ramas y títulos (TT091138, TT-91138 y TT91138 son el mismo)
function Get-NumTT([string]$s) { if ($s -match '(?i)TT[\s_-]*0*(\d{4,6})') { [int]$Matches[1] } else { $null } }

function Write-Utf8([string]$Ruta, [string]$Texto) {
  New-Item -ItemType Directory -Force (Split-Path $Ruta) | Out-Null
  [IO.File]::WriteAllText($Ruta, $Texto, (New-Object Text.UTF8Encoding($false)))
}

# git fuera de un repo (diff --no-index, merge-file). En PS 5.1 cualquier línea en stderr con ErrorActionPreference=Stop
# aborta el script, y git devuelve 1 cuando hay diferencias: se aíslan ambas cosas aquí.
function Invoke-Git {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & git -c core.autocrlf=false -c core.safecrlf=false @args 2>$null } finally { $ErrorActionPreference = $prev; $global:LASTEXITCODE = 0 }
}

# Bytes de un archivo de código a texto: UTF-8 (con o sin BOM) o, si no es UTF-8 válido, Windows-1252 (Delphi)
function ConvertTo-Texto([byte[]]$b) {
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($b) }
  catch { return [Text.Encoding]::GetEncoding(1252).GetString($b) }
}

# Filas de una hoja .xlsx sin abrir Excel (funciona aunque el archivo esté abierto). Devuelve objetos con los encabezados de la fila 1.
function Read-XlsxHoja([string]$Ruta, [string]$Hoja) {
  Add-Type -AssemblyName System.IO.Compression
  $fs = [IO.File]::Open($Ruta, 'Open', 'Read', 'ReadWrite')
  try {
    $zip = New-Object IO.Compression.ZipArchive($fs, 'Read')
    $leer = { param($n) $e = $zip.GetEntry($n); if (-not $e) { return $null }; $r = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8); try { [xml]$r.ReadToEnd() } finally { $r.Close() } }
    $txt = { param($t) if ($null -eq $t) { '' } elseif ($t -is [string]) { $t } else { $t.'#text' } }
    $ss = @()
    $x = & $leer 'xl/sharedStrings.xml'
    if ($x) { $ss = @($x.sst.si | ForEach-Object { if ($_.t) { & $txt $_.t } else { ($_.r | ForEach-Object { & $txt $_.t }) -join '' } }) }
    $wb = & $leer 'xl/workbook.xml'
    $sh = @($wb.workbook.sheets.sheet | Where-Object { $_.name -eq $Hoja })[0]
    if (-not $sh) { $sh = @($wb.workbook.sheets.sheet)[0] }
    $rid = $sh.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
    $rels = & $leer 'xl/_rels/workbook.xml.rels'
    $target = (@($rels.Relationships.Relationship | Where-Object { $_.Id -eq $rid })[0]).Target -replace '^/?xl/', ''
    $ws = & $leer ('xl/' + $target)
    $filas = foreach ($row in $ws.worksheet.sheetData.row) {
      $f = @{}
      foreach ($c in $row.c) {
        $col = $c.r -replace '\d', ''
        $v = switch ($c.t) { 's' { $ss[[int]$c.v] } 'inlineStr' { & $txt $c.is.t } default { $c.v } }
        $f[$col] = "$v"
      }
      $f
    }
    $enc = $filas[0]
    foreach ($f in ($filas | Select-Object -Skip 1)) {
      if (-not ($f.Values | Where-Object { $_ })) { continue }
      $o = [ordered]@{}
      foreach ($k in $enc.Keys) { $o[$enc[$k].Trim()] = $f[$k] }
      [pscustomobject]$o
    }
  } finally { $fs.Close() }
}
