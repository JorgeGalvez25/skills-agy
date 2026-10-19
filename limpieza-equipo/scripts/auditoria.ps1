# Auditoría de persistencia y compromiso - SOLO LECTURA. No modifica nada.
# Uso: auditoria.ps1 -Salida <archivo.txt> [-Desde <fecha>]   (mejor en Terminal de Administrador)
param([string]$Salida = (Join-Path $PSScriptRoot 'auditoria_reporte.txt'), [datetime]$Desde = (Get-Date).AddMonths(-12))
$ErrorActionPreference = 'SilentlyContinue'
function Section($t) { "`n==================== $t ====================" }   # 'H' choca con el alias de Get-History
function Sig($path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return 'SIN_ARCHIVO' }
  $s = Get-AuthenticodeSignature -LiteralPath $path
  if ($s.Status -eq 'Valid') { 'OK:' + ($s.SignerCertificate.Subject -replace '^CN="?([^",]+).*', '$1') } else { $s.Status.ToString().ToUpper() }
}
function ExePath($cmd) {
  if (-not $cmd) { return $null }
  $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim()) -replace '""', '"'
  if ($c -match '^"([^"]+)"') { return $Matches[1] }
  if ($c -match '^(.+?\.(exe|dll|sys|com|bat|cmd|vbs|js|ps1))') { return $Matches[1] }
  ($c -split ' ')[0]
}
function EsAleatorio($n) { $n -cmatch '^[A-Za-z0-9]{8,22}$' -and $n -cmatch '[a-z][A-Z].*[a-z][A-Z]' -and $n -notmatch 'Microsoft|Windows|Software|Service|Update|Package|Assistant|PowerShell|NuGet|Metadata|Copilot' }
$lol = 'wscript|cscript|mshta|rundll32|regsvr32|forfiles|powershell|pwsh|cmd\.exe|bitsadmin|certutil|curl|\.vbs|\.js\b|\.jse|\.wsf|\\ProgramData\\|\\Temp\\|\\AppData\\'
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

