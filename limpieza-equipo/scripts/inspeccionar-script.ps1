# Inspecciona un script sospechoso (VBS/JS/WSF/PS1, con o sin extensión) SIN EJECUTARLO.
# Muestra el hash, las cadenas legibles, los URL y decodifica de forma estática los textos ofuscados
# como Array(n1,n2,...) con XOR. La clave se detecta sola probando las constantes numéricas del archivo.
# Uso: inspeccionar-script.ps1 -Ruta <archivo> [-MostrarCodigo]
param([Parameter(Mandatory)][string]$Ruta, [switch]$MostrarCodigo)
$f = Get-Item -LiteralPath $Ruta -Force
$t = [IO.File]::ReadAllText($f.FullName)
"Archivo: $($f.FullName)"
"Tamaño: $($f.Length) B | Creado: $($f.CreationTime) | Modificado: $($f.LastWriteTime)"
"SHA256: $((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)"
$tipo = if ($t -match '(?im)^\s*(Function|Sub|Dim|Private|Set)\b') { 'VBScript' } elseif ($t -match '(?m)\b(var|let|const|function)\b.*[;{]') { 'JScript/JavaScript' } elseif ($t -match '(?i)\$[a-z_]+\s*=|Invoke-|New-Object') { 'PowerShell' } else { 'desconocido' }
"Tipo probable: $tipo"

"`n--- URL e IP en claro ---"
([regex]::Matches($t, '(?i)\b(?:https?|ftp)://[^\s"''<>)]+|\b\d{1,3}(?:\.\d{1,3}){3}\b') | ForEach-Object Value | Sort-Object -Unique)
"`n--- Objetos COM y llamadas peligrosas en claro ---"
([regex]::Matches($t, '(?i)CreateObject\("?[^)"]+|WScript\.Shell|ADODB\.Stream|MSXML2\.[A-Za-z]+|Shell\.Application|\.Run\b|\.Exec\b|Invoke-Expression|IEX\b|DownloadString|FromBase64String') | ForEach-Object Value | Sort-Object -Unique)

# Decodificación XOR de Array(...) numéricos. Esquemas probados: v XOR (k+i+1), v XOR (k+i), v XOR k.
$arrays = [regex]::Matches($t, 'Array\(\s*((?:\d+\s*,\s*)*\d+)\s*\)') | ForEach-Object { , ([int[]]($_.Groups[1].Value -split '\s*,\s*')) }
if ($arrays) {
  $consts = [regex]::Matches($t, '(?<![\w(,])\b(\d{3,6})\b(?![\w,)])') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
  $schemes = @{ 'k+i+1' = { param($k, $i) $k + $i + 1 }; 'k+i' = { param($k, $i) $k + $i }; 'k' = { param($k, $i) $k } }
  function Decode($arr, $k, $sch) { -join (0..($arr.Count - 1) | ForEach-Object { [char](($arr[$_] -bxor (& $sch $k $_)) -band 0xFFFF) }) }
  function Score($s) { if (-not $s) { return 0 }; ([regex]::Matches($s, '[\x20-\x7E]')).Count / $s.Length }
  $best = $null; $bestScore = 0
  foreach ($k in $consts) { foreach ($n in $schemes.Keys) {
      $sc = ($arrays | Select-Object -First 15 | ForEach-Object { Score (Decode $_ $k $schemes[$n]) } | Measure-Object -Average).Average
      if ($sc -gt $bestScore) { $bestScore = $sc; $best = @($k, $n) } } }
  "`n--- Textos ofuscados: $($arrays.Count) arreglos ---"
  if ($best -and $bestScore -ge 0.85) {
    "Clave detectada: base=$($best[0]), esquema v XOR ($($best[1])), legibilidad {0:P0}" -f $bestScore
    $seen = @{}
    foreach ($a in $arrays) { $s = Decode $a $best[0] $schemes[$best[1]]; if (-not $seen[$s]) { $seen[$s] = 1; "  $s" } }
  } else {
    'No se encontró una clave XOR simple (mejor legibilidad {0:P0}). Puede usar otro cifrado; revisa el código manualmente.' -f $bestScore
  }
}
if ($MostrarCodigo) { "`n--- Código (primeros 8000 caracteres) ---"; $t.Substring(0, [Math]::Min(8000, $t.Length)) }
