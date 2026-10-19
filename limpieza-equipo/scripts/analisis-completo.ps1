# Análisis completo de Defender sin interrupciones por suspensión. Requiere administrador.
# Evita la suspensión SOLO en corriente alterna (con batería se suspende igual, para no agotarla),
# actualiza firmas, analiza, recopila detecciones y restaura la configuración de energía original.
# -Apagar: al terminar programa un apagado de RESPALDO en -RespaldoMin minutos (cancelable con shutdown /a).
param([string]$Log = (Join-Path $PSScriptRoot 'analisis_log.txt'), [switch]$Apagar, [int]$RespaldoMin = 30)
function EscribirLog($m) { $l = "[{0:dd/MM HH:mm:ss}] {1}" -f (Get-Date), $m; $l; Add-Content -Path $Log -Value $l -Encoding utf8 }
function AcValue($sub, $set) { $o = powercfg /query SCHEME_CURRENT $sub $set 2>$null | Select-String -Pattern '(alterna actual|Current AC Power Setting Index):\s*0x([0-9a-fA-F]+)'; if ($o) { [Convert]::ToInt32($o.Matches[0].Groups[2].Value, 16) } }
Set-Content -Path $Log -Value "Análisis completo de Defender - $(Get-Date)" -Encoding utf8

$lidSub = '4f971e89-eebd-4455-a8de-9e59040e7347'; $lid = '5ca83367-6e45-459f-a27b-476b1d01c936'
$origStandby = AcValue 'SUB_SLEEP' 'STANDBYIDLE'; if ($null -eq $origStandby) { $origStandby = 1800 }
$origLid = AcValue $lidSub $lid; if ($null -eq $origLid) { $origLid = 1 }   # oculta en muchos equipos; 1 = Suspender (predeterminado)
$bat = Get-CimInstance Win32_Battery
if ($bat -and $bat.BatteryStatus -eq 1) { EscribirLog "AVISO: el equipo está con BATERÍA ($($bat.EstimatedChargeRemaining)%). Puede suspenderse e interrumpir el análisis; conéctalo a la corriente." }

powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0
powercfg /setacvalueindex SCHEME_CURRENT $lidSub $lid 0
powercfg /setactive SCHEME_CURRENT
Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
[void][Win32.Power]::SetThreadExecutionState([uint32]'0x80000001')
EscribirLog "Suspensión desactivada en AC (original: inactividad=$origStandby s, tapa=$origLid)"

try {
  try { Update-MpSignature -ErrorAction Stop } catch { EscribirLog "Aviso firmas: $($_.Exception.Message)" }
  EscribirLog "Firmas: $((Get-MpComputerStatus).AntivirusSignatureLastUpdated)"
  $ex = Get-MpPreference
  if ($ex.ExclusionPath -or $ex.ExclusionExtension) { EscribirLog "AVISO: Defender tiene exclusiones ($((@($ex.ExclusionPath) + @($ex.ExclusionExtension)) -join '; ')). El análisis NO revisará esas rutas." }
  $start = Get-Date
  L 'Iniciando análisis completo...'
  try { Start-MpScan -ScanType FullScan -ErrorAction Stop } catch { EscribirLog "ERROR en el análisis: $($_.Exception.Message)" }
  EscribirLog ("Análisis terminado. Duración: {0:N0} min" -f ((Get-Date) - $start).TotalMinutes)
  Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1000, 1001, 1002, 1005; StartTime = $start } -ErrorAction SilentlyContinue | Sort-Object TimeCreated | ForEach-Object { EscribirLog ("Evento {0}: {1}" -f $_.Id, @{1000 = 'inicio'; 1001 = 'COMPLETADO'; 1002 = 'cancelado'; 1005 = 'FALLÓ' }[$_.Id]) }
  L '--- DETECCIONES ---'
  $det = Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117, 1118, 1119; StartTime = $start } -ErrorAction SilentlyContinue | Sort-Object TimeCreated
  if (-not $det) { L 'Sin detecciones.' }
  foreach ($e in $det) {
    $x = [xml]$e.ToXml(); $d = @{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
    EscribirLog ("[{0}] {1} | Severidad: {2} | Categoría: {3} | Acción: {4} | Ruta: {5}" -f $e.Id, $d['Threat Name'], $d['Severity Name'], $d['Category Name'], $d['Action Name'], $d['Path'])
  }
  Get-MpThreatDetection | Where-Object InitialDetectionTime -ge $start | ForEach-Object {
    EscribirLog ("ESTADO: {0} | ActionSuccess={1} | {2}" -f (Get-MpThreat -ThreatID $_.ThreatID).ThreatName, $_.ActionSuccess, ($_.Resources -join ' ; '))
  }
}
finally {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $origStandby
  powercfg /setacvalueindex SCHEME_CURRENT $lidSub $lid $origLid
  powercfg /setactive SCHEME_CURRENT
  [void][Win32.Power]::SetThreadExecutionState([uint32]'0x80000000')
  EscribirLog "Energía restaurada (inactividad=$origStandby s, tapa=$origLid)"
  if ($Apagar) { shutdown /s /t ($RespaldoMin * 60) /c "Apagado de respaldo tras el análisis de Defender. Cancelar con: shutdown /a"; EscribirLog "Apagado de respaldo programado en $RespaldoMin min" }
  L 'FIN'
}
