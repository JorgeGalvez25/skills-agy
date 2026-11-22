# Actualiza la caché de correos de casos TT (solo lectura de Outlook; ver correos.md)
#   powershell -File correos.ps1 [-Desde dd/mm/aaaa]
param([string]$Desde)
$ErrorActionPreference = 'Stop'
$cuenta = 'jorgegalvez@igas.com.mx'
$ruta = if ($env:MTTO_CORREOS) { $env:MTTO_CORREOS } else { 'C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\correos_mtto.json' }
$ci = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)

$cache = $null
if (Test-Path $ruta) { $cache = [IO.File]::ReadAllText($ruta, $utf8) | ConvertFrom-Json }
if ($Desde) { $ini = [datetime]::ParseExact($Desde, 'dd/MM/yyyy', $ci) }
elseif ($cache -and $cache.correos.Count) { $ini = ([datetime]::ParseExact(@($cache.correos)[-1].fecha, 'yyyy-MM-dd HH:mm', $ci)).Date.AddDays(-3) }
else { $ini = (Get-Date).Date.AddDays(-120) }
$iniTxt = $ini.ToString('g')   # Restrict usa el formato de fecha regional del equipo

$rxTT = 'TT[\s_-]?\d{5,6}'
$normTT = { param($s) 'TT' + ($s -replace '\D', '') }
$sinAcentos = { param($s) (($s.Normalize([Text.NormalizationForm]::FormD)) -replace '\p{Mn}', '').ToLower() }

function Get-Tipo($a) {
  $x = (& $sinAcentos ($a -replace '^\s*((re|rv|fw|fwd|resp)\s*:\s*)+', '')).Trim()
  if ($x -match '^\d{8}_|std-report|report[ae] (de )?caso|reporte caso|solicitud de apoyo') { return 'alta-soporte' }
  if ($x -match 'revision de fallo|apoyo a soporte|\baca\b') { return 'asignacion' }
  if ($x -match 'solicitud de (cambio|mejora)|propuesta tecnica|estima[cs]ion') { return 'solicitud' }
  foreach ($t in 'entrega', 'estatus', 'rsp', 'cec', 'ldp') { if ($x -match "\b$t\b") { return $t } }
  'otro'
}

# Texto propio: antes del primer bloque citado
function Get-Propio($c) {
  $m = [regex]::Match($c, '(?im)^\s*(De:|From:|-----\s*Original|_{8,}|Enviado el:)')
  if ($m.Success) { $c.Substring(0, $m.Index) } else { $c }
}

function Get-Relaciones($tipo, $tt, $cuerpo, $asunto) {
  $r = @()
  if ($tipo -eq 'asignacion') {
    $m = [regex]::Match($cuerpo, "(?i)CASO SOPORTE:\s*($rxTT)")
    if (-not $m.Success) { $m = [regex]::Match($cuerpo, "(?i)(?:\d{8}_\s?|STD-ReporteDeCaso_)($rxTT)") }
    if ($m.Success) { $r += @{ tt = (& $normTT $m.Groups[1].Value); tipo = 'soporte'; evidencia = $m.Value.Trim() } }
  } elseif ($tipo -eq 'cec') {
    # Primer TT del texto distinto al del asunto
    foreach ($m in [regex]::Matches($cuerpo, "(?i)(atender[aá]|atendid[oa]|atiende|cerrar[aá]|registrado|mediante)\b[\s\S]{0,60}?($rxTT)")) {
      $otro = & $normTT $m.Groups[2].Value
      if ($otro -ne $tt) { $r += @{ tt = $otro; tipo = 'atiende-con'; evidencia = $m.Value.Trim() }; break }
    }
  } elseif ($tipo -eq 'entrega') {
    $m = [regex]::Match($cuerpo, '(?i)([\\]{2}192\.168\.0\.2[\\]|WorkDir)[^\r\n]*?[\\](TT\d{5,6})(?![\w-])')
    if ($m.Success) { $r += @{ tt = $m.Groups[2].Value.ToUpper(); tipo = 'anomalia'; evidencia = $m.Value.Trim() } }
  }
  @($r | Where-Object { $_.tt -ne $tt })
}