& {
Section 'CONTEXTO'
"Fecha: $(Get-Date) | Equipo: $env:COMPUTERNAME | Admin: $esAdmin | Revisando cambios desde: $($Desde.ToString('dd/MM/yyyy'))"
"Último arranque: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
"Dominio: $((Get-CimInstance Win32_ComputerSystem).PartOfDomain) | " + ((dsregcmd /status | Select-String 'AzureAdJoined|DomainJoined|MDMUrl' | ForEach-Object { $_.Line.Trim() }) -join ' | ')
if (-not $esAdmin) { 'AVISO: sin permisos de administrador. Tareas, rutas de procesos, Windows\Temp y políticas pueden salir incompletas.' }

Section 'TAREAS PROGRAMADAS (fuera de \Microsoft\ o con acciones sospechosas)'
Get-ScheduledTask | ForEach-Object {
  $t = $_
  foreach ($a in $t.Actions) {
    $line = "$($a.Execute) $($a.Arguments)"
    if ($t.TaskPath -notlike '\Microsoft\*' -or $line -match $lol) {
      $flag = if ($t.TaskPath -eq '\' -and -not $t.Author -and $line -match 'rundll32|forfiles|wscript|cscript|mshta') { '  <<< SOSPECHOSA' } else { '' }
      $info = $t | Get-ScheduledTaskInfo
      "[{0}] {1}{2} | Autor: {3} | Últ. ejec.: {4} | Firma: {5}{6}`n    {7}" -f $t.State, $t.TaskPath, $t.TaskName, $t.Author, $info.LastRunTime, (Sig (ExePath $a.Execute)), $flag, $line
    }
  }
}

Section 'SERVICIOS NO FIRMADOS POR MICROSOFT'
Get-CimInstance Win32_Service | ForEach-Object {
  $p = ExePath $_.PathName; $s = Sig $p
  if ($s -notmatch 'OK:Microsoft') { "[{0}/{1}] {2} ({3}) | {4}`n    {5}" -f $_.State, $_.StartMode, $_.Name, $_.DisplayName, $s, $_.PathName }
}

Section 'ARRANQUE: RUN / RUNONCE / WINLOGON / IFEO / APPINIT / CARPETAS DE INICIO'
$runKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'
foreach ($k in $runKeys) { $i = Get-Item $k; if ($i) { foreach ($n in $i.Property) { $v = $i.GetValue($n); "{0}\{1} | {2}`n    {3}" -f $k, $n, (Sig (ExePath $v)), $v } } }
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
"Winlogon Shell: $($wl.Shell) | Userinit: $($wl.Userinit)"
$ai = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows'
"AppInit_DLLs: '$($ai.AppInit_DLLs)' LoadAppInit: $($ai.LoadAppInit_DLLs)"
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' | ForEach-Object { $d = (Get-ItemProperty $_.PSPath).Debugger; if ($d) { "IFEO Debugger: $($_.PSChildName) -> $d" } }
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Force | Where-Object Name -ne 'desktop.ini' | ForEach-Object { "Inicio: $($_.FullName) ($($_.CreationTime))" }

Section 'SUSCRIPCIONES WMI (persistencia oculta)'
Get-CimInstance -Namespace root\subscription -ClassName __EventFilter | Where-Object Name -ne 'SCM Event Log Filter' | ForEach-Object { "Filtro: $($_.Name) | $($_.Query)" }
Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer | ForEach-Object { "Consumidor CMD: $($_.Name) | $($_.CommandLineTemplate)" }
Get-CimInstance -Namespace root\subscription -ClassName ActiveScriptEventConsumer | ForEach-Object { "Consumidor script: $($_.Name) | $($_.ScriptText)" }

Section 'PROCESOS: SCRIPTS, NO FIRMADOS O EN RUTAS SOSPECHOSAS'
$procs = Get-CimInstance Win32_Process
$procs | Where-Object { $_.Name -match '^(wscript|cscript|mshta|forfiles)\.exe$' } | ForEach-Object {
  $pp = $procs | Where-Object ProcessId -eq $_.ParentProcessId
  "<<< SCRIPT PID {0} {1} (padre {2} {3}) creado {4}`n    {5}" -f $_.ProcessId, $_.Name, $_.ParentProcessId, $pp.Name, $_.CreationDate, $_.CommandLine
}
$procs | Where-Object ExecutablePath | ForEach-Object {
  $s = Sig $_.ExecutablePath
  if (($s -notmatch '^OK:' -and $_.ExecutablePath -notmatch '\\WindowsApps\\') -or $_.ExecutablePath -match '\\ProgramData\\(?!Microsoft\\Windows Defender)|\\Temp\\|\\AppData\\Roaming\\') { "PID {0} | {1} | {2}`n    {3}" -f $_.ProcessId, $s, $_.ExecutablePath, $_.CommandLine }
}

Section 'RED: CONEXIONES ESTABLECIDAS Y PUERTOS EN ESCUCHA'
Get-NetTCPConnection -State Established | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0)' } | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess; "{0,-26} {1,-42} {2}" -f $p.ProcessName, "$($_.RemoteAddress):$($_.RemotePort)", $p.Path
} | Sort-Object -Unique
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' -and $_.LocalPort -lt 49152 } | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess; "ESCUCHA {0,-6} {1,-26} {2}" -f $_.LocalPort, $p.ProcessName, $p.Path
} | Sort-Object -Unique
"DNS en caché: " + ((Get-DnsClientCache | Select-Object -ExpandProperty Entry -Unique | Sort-Object) -join ', ')

