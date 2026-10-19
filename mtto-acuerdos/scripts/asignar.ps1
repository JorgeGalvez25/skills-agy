param(
  [Parameter(Mandatory=$true)][string]$Carpeta,   # carpeta de la versión
  [Parameter(Mandatory=$true)][string]$Casos,     # casos.json de extraer.ps1 (se actualiza la columna tester)
  [Parameter(Mandatory=$true)][string]$Acuerdos,  # acuerdos.json con G (complejidad) e I (módulos)
  [string]$Versiones                              # carpeta con todas las versiones (default: la que contiene $Carpeta)
)
# Asigna tester a los casos que no lo tienen:
#  1. Nadie prueba sus propios casos.
#  2. Cantidad equitativa: diferencia máxima de 1 caso entre testers.
#  3. Alta/Media primero, al tester con menos puntos pesados (Alta=3, Media=2).
#  4. Baja por afinidad: quién ha probado ese módulo en versiones anteriores, repartiendo los casos de cada desarrollador.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
$utf8 = New-Object Text.UTF8Encoding $false
$version = [version](Split-Path $Carpeta -Leaf)

# --- Historial (caché en references\historial.csv; solo versiones con prueba cruzada, >= 4.3.7.0) ---
$cache = Join-Path (Split-Path $PSScriptRoot -Parent) 'references\historial.csv'
$hist = @(if (Test-Path $cache) { Import-Csv $cache -Encoding UTF8 })
$enCache = @($hist | ForEach-Object version | Select-Object -Unique)
if (-not $Versiones) { $Versiones = Split-Path $Carpeta -Parent }
$faltan = Get-ChildItem $Versiones -Directory | Where-Object {
  $_.Name -match '^\d+(\.\d+){3}$' -and [version]$_.Name -ge [version]'4.3.7.0' -and [version]$_.Name -lt $version -and
  $_.Name -notin $enCache -and (Test-Path (Join-Path $_.FullName 'Acuerdos_IGAS_RSP.xlsx')) }
if ($faltan) {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try {
    foreach ($d in $faltan) {
      $wb = $xl.Workbooks.Open((Join-Path $d.FullName 'Acuerdos_IGAS_RSP.xlsx'), 0, $true); $ws = $wb.Worksheets.Item(1)
      for ($r = 2; $r -le $ws.UsedRange.Rows.Count; $r++) {
        $id = $ws.Cells.Item($r, 1).Text.Trim(); if (-not $id) { continue }
        $hist += [pscustomobject]@{ version = $d.Name; id = $id; resp = (Normalize-Persona $ws.Cells.Item($r, 5).Text)
          tester = (Normalize-Persona $ws.Cells.Item($r, 6).Text); complejidad = $ws.Cells.Item($r, 7).Text; modulos = ($ws.Cells.Item($r, 9).Text -replace "`n", ' / ') }
      }
      $wb.Close($false)
    }
  } finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
  $hist | Export-Csv $cache -NoTypeInformation -Encoding UTF8
}

# Afinidad: proporción de veces que cada tester probó cada módulo
$cuenta = @{}; $total = @{}
foreach ($h in $hist) {
  if ($h.tester -eq $h.resp) { continue }
  foreach ($m in Split-Modulos $h.modulos) {
    $k = Get-ClaveModulo $m
    $total[$k] = 1 + [int]$total[$k]
    $cuenta["$($h.tester)|$k"] = 1 + [int]$cuenta["$($h.tester)|$k"]
  }
}
function Get-Afinidad($t, $mods) {
  $ms = @($mods | ForEach-Object { Get-ClaveModulo $_ } | Select-Object -Unique)
  if (-not $ms) { return 0.0 }
  $s = 0.0; foreach ($k in $ms) { if ($total[$k]) { $s += [double][int]$cuenta["$t|$k"] / $total[$k] } }
  return $s / $ms.Count
}

