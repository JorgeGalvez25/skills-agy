# Vigila durante N minutos los procesos que se inician (sustituye a grabar el Administrador de tareas).
# Atrapa procesos intermitentes, como scripts lanzados por tareas programadas, que una foto instantánea no ve.
# Con administrador usa el evento Win32_ProcessStartTrace (atrapa hasta los de milisegundos);
# sin administrador sondea Win32_Process cada -Intervalo segundos.
# Uso: vigilar-procesos.ps1 [-Minutos 10] [-Salida <archivo.txt>] [-Intervalo 1] [-Todos]
#   -Todos: lista todos los procesos nuevos; por defecto solo se marcan los sospechosos y se resume el resto.
param([double]$Minutos = 10, [string]$Salida, [double]$Intervalo = 1, [switch]$Todos)
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$patron = '^(wscript|cscript|mshta|forfiles|rundll32|regsvr32|powershell|pwsh|cmd|bitsadmin|certutil|curl|schtasks|msiexec)\.exe$'
# Ruta rara: Temp, Roaming o Public, o una carpeta con nombre aleatorio (p. ej. GbcrGbfJBMUn) bajo Program Files o ProgramData.
function RutaRara($r) {
  if (-not $r) { return $false }
  if ($r -match '\\(Temp|AppData\\Roaming|Users\\Public)\\') { return $true }
  if ($r -match '^[A-Z]:\\(Program Files( \(x86\))?|ProgramData)\\([^\\]+)\\') { $c = $Matches[3]; return ($c -cmatch '^[A-Za-z0-9]{8,22}$' -and $c -cmatch '[a-z][A-Z].*[a-z][A-Z]' -and $c -notmatch 'Microsoft|Windows|Software|Service|Update|NuGet') }
  $false
}
function Corto($s) { if ($s.Length -gt 300) { $s.Substring(0, 300) + '…' } else { $s } }
$global:VigNuevos = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$nombres = @{}
function Instantanea { Get-CimInstance Win32_Process | ForEach-Object { $nombres[[int]$_.ProcessId] = $_.Name; $_ } }
function Registrar($proc, $pidN, $nombre, $padre) {
  [void]$global:VigNuevos.Add([pscustomobject]@{ Hora = Get-Date; PID = $pidN; Nombre = $nombre; PadrePID = $padre; Comando = $proc.CommandLine; Ruta = $proc.ExecutablePath })
}

$inicial = Instantanea
$vistos = @{}; $inicial | ForEach-Object { $vistos["$($_.ProcessId)|$($_.CreationDate)"] = 1 }
$modo = if ($esAdmin) { 'evento Win32_ProcessStartTrace' } else { "sondeo cada $Intervalo s (sin administrador: se pierden procesos muy breves y algunas líneas de comando)" }
$cab = "Vigilancia de procesos | inicio $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') | $Minutos min | modo: $modo"
$cab
'Sospechosos ya en ejecución al empezar:'
$inicial | Where-Object { $_.Name -match '^(wscript|cscript|mshta|forfiles)\.exe$' -or (RutaRara $_.ExecutablePath) } | ForEach-Object { "  PID $($_.ProcessId) $($_.Name) | $(Corto $_.CommandLine)" }

if ($esAdmin) {
  Register-CimIndicationEvent -ClassName Win32_ProcessStartTrace -SourceIdentifier VigProc -Action {
    $n = $Event.SourceEventArgs.NewEvent
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($n.ProcessID)" -ErrorAction SilentlyContinue
    [void]$global:VigNuevos.Add([pscustomobject]@{ Hora = Get-Date; PID = [int]$n.ProcessID; Nombre = $n.ProcessName; PadrePID = [int]$n.ParentProcessID; Comando = $p.CommandLine; Ruta = $p.ExecutablePath })
  } | Out-Null
}
$fin = (Get-Date).AddMinutes($Minutos)
try {
  while ((Get-Date) -lt $fin) {
    Start-Sleep -Milliseconds ([int]($Intervalo * 1000))
    $actual = Instantanea   # también refresca los nombres de los padres
    if (-not $esAdmin) {
      foreach ($p in $actual) { $k = "$($p.ProcessId)|$($p.CreationDate)"; if (-not $vistos[$k]) { $vistos[$k] = 1; Registrar $p ([int]$p.ProcessId) $p.Name ([int]$p.ParentProcessId) } }
    }
  }
} finally { if ($esAdmin) { Unregister-Event -SourceIdentifier VigProc -ErrorAction SilentlyContinue; Remove-Job -Name VigProc -Force -ErrorAction SilentlyContinue } }

# Servicio Schedule: si el padre es ese svchost, el proceso lo lanzó una tarea programada.
$pidSchedule = (Get-CimInstance Win32_Service -Filter "Name='Schedule'").ProcessId
# Árbol de procesos con los de la instantánea inicial y los nuevos, para resolver padres de vida corta.
$padres = @{}; $inicial | ForEach-Object { $padres[[int]$_.ProcessId] = [int]$_.ParentProcessId }
foreach ($r in $global:VigNuevos) { $nombres[$r.PID] = $r.Nombre; $padres[$r.PID] = $r.PadrePID }
# Se omite lo que desciende de Claude Code o de esta vigilancia: son los comandos de la propia sesión.
function EsPropio($id) { $n = 0; while ($id -and $n++ -lt 15) { if ($id -eq $PID -or $nombres[$id] -match '^(claude|gk)\.exe$') { return $true }; $id = $padres[$id] }; $false }
$propios = @($global:VigNuevos | Where-Object { EsPropio $_.PadrePID })
$lineas = foreach ($r in $global:VigNuevos | Where-Object { $propios -notcontains $_ }) {
  if ($r.Nombre -eq 'conhost.exe' -and -not $Todos) { continue }
  $padre = if ($nombres.ContainsKey($r.PadrePID)) { $nombres[$r.PadrePID] } else { '?' }
  if ($r.PadrePID -eq $pidSchedule) { $padre = 'svchost (Programador de tareas)' }
  $sosp = $r.Nombre -match $patron -or (RutaRara $r.Ruta) -or $padre -match 'Programador|wscript|cscript|mshta|forfiles'
  if ($sosp -or $Todos) { "{0} {1} PID {2,-6} {3,-22} <- {4} ({5})`n    {6}" -f $r.Hora.ToString('HH:mm:ss'), $(if ($sosp) { '<<<' } else { '   ' }), $r.PID, $r.Nombre, $padre, $r.PadrePID, (Corto $(if ($r.Comando) { $r.Comando } else { $r.Ruta })) }
}
$res = @($cab, "`nProcesos nuevos: $($global:VigNuevos.Count) (de la propia sesión de Claude Code, omitidos: $($propios.Count)) | marcados (<<<): $(@($lineas | Where-Object { $_ -match '<<<' }).Count)") + $lineas +
  "`nResumen por nombre (sin la sesión de Claude Code):" + ($global:VigNuevos | Where-Object { $propios -notcontains $_ } | Group-Object Nombre | Sort-Object Count -Descending | ForEach-Object { "  {0,4} x {1}" -f $_.Count, $_.Name })
$res | Select-Object -Skip 1
if ($Salida) { $res | Out-File -FilePath $Salida -Encoding utf8; "Guardado en $Salida" }