Section 'DEFENDER: ESTADO, EXCLUSIONES Y ACCIONES PERMITIDAS'
$mp = Get-MpPreference; $st = Get-MpComputerStatus
"Tiempo real: $($st.RealTimeProtectionEnabled) | Tamper: $($st.IsTamperProtected) | PUA: $($mp.PUAProtection) | MAPS: $($mp.MAPSReporting) | Firmas: $($st.AntivirusSignatureLastUpdated) | Últ. completo: $($st.FullScanEndTime)"
"ExclusionPath: $($mp.ExclusionPath -join '; ')"
"ExclusionProcess: $($mp.ExclusionProcess -join '; ')"
"ExclusionExtension: $($mp.ExclusionExtension -join '; ')"
"ThreatIDDefaultAction (6 = PERMITIR): " + (($mp.ThreatIDDefaultAction_Ids | ForEach-Object -Begin { $k = 0 } -Process { "$_=$($mp.ThreatIDDefaultAction_Actions[$k])"; $k++ }) -join ', ')
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
if (Test-Path $pol) { Get-ChildItem $pol -Recurse | Where-Object { $_.Property } | ForEach-Object { $k = $_; $k.Property | ForEach-Object { "POLÍTICA $($k.Name -replace '^.*Windows Defender', '')\$_ = $($k.GetValue($_))" } }; (Get-Item $pol).Property | ForEach-Object { "POLÍTICA (raíz) $_ = $((Get-Item $pol).GetValue($_))" } }
"--- Cambios de configuración relevantes (evento 5007) desde $($Desde.ToString('dd/MM/yyyy')) ---"
Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 5007; StartTime = $Desde } | Sort-Object TimeCreated | ForEach-Object {
  $x = [xml]$_.ToXml(); $d = @{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
  if ("$($d['New Value'])$($d['Old Value'])" -match 'Exclusions|ThreatIDDefaultAction|Disable') { "{0:dd/MM/yyyy HH:mm:ss} | ANTES: {1} | AHORA: {2}" -f $_.TimeCreated, $d['Old Value'], $d['New Value'] }
} | Select-Object -Last 120
"--- Detecciones (1116/1117) desde $($Desde.ToString('dd/MM/yyyy')) ---"
Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117; StartTime = $Desde } | Sort-Object TimeCreated | ForEach-Object {
  $x = [xml]$_.ToXml(); $d = @{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
  "{0:dd/MM/yyyy HH:mm} [{1}] {2} | {3} | {4}" -f $_.TimeCreated, $_.Id, $d['Threat Name'], $d['Action Name'], $d['Path']
} | Select-Object -Last 60

Section 'CARPETAS CON NOMBRE ALEATORIO (actuales e históricas en VirtualStore)'
$dirs = 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData', 'C:\Windows\Temp', "$env:LOCALAPPDATA\Temp", "$env:LOCALAPPDATA\VirtualStore\Program Files (x86)", "$env:LOCALAPPDATA\VirtualStore\Program Files"
Get-ChildItem $dirs -Directory -Force | Where-Object { EsAleatorio $_.Name } | Sort-Object CreationTime | ForEach-Object {
  $files = (Get-ChildItem $_.FullName -Recurse -File -Force | ForEach-Object { "$($_.Name) ($($_.Length) B)" }) -join ', '
  "{0:dd/MM/yyyy HH:mm} | {1} | {2}" -f $_.CreationTime, $_.FullName, $(if ($files) { $files } else { '(vacía)' })
}

Section 'CARPETAS CON PERMISO DENY PARA TODOS (táctica anti-borrado; se omiten las uniones de Windows)'
$cand = Get-ChildItem 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData', "$env:LOCALAPPDATA", "$env:APPDATA", 'C:\Windows\Temp', "$env:LOCALAPPDATA\Temp" -Directory -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }
$cand += Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Extensions", "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Extensions", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Extensions" -Directory -Force
$cand | Where-Object { (Get-Acl $_.FullName).Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference -match 'Todos|Everyone' } } | ForEach-Object { "{0} | dueño {1} | creada {2}" -f $_.FullName, (Get-Acl $_.FullName).Owner, $_.CreationTime }

Section 'PROGRAMAS INSTALADOS SOSPECHOSOS (sin fabricante, desinstalador rundll32 o recientes)'
Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object { $_.DisplayName -and ((-not $_.Publisher -and -not $_.SystemComponent) -or $_.UninstallString -match 'rundll32' -or ($_.InstallDate -and $_.InstallDate -ge $Desde.ToString('yyyyMMdd'))) } |
  ForEach-Object { "{0} | v{1} | Fabricante: {2} | Instalado: {3} | Desinstalar: {4}" -f $_.DisplayName, $_.DisplayVersion, $_.Publisher, $_.InstallDate, $_.UninstallString }

