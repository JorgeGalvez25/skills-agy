# Lista o elimina tareas programadas maliciosas.
# Sin parámetros: lista las sospechosas (raíz \, sin autor, lanzan rundll32/forfiles/wscript/cscript/mshta).
# Con -Nombres a,b -Aplicar: elimina esas tareas y su archivo en System32\Tasks. Requiere administrador.
param([string[]]$Nombres, [switch]$Aplicar)
function Accion($t) { ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ' }
$sosp = Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' -and -not $_.Author -and (Accion $_) -match 'rundll32|forfiles|wscript|cscript|mshta|\.vbs|\.js\b|\.wsf' }
if (-not $Nombres) {
  if (-not $sosp) { 'No hay tareas sospechosas visibles. Si no eres administrador, algunas pueden no verse.'; return }
  foreach ($t in $sosp) { $i = $t | Get-ScheduledTaskInfo; "{0} | estado={1} | últ. ejec.={2}`n    {3}" -f $t.TaskName, $t.State, $i.LastRunTime, (Accion $t) }
  "`nPara eliminarlas: -Nombres $(($sosp.TaskName) -join ',') -Aplicar"
  return
}
foreach ($n in $Nombres) {
  $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
  $file = "$env:SystemRoot\System32\Tasks\$n"
  if (-not $t -and -not (Test-Path $file)) { "$n : no existe"; continue }
  if ($t) { "$n : $(Accion $t)" }
  if ($Aplicar) {
    if ($t) { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue }
    if (Test-Path $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    "$n : " + $(if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) { 'NO SE PUDO ELIMINAR (¿falta administrador?)' } else { 'eliminada' })
  } else { "$n : (simulación) se eliminaría" }
}
