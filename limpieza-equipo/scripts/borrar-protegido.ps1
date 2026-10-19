# Borra archivos o carpetas maliciosos aunque tengan permisos "Deny" para Todos (táctica anti-borrado).
# Primero registra el hash SHA256 de cada archivo en -Respaldo\hashes_eliminados.txt.
# Sin -Aplicar solo muestra lo que borraría. Rutas en Program Files o Windows requieren administrador.
param([Parameter(Mandatory)][string[]]$Rutas, [string]$Respaldo = $PSScriptRoot, [switch]$Aplicar)
$reg = Join-Path $Respaldo 'hashes_eliminados.txt'
foreach ($r in $Rutas) {
  if (-not (Test-Path -LiteralPath $r)) { "$r : no existe"; continue }
  $item = Get-Item -LiteralPath $r -Force
  $files = if ($item.PSIsContainer) { Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue } else { @($item) }
  $deny = (Get-Acl -LiteralPath $r).Access | Where-Object { $_.AccessControlType -eq 'Deny' }
  "$r : $(@($files).Count) archivo(s)" + $(if ($deny) { ' | tiene reglas DENY: ' + (($deny | ForEach-Object { "$($_.IdentityReference) $($_.FileSystemRights)" }) -join '; ') } else { '' })
  foreach ($f in $files) {
    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    $sig = (Get-AuthenticodeSignature -LiteralPath $f.FullName).Status
    $line = "{0} | {1} | {2:N0} B | creado {3} | firma {4} | {5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $h, $f.Length, $f.CreationTime, $sig, $f.FullName
    "  $line"
    if ($Aplicar) { Add-Content -Path $reg -Value $line -Encoding utf8 }
  }
  if (-not $Aplicar) { "  (simulación) se borraría"; continue }
  if ($item.PSIsContainer) { icacls "$r" /remove:d *S-1-1-0 /t /c /q | Out-Null } else { icacls "$r" /remove:d *S-1-1-0 /c /q | Out-Null }
  Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue
  "  -> " + $(if (Test-Path -LiteralPath $r) { 'SIGUE AHÍ (¿en uso? cierra el programa; ¿falta administrador?)' } else { 'eliminado' })
}
if ($Aplicar) { "Hashes registrados en $reg" }
