# Revisión rápida de seguimiento (solo lectura): ¿volvió algo después de la limpieza?
# -Indicadores: JSON opcional con los indicadores del caso, por ejemplo:
#   { "dominios": ["malo.com"], "tareas": ["AbCdEf"], "rutas": ["C:\\ProgramData\\XyZ"], "hashes": ["ABC..."] }
# -Desde: fecha de la limpieza; se buscan carpetas aleatorias creadas después.
param([string]$Indicadores, [datetime]$Desde = (Get-Date).AddDays(-30))
$ok = $true
function Comprobar($nombre, $hallado) { if ($hallado) { $script:ok = $false; "[!!] $nombre : $($hallado -join ', ')" } else { "[OK] $nombre : nada" } }
$ioc = if ($Indicadores -and (Test-Path $Indicadores)) { Get-Content $Indicadores -Raw | ConvertFrom-Json } else { $null }
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"Seguimiento $(Get-Date) | Admin: $esAdmin | Carpetas nuevas desde $($Desde.ToString('dd/MM/yyyy'))"

Comprobar 'Procesos de script (wscript/cscript/mshta/forfiles)' ((Get-Process wscript, cscript, mshta, forfiles -ErrorAction SilentlyContinue).Name)
Comprobar 'Tareas sospechosas en la raíz' ((Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' -and (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ') -match 'rundll32|forfiles|wscript|cscript|mshta' }).TaskName)
$mp = Get-MpPreference
Comprobar 'Exclusiones de Defender (ruta/extensión)' (@($mp.ExclusionPath) + @($mp.ExclusionExtension) | Where-Object { $_ })
Comprobar 'Amenazas con acción forzada' ($mp.ThreatIDDefaultAction_Ids)
Comprobar 'Política de Defender (exclusiones/amenazas)' ((Get-ChildItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Property -and $_.PSChildName -match 'Paths|Extensions|Processes|ThreatIDDefaultAction' }).PSChildName)
$st = Get-MpComputerStatus
Comprobar 'Protecciones de Defender desactivadas' (@(if (-not $st.RealTimeProtectionEnabled) { 'tiempo real' }; if (-not $st.IsTamperProtected) { 'protección contra alteraciones' }; if ($mp.PUAProtection -ne 1) { 'PUA' }))
Comprobar 'Políticas de navegadores' (@('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge', 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave') | Where-Object { Test-Path $_ })
$alea = Get-ChildItem 'C:\Program Files (x86)', 'C:\Program Files', 'C:\ProgramData', 'C:\Windows\Temp', "$env:LOCALAPPDATA\Temp", "$env:LOCALAPPDATA\VirtualStore\Program Files (x86)" -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.CreationTime -ge $Desde -and $_.Name -cmatch '^[A-Za-z0-9]{8,22}$' -and $_.Name -cmatch '[a-z][A-Z].*[a-z][A-Z]' -and $_.Name -notmatch 'Microsoft|Windows|Software|Service|Update|NuGet|Metadata|Copilot' }
Comprobar 'Carpetas nuevas con nombre aleatorio' ($alea.FullName)
if ($ioc) {
  Comprobar 'Dominios del caso en caché DNS' ((Get-DnsClientCache -ErrorAction SilentlyContinue | Where-Object { $e = $_.Entry; $ioc.dominios | Where-Object { $e -like "*$_" } }).Entry | Sort-Object -Unique)
  Comprobar 'Tareas del caso' ($ioc.tareas | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue })
  Comprobar 'Rutas del caso' ($ioc.rutas | Where-Object { Test-Path -LiteralPath $_ })
}
"Último análisis completo: $($st.FullScanEndTime) | Firmas: $($st.AntivirusSignatureLastUpdated)"
$rec = Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116; StartTime = $Desde } -ErrorAction SilentlyContinue
"Detecciones de Defender desde $($Desde.ToString('dd/MM/yyyy')): $(@($rec).Count)"
if ($ok) { "`nRESULTADO: limpio, no se encontró nada que indique reinfección." } else { "`nRESULTADO: hay hallazgos; revisarlos antes de dar el equipo por limpio." }
if (-not $esAdmin) { 'Nota: sin administrador algunas tareas y políticas pueden no verse.' }