# --- Asignación ---
$lista = Read-JsonArray $Casos
$acu = @{}; foreach ($a in Read-JsonArray $Acuerdos) { $acu[$a.id] = $a }
foreach ($c in $lista) {
  $c.resp = Normalize-Persona $c.resp
  if ($c.tester) { $c.tester = Normalize-Persona $c.tester }
  $a = $acu[$c.id]
  $c | Add-Member -Force NoteProperty G $(if ($a) { $a.G } else { '' })
  $c | Add-Member -Force NoteProperty mods $(if ($a) { Split-Modulos $a.I } else { @() })
}
$testers = $Equipo
$n = $lista.Count; $base = [math]::Floor($n / $testers.Count); $extra = $n % $testers.Count
$cnt = @{}; $pts = @{}; $pesados = @{}; $pares = @{}
foreach ($t in $testers) { $cnt[$t] = 0; $pts[$t] = 0; $pesados[$t] = 0 }
function Add-Carga($c, $t) {
  $script:cnt[$t]++; $w = Get-PesoComplejidad $c.G; $script:pts[$t] += $w
  if ($w -gt 1) { $script:pesados[$t] += $w }
  $script:pares["$($c.resp)|$t"] = 1 + [int]$script:pares["$($c.resp)|$t"]
}
foreach ($c in $lista | Where-Object { $_.tester }) { if ($cnt.ContainsKey($c.tester)) { Add-Carga $c $c.tester } }

$porResp = @{}; foreach ($c in $lista) { $porResp[$c.resp] = 1 + [int]$porResp[$c.resp] }
$pendientes = $lista | Where-Object { -not $_.tester } | Sort-Object @{ e = { -(Get-PesoComplejidad $_.G) } }, @{ e = { -$porResp[$_.resp] } }, @{ e = { [int]($_.id -replace '\D', '') } }
$motivos = @{}
foreach ($c in $pendientes) {
  $llenos = @($testers | Where-Object { $cnt[$_] -gt $base }).Count
  $eleg = @($testers | Where-Object { $_ -ne $c.resp -and ($cnt[$_] -lt $base -or ($cnt[$_] -eq $base -and $llenos -lt $extra)) })
  $relajado = $false
  if (-not $eleg) { $eleg = @($testers | Where-Object { $_ -ne $c.resp }); $relajado = $true }
  $w = Get-PesoComplejidad $c.G
  $mejor = $eleg | Sort-Object `
    @{ e = { if ($w -gt 1) { $pesados[$_] } else { 0 } } }, `
    @{ e = { -[math]::Round((Get-Afinidad $_ $c.mods) - 0.25 * [int]$pares["$($c.resp)|$_"], 3) } }, `
    @{ e = { $cnt[$_] } }, @{ e = { $pts[$_] } }, @{ e = { $_ } } | Select-Object -First 1
  $c.tester = $mejor
  $motivos[$c.id] = ('afinidad {0:N2}' -f (Get-Afinidad $mejor $c.mods)) + $(if ($w -gt 1) { ", pesados previos $($pesados[$mejor])" } else { '' }) + $(if ($relajado) { ', SIN CUPO (se relajó la equidad)' } else { '' })
  Add-Carga $c $mejor
}

foreach ($c in $lista) { $c.PSObject.Properties.Remove('G'); $c.PSObject.Properties.Remove('mods') }
[IO.File]::WriteAllText($Casos, (ConvertTo-Json -InputObject $lista -Depth 3), $utf8)

Write-Output "Historial: $($hist.Count) casos de $(@($hist | ForEach-Object version | Select-Object -Unique).Count) versiones"
Write-Output ''
Write-Output 'ID | Responsable | Complejidad | Tester | Motivo'
foreach ($c in $lista) { Write-Output ("{0} | {1} | {2} | {3} | {4}" -f $c.id, $c.resp, $(if ($acu[$c.id]) { $acu[$c.id].G } else { '(sin informe)' }), $c.tester, $(if ($motivos[$c.id]) { $motivos[$c.id] } else { 'ya asignado' })) }
Write-Output ''
Write-Output 'Tester | Casos | Alta | Media | Baja | Puntos'
foreach ($t in $testers) {
  $mios = @($lista | Where-Object { $_.tester -eq $t })
  $g = $mios | ForEach-Object { if ($acu[$_.id]) { $acu[$_.id].G } else { '' } }
  Write-Output ("{0} | {1} | {2} | {3} | {4} | {5}" -f $t, $mios.Count, @($g | Where-Object { $_ -eq 'Alta' }).Count, @($g | Where-Object { $_ -eq 'Media' }).Count, @($g | Where-Object { $_ -notin 'Alta', 'Media' }).Count, $pts[$t])
}