Section 'EXTENSIONES DE NAVEGADOR (todos los perfiles)'
$roots = @{ 'Edge' = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; 'Chrome' = "$env:LOCALAPPDATA\Google\Chrome\User Data"; 'Brave' = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
foreach ($b in $roots.Keys) {
  Get-ChildItem $roots[$b] -Directory | ForEach-Object {
    $prof = $_.Name
    Get-ChildItem (Join-Path $_.FullName 'Extensions') -Directory | Where-Object Name -ne 'Temp' | ForEach-Object {
      $m = Get-ChildItem $_.FullName -Recurse -Filter manifest.json | Select-Object -First 1
      $j = if ($m) { try { Get-Content $m.FullName -Raw | ConvertFrom-Json } catch { $null } }
      $n = $j.name
      if ($n -like '__MSG_*' -and $m) { $key = $n -replace '^__MSG_|__$'; foreach ($loc in 'es', 'en', 'en_US') { $lf = Join-Path $m.Directory.FullName "_locales\$loc\messages.json"; if (Test-Path $lf) { try { $n = (Get-Content $lf -Raw | ConvertFrom-Json).$key.message; break } catch {} } } }
      $perm = (@($j.permissions) + @($j.host_permissions)) -join ','
      $riesgo = if ($perm -match '<all_urls>|\*://\*/\*|http://\*/\*|https://\*/\*' -and $perm -match 'cookies|webRequest|management') { '  <<< permisos amplios' } else { '' }
      "{0}/{1} | {2} | {3} v{4} | creada {5}{6}`n    perms: {7}" -f $b, $prof, $_.Name, $n, $j.version, $_.CreationTime, $riesgo, $perm
    }
  }
}

Section 'POLÍTICAS DE NAVEGADORES (causan "Administrado por su organización")'
'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge', 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKCU:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' | ForEach-Object {
  if (Test-Path $_) { $_; $r = Get-Item $_; $r.Property | ForEach-Object { "  $_ = $($r.GetValue($_))" }; Get-ChildItem $_ -Recurse | ForEach-Object { $k = $_; $k.Property | ForEach-Object { "  $($k.PSChildName)\$_ = $($k.GetValue($_))" } } }
}

Section 'HOSTS, PROXY Y DNS'
Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -notmatch '^\s*(#|$)' }
$ie = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
"ProxyEnable: $($ie.ProxyEnable) | ProxyServer: $($ie.ProxyServer) | AutoConfigURL: $($ie.AutoConfigURL)"
"WinHTTP: " + ((netsh winhttp show proxy) -join ' ')
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | ForEach-Object { "DNS $($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" }

Section "CERTIFICADOS RAÍZ AGREGADOS DESDE $($Desde.ToString('dd/MM/yyyy')) (posible intercepción HTTPS)"
Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | Where-Object { $_.NotBefore -ge $Desde } | ForEach-Object { "{0} | {1} | desde {2} | {3}" -f ($_.PSParentPath -replace '.*::'), $_.Subject, $_.NotBefore, $_.Thumbprint }

Section "EJECUTABLES Y DLL NO FIRMADOS CREADOS DESDE $($Desde.ToString('dd/MM/yyyy')) (se omiten WindowsApps y Windows Kits)"
Get-ChildItem 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData' -Recurse -Depth 2 -Include *.exe, *.dll, *.sys -Force |
  Where-Object { $_.CreationTime -ge $Desde -and $_.FullName -notmatch '\\WindowsApps\\|\\Windows Kits\\|\\Reference Assemblies\\' } |
  ForEach-Object { $s = Sig $_.FullName; if ($s -notmatch '^OK:') { "{0:dd/MM/yyyy HH:mm} | {1} | {2:N0} B | {3}" -f $_.CreationTime, $s, $_.Length, $_.FullName } }

Section 'CUENTAS LOCALES Y ADMINISTRADORES'
Get-LocalUser | ForEach-Object { "{0} | habilitada={1} | últ. inicio={2}" -f $_.Name, $_.Enabled, $_.LastLogon }
Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { "Admin: $($_.Name) ($($_.PrincipalSource))" }

Section 'FIN'
} *>&1 | Out-File -FilePath $Salida -Encoding utf8 -Width 400
"Reporte generado: $Salida"