$smtp = @{}
function Get-Smtp($entrada) {
  $dir = $entrada.Address
  if ($smtp.ContainsKey($dir)) { return $smtp[$dir] }
  $v = $dir
  if ($entrada.AddressEntry -ne $null -and $dir -match '^/') {
    try { $v = $entrada.AddressEntry.GetExchangeUser().PrimarySmtpAddress } catch { }
  }
  $smtp[$dir] = "$v".ToLower()
  $smtp[$dir]
}

$ol = New-Object -ComObject Outlook.Application
$almacen = $ol.Session.Stores | Where-Object { $_.DisplayName -eq $cuenta } | Select-Object -First 1
if (-not $almacen) { throw "No se encontró el store $cuenta en Outlook." }

$nuevos = @(); $leidos = 0
foreach ($c in @(@{ n = 6; carpeta = 'entrada'; campo = 'ReceivedTime' }, @{ n = 5; carpeta = 'enviados'; campo = 'SentOn' })) {
  $items = $almacen.GetDefaultFolder($c.n).Items.Restrict("[$($c.campo)] >= '$iniTxt'")
  foreach ($it in $items) {
    if ($it.Class -ne 43) { continue }
    $asunto = "$($it.Subject)"
    $m = [regex]::Match($asunto, $rxTT, 'IgnoreCase')
    if (-not $m.Success) { continue }
    $fecha = if ($c.campo -eq 'SentOn') { $it.SentOn } else { $it.ReceivedTime }
    if ($fecha -lt $ini) { continue }
    $leidos++
    $tipo = Get-Tipo $asunto
    $tt = & $normTT $m.Value
    $propio = Get-Propio "$($it.Body)"
    if ($c.carpeta -eq 'enviados') { $de = $cuenta } else { $de = if ($it.SenderEmailType -eq 'EX') { try { "$($it.Sender.GetExchangeUser().PrimarySmtpAddress)".ToLower() } catch { "$($it.SenderEmailAddress)".ToLower() } } else { "$($it.SenderEmailAddress)".ToLower() } }
    $para = @(); foreach ($d in $it.Recipients) { if ($d.Type -le 2) { $para += (Get-Smtp $d) } }
    $nuevos += [ordered]@{
      id = $it.EntryID; fecha = $fecha.ToString('yyyy-MM-dd HH:mm', $ci); carpeta = $c.carpeta
      de = $de; deNombre = "$($it.SenderName)"; para = @($para); asunto = $asunto
      respuesta = [bool]($asunto -match '^\s*(RE|RV|FW|FWD|RESP)\s*:'); tipo = $tipo; tt = $tt
      relaciones = @(Get-Relaciones $tipo $tt $propio $asunto)
      extracto = (($propio -replace '\s+', ' ').Trim() | ForEach-Object { $_.Substring(0, [Math]::Min(400, $_.Length)) })
    }
  }
}

$iniFecha = $ini.ToString('yyyy-MM-dd', $ci)
$previos = if ($cache) { @($cache.correos | Where-Object { $_.fecha -lt $iniFecha }) } else { @() }
$todos = @(@($previos) + @($nuevos) | Group-Object { $_.id } | ForEach-Object { $_.Group[0] } | Sort-Object { $_.fecha })
$desdeCache = if ($cache -and $cache.desde -lt $iniFecha) { $cache.desde } else { $iniFecha }
$salida = [ordered]@{ actualizado = (Get-Date).ToString('yyyy-MM-dd HH:mm', $ci); desde = $desdeCache; correos = @($todos) }
New-Item -ItemType Directory -Force (Split-Path $ruta) | Out-Null
[IO.File]::WriteAllText($ruta, ($salida | ConvertTo-Json -Depth 6), $utf8)

$rel = @($todos | ForEach-Object { $_.relaciones } | Where-Object { $_ } | Group-Object { $_.tipo } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
"Leído desde ${iniFecha}: $leidos correos; total en caché: $($todos.Count); relaciones: $rel"
