# Detecta y revierte manipulaciones de Microsoft Defender:
#  - exclusiones de ruta, extensión, proceso e IP (preferencias normales)
#  - exclusiones y ThreatIDDefaultAction escondidas como política (HKLM\SOFTWARE\Policies\Microsoft\Windows Defender);
#    Remove-MpPreference NO puede quitarlas, por eso hay que borrar la clave
#  - activa el bloqueo de aplicaciones no deseadas (PUA) y la protección en la nube
# Sin -Aplicar solo informa. Con -Aplicar respalda la política en -Respaldo (.reg) y luego borra. Requiere administrador.
# -ConservarProcesos / -ConservarRutas: exclusiones legítimas que el usuario quiere mantener.
# -ConNombres: busca el nombre de cada amenaza "permitida" (lento: Get-MpThreatCatalog tarda).
param([string]$Respaldo = $PSScriptRoot, [string[]]$ConservarProcesos = @(), [string[]]$ConservarRutas = @(), [switch]$ConNombres, [switch]$Aplicar)
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$mp = Get-MpPreference
$acciones = @{ 1 = 'Limpiar'; 2 = 'Cuarentena'; 3 = 'Quitar'; 6 = 'PERMITIR'; 8 = 'Usuario decide'; 9 = 'Sin acción'; 10 = 'Bloquear' }

'=== Preferencias (Remove-MpPreference) ==='
$rutas = @($mp.ExclusionPath | Where-Object { $_ -and $ConservarRutas -notcontains $_ })
$procs = @($mp.ExclusionProcess | Where-Object { $_ -and $ConservarProcesos -notcontains $_ })
"ExclusionPath a quitar: " + $(if ($rutas) { $rutas -join '; ' } else { 'ninguna' })
"ExclusionExtension a quitar: " + $(if ($mp.ExclusionExtension) { $mp.ExclusionExtension -join '; ' } else { 'ninguna' })
"ExclusionProcess a quitar: " + $(if ($procs) { $procs -join '; ' } else { 'ninguna' })
"ExclusionIpAddress a quitar: " + $(if ($mp.ExclusionIpAddress) { $mp.ExclusionIpAddress -join '; ' } else { 'ninguna' })
"Conservadas: " + ((@($ConservarRutas) + @($ConservarProcesos)) -join '; ')

"`n=== Política en el registro ==="
$exPol = @(); $thrPol = @()
if (Test-Path "$pol\Exclusions") { Get-ChildItem "$pol\Exclusions" | ForEach-Object { $k = $_; $k.Property | ForEach-Object { $exPol += "$($k.PSChildName): $_" } } }
if (Test-Path "$pol\Threats\ThreatIDDefaultAction") { $k = Get-Item "$pol\Threats\ThreatIDDefaultAction"; $k.Property | ForEach-Object { $thrPol += [pscustomobject]@{ Id = $_; Accion = $k.GetValue($_) } } }
"Exclusiones por política: $($exPol.Count)"; $exPol | ForEach-Object { "  $_" }
"Amenazas con acción forzada por política: $($thrPol.Count)"
foreach ($x in $thrPol) {
  $nom = if ($ConNombres) { (Get-MpThreatCatalog -ThreatID $x.Id -ErrorAction SilentlyContinue).ThreatName } else { '' }
  "  {0} -> {1} {2}" -f $x.Id, $acciones[[int]$x.Accion], $nom
}
if ($thrPol | Where-Object { [int]$_.Accion -eq 6 }) { '  <<< El malware ordenó a Defender PERMITIR estas amenazas.' }
$otras = if (Test-Path $pol) { (Get-Item $pol).Property + (Get-ChildItem $pol -Recurse | Where-Object { $_.PSChildName -notmatch 'Exclusions|Paths|Processes|Extensions|IpAddresses|Threats|ThreatIDDefaultAction' -and $_.Property } | ForEach-Object { $k = $_; $k.Property | ForEach-Object { "$($k.PSChildName)\$_=$($k.GetValue($_))" } }) }
"Otras políticas de Defender: " + $(if ($otras) { $otras -join '; ' } else { 'ninguna' })
if ($otras -match 'Disable') { '  <<< Hay políticas que DESACTIVAN protecciones; revísalas y quítalas si no vienen de la organización.' }

"`n=== Configuración ==="
"PUAProtection actual: $($mp.PUAProtection) (1 = bloquear) | MAPSReporting: $($mp.MAPSReporting) (2 = avanzado) | Tamper: $((Get-MpComputerStatus).IsTamperProtected)"

if (-not $Aplicar) { "`n(Simulación) Nada se cambió. Repite con -Aplicar para revertir."; return }

"`n=== Aplicando ==="
if (Test-Path $pol) {
  $bk = Join-Path $Respaldo ("politica_defender_{0:yyyyMMdd_HHmmss}.reg" -f (Get-Date))
  reg export 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender' "$bk" | Out-Null
  "Respaldo: $bk ($(Test-Path $bk))"
  foreach ($sub in 'Exclusions', 'Threats') { if (Test-Path "$pol\$sub") { Remove-Item "$pol\$sub" -Recurse -Force; "Borrada política $sub" } }
}
if ($rutas) { Remove-MpPreference -ExclusionPath $rutas }
if ($mp.ExclusionExtension) { Remove-MpPreference -ExclusionExtension $mp.ExclusionExtension }
if ($procs) { Remove-MpPreference -ExclusionProcess $procs }
if ($mp.ExclusionIpAddress) { Remove-MpPreference -ExclusionIpAddress $mp.ExclusionIpAddress }
if ($mp.ThreatIDDefaultAction_Ids) { Remove-MpPreference -ThreatIDDefaultAction_Ids $mp.ThreatIDDefaultAction_Ids }
Set-MpPreference -PUAProtection Enabled -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -DisableRealtimeMonitoring $false
$mp = Get-MpPreference
"`n=== Resultado ==="
"ExclusionPath: " + $(if ($mp.ExclusionPath) { $mp.ExclusionPath -join '; ' } else { 'ninguna' })
"ExclusionExtension: " + $(if ($mp.ExclusionExtension) { $mp.ExclusionExtension -join '; ' } else { 'ninguna' })
"ExclusionProcess: " + $(if ($mp.ExclusionProcess) { $mp.ExclusionProcess -join '; ' } else { 'ninguna' })
"ThreatIDDefaultAction: " + $(if ($mp.ThreatIDDefaultAction_Ids) { $mp.ThreatIDDefaultAction_Ids -join ', ' } else { 'ninguna' })
"PUA: $($mp.PUAProtection) | MAPS: $($mp.MAPSReporting)"
if ($mp.ExclusionPath) { 'AVISO: siguen exclusiones. Si la Protección contra alteraciones está activa o hay GPO de la organización, no se pueden quitar desde aquí.' }
