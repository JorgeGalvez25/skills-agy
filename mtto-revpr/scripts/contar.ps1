# /mtto-revpr paso 4: veredicto y hallazgos por severidad de cada informe TT*.md (para el índice; no contar a mano)
param([Parameter(Mandatory)][string]$Reportes)
$ErrorActionPreference = 'Stop'
$tot = @{ Alta = 0; Media = 0; Baja = 0 }; $ver = @{}
$filas = foreach ($f in Get-ChildItem $Reportes -Filter 'TT*.md' | Sort-Object Name) {
  $t = Get-Content $f.FullName -Encoding UTF8
  $v = ($t | Where-Object { $_ -match '^\*\*Veredicto:\*\*' } | Select-Object -First 1) -replace '^\*\*Veredicto:\*\*\s*', '' -replace '\s+—.*$', ''
  $n = @{}
  foreach ($s in 'Alta', 'Media', 'Baja') { $n[$s] = @($t | Where-Object { $_ -match "^\|\s*\d+\s*\|\s*\**$s\**\s*\|" }).Count; $tot[$s] += $n[$s] }
  $ver[$v] = 1 + [int]$ver[$v]
  [pscustomobject]@{ TT = $f.BaseName; Veredicto = $v; Alta = $n.Alta; Media = $n.Media; Baja = $n.Baja }
}
$filas | Format-Table -AutoSize | Out-String -Width 200
"Veredictos: " + (($ver.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ' · ')
"Total: Alta $($tot.Alta) · Media $($tot.Media) · Baja $($tot.Baja)"
