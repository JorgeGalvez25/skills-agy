<#
.SYNOPSIS
  Genera el Informe de Correcciones / Informe de Cambios (distribuidores) a partir de la
  plantilla oficial, llenando solo sus campos. La plantilla NO se modifica.

.DESCRIPTION
  Usa Word (COM) con Documents.Add(plantilla): crea un documento nuevo basado en la plantilla,
  llena encabezado, tabla principal, fecha, complejidad, casillas de BD, configuraciones
  especiales (con scripts .sql incrustados como icono) y el detalle por opción de menú.
  Las capturas de pantalla quedan como marcadores [CAPTURA: ...] resaltados en amarillo
  para que el desarrollador las sustituya.

.PARAMETER Datos
  Ruta del JSON con el contenido (ver referencias/informe.ejemplo.json).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Datos,
  [string]$Plantillas,
  [switch]$Visible
)
$ErrorActionPreference = 'Stop'
if (-not $Plantillas) {
  # $PSScriptRoot puede llegar vacío según cómo se invoque (p. ej. powershell.exe -File desde Bash).
  $dirScript = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $Plantillas = Join-Path (Split-Path $dirScript -Parent) 'plantillas'
}

function Normalize([string]$s) {
  if ($null -eq $s) { return '' }
  $n = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) } }
  return ($sb.ToString() -replace '[\s\.\r\a\x07]+', ' ').Trim().ToUpper()
}

function Find-InRange($Range, [string]$Text) {
  $r = $Range.Duplicate
  $f = $r.Find
  $f.ClearFormatting()
  $f.Text = $Text; $f.Forward = $true; $f.Wrap = 0; $f.MatchWildcards = $false; $f.MatchCase = $false
  if ($f.Execute()) { return $r } else { return $null }
}

function Join-Lines($v) { if ($null -eq $v) { return '' }; return ((@($v) | ForEach-Object { "$_" }) -join "`r") }

$d = Get-Content $Datos -Raw -Encoding UTF8 | ConvertFrom-Json
$esCambio = (Normalize $d.tipo) -like 'CAMBIO*'
# Toda ruta que se pasa a Word debe ser [string]: el PSObject que devuelve Join-Path cuelga a Word (SaveAs2).
[string]$plantilla = if ($esCambio) { Join-Path $Plantillas 'STD-InformeDeCambios.dotx.docx' } else { Join-Path $Plantillas 'STD-InformeDeCorrecciones.dotx' }
if (-not (Test-Path $plantilla)) { throw "No se encontró la plantilla: $plantilla" }
if (-not $d.archivoSalida) { throw 'El JSON debe indicar archivoSalida.' }
if (Test-Path $d.archivoSalida) { throw "Ya existe $($d.archivoSalida). Bórrelo o use otro nombre (no se sobrescribe)." }
New-Item -ItemType Directory -Force -Path (Split-Path $d.archivoSalida -Parent) | Out-Null

$word = New-Object -ComObject Word.Application
$word.Visible = [bool]$Visible
$word.DisplayAlerts = 0
$pendientes = New-Object System.Collections.Generic.List[string]
try {
  Write-Verbose "Abriendo plantilla $plantilla"
  $doc = $word.Documents.Add($plantilla)

  # ---------- Encabezado: Cliente
  Write-Verbose "Encabezado: Cliente"
  # Se recorre párrafo por párrafo (Find sobre encabezados inexistentes puede quedarse girando).
  foreach ($sec in $doc.Sections) {
    foreach ($idx in 1, 2, 3) {
      $h = $sec.Headers.Item($idx)
      if (-not $h.Exists) { continue }
      foreach ($p in $h.Range.Paragraphs) {
        $pt = $p.Range.Text
        $pos = $pt.IndexOf('<Nombre del Cliente>')
        if ($pos -ge 0) {
          $r = $p.Range.Duplicate
          $r.SetRange($p.Range.Start + $pos, $p.Range.Start + $pos + '<Nombre del Cliente>'.Length)
          if ($r.Text -eq '<Nombre del Cliente>') { $r.Text = "$($d.cliente)" }
          else { $pendientes.Add('No se pudo colocar el Cliente en el encabezado; llénelo a mano.') }
        }
      }
    }
  }

  # ---------- Tabla principal
  Write-Verbose "Tabla principal"
  $t = $doc.Tables.Item(1)
  $cells = @(); foreach ($c in $t.Range.Cells) { $cells += $c }
  $filaModHeader = $null; $filaIdVtiger = $null
  for ($i = 0; $i -lt $cells.Count; $i++) {
    $lbl = Normalize $cells[$i].Range.Text
    $next = if ($i + 1 -lt $cells.Count) { $cells[$i + 1] } else { $null }
    switch ($lbl) {
      'VERSION'              { $next.Range.Text = "$($d.version)" }
      'ANTECEDENTE'          { $next.Range.Text = (Join-Lines $d.antecedente) }
      'DESCRIPCION GENERAL'  { $next.Range.Text = (Join-Lines $d.descripcionGeneral) }
      'MODULOS AFECTADOS'    { $filaModHeader = $cells[$i].RowIndex }
      'ID VTIGER'            { $next.Range.Text = "$($d.idVtiger)"; $filaIdVtiger = $cells[$i].RowIndex }
      'AUTOR'                { $next.Range.Text = "$($d.autor)" }
    }
  }
  # Módulos: celdas de la columna 1 entre el encabezado y la fila de ID VTiger (7 renglones numerados)
  $celdasMod = @($cells | Where-Object { $_.RowIndex -gt $filaModHeader -and $_.RowIndex -lt $filaIdVtiger -and $_.ColumnIndex -eq 1 })
  $mods = @($d.modulos)
  for ($i = 0; $i -lt $celdasMod.Count; $i++) {
    if ($i -lt $mods.Count) {
      $txt = if ($i -eq $celdasMod.Count - 1 -and $mods.Count -gt $celdasMod.Count) { ($mods[$i..($mods.Count - 1)]) -join ', ' } else { $mods[$i] }
      $celdasMod[$i].Range.Text = "$txt"
      # Las celdas 2..7 de la plantilla traen otro formato de carácter; se iguala al de la celda 1.
      $f0 = $celdasMod[0].Range.Font; $fi = $celdasMod[$i].Range.Font
      $fi.Name = 'Segoe UI'; $fi.Size = 10; $fi.Bold = $false; $fi.Italic = $false
    }
  }

  # ---------- Controles de contenido: Fecha y Complejidad
  Write-Verbose "Controles de contenido: Fecha y Complejidad"
  foreach ($cc in $doc.ContentControls) {
    if ($cc.Type -eq 6) { $cc.Range.Text = "$($d.fecha)" }                       # wdContentControlDate
    elseif ($cc.Type -eq 4 -or $cc.Title -eq 'Complejidad') {                     # wdContentControlDropdownList
      $ok = $false
      foreach ($e in $cc.DropdownListEntries) { if ((Normalize $e.Text) -eq (Normalize $d.complejidad)) { $e.Select(); $ok = $true } }
      if (-not $ok) { $pendientes.Add("Complejidad '$($d.complejidad)' no válida (Baja/Media/Alta).") }
    }
  }

  # ---------- Casillas de Bases de Datos (ActiveX)
  Write-Verbose "Casillas de Bases de Datos (ActiveX)"
  $bdPedidas = @($d.basesDatos | ForEach-Object { Normalize $_ })
  $bdMarcadas = @()
  foreach ($s in $doc.InlineShapes) {
    try { $prog = $s.OLEFormat.ProgID } catch { continue }
    if ($prog -notlike 'Forms.CheckBox*') { continue }
    $o = $s.OLEFormat.Object
    $cap = Normalize $o.Caption
    $marcar = $bdPedidas | Where-Object { $cap -eq $_ -or $cap -eq "BD $_" -or $cap.Replace('BD ', '') -eq $_.Replace('BD ', '') }
    if ($marcar) { $o.Value = $true; $bdMarcadas += $cap }
  }
  foreach ($b in $bdPedidas) { if (-not ($bdMarcadas | Where-Object { $_ -eq $b -or $_ -eq "BD $b" -or $_.Replace('BD ', '') -eq $b.Replace('BD ', '') })) { $pendientes.Add("Base de datos '$b' no existe como casilla en la plantilla.") } }

  # ---------- Configuraciones Especiales
  Write-Verbose "Configuraciones Especiales"
  $r = Find-InRange $doc.Content '<Indicar algunas observaciones para realizar los cambios, por ejemplo: alguna variable, configuraciones previas, etc.>'
  if ($r) {
    $conf = Join-Lines $d.configuracionesEspeciales
    $r.Text = $conf
    $ancla = $r.Paragraphs.Last.Range
    foreach ($sql in @($d.scriptsAdjuntos)) {
      if (-not $sql) { continue }
      if (-not (Test-Path $sql)) { $pendientes.Add("Script no encontrado, no se adjuntó: $sql"); continue }
      $ancla.InsertParagraphAfter()          # el rango se extiende e incluye el párrafo nuevo
      $p = $ancla.Paragraphs.Last.Range
      $pr = $p.Duplicate; $pr.Collapse(1)
      $m = [Type]::Missing
      [void]$doc.InlineShapes.AddOLEObject($m, [string]$sql, $false, $true, $m, $m, [IO.Path]::GetFileName($sql), $pr)
      $ancla = $p
    }
  }

  # ---------- Detalle de Correcciones / Cambios
  Write-Verbose "Detalle de Correcciones / Cambios"
  $pars = @(); foreach ($p in $doc.Paragraphs) { $pars += $p }
  $bloques = @()
  for ($i = 0; $i -lt $pars.Count; $i++) {
    if ((Normalize $pars[$i].Range.Text).StartsWith('OPCION DEL MENU:')) { $bloques += , @($pars[$i..([Math]::Min($i + 4, $pars.Count - 1))]) }
  }
  $detalle = @($d.detalle)
  if ($detalle.Count -gt $bloques.Count -and $bloques.Count -gt 0) {
    $ultimo = $bloques[-1]
    $src = $doc.Range($ultimo[0].Range.Start, $ultimo[4].Range.End)
    for ($k = $bloques.Count; $k -lt $detalle.Count; $k++) {
      $dst = $doc.Range($src.End, $src.End)
      $dst.FormattedText = $src.FormattedText
    }
    $pars = @(); foreach ($p in $doc.Paragraphs) { $pars += $p }
    $bloques = @()
    for ($i = 0; $i -lt $pars.Count; $i++) {
      if ((Normalize $pars[$i].Range.Text).StartsWith('OPCION DEL MENU:')) { $bloques += , @($pars[$i..([Math]::Min($i + 4, $pars.Count - 1))]) }
    }
  }
  # Se procesa de atrás hacia adelante para que los rangos no se desplacen.
  for ($k = $bloques.Count - 1; $k -ge 0; $k--) {
    $b = $bloques[$k]
    if ($k -ge $detalle.Count) { $doc.Range($b[0].Range.Start, $b[4].Range.End).Delete() | Out-Null; continue }
    $item = $detalle[$k]
    # P5 <Incluir pantallas...> y P4 <Configuración...>
    $b[4].Range.Delete() | Out-Null
    if ($item.configuracion) { $r4 = $b[3].Range.Duplicate; $r4.MoveEnd(1, -1) | Out-Null; $r4.Text = (Join-Lines $item.configuracion) } else { $b[3].Range.Delete() | Out-Null }
    # P3 pasos + marcadores de captura
    $lineas = @()
    foreach ($paso in @($item.pasos)) {
      if ($paso -is [string]) { $lineas += $paso; continue }
      if ($paso.texto) { $lineas += "$($paso.texto)" }
      if ($paso.captura) { $lineas += "[CAPTURA: $($paso.captura)]" }
    }
    $r3 = $b[2].Range.Duplicate; $r3.MoveEnd(1, -1) | Out-Null
    $r3.Text = ($lineas -join "`r")
    $r3.Font.Italic = $false
    # P1 opción del menú
    $r1 = Find-InRange $b[0].Range '<Indicar en que opción del menú del sistema se realizó '
    if ($r1) { $r1.MoveEndUntil('>') | Out-Null; $r1.MoveEnd(1, 1) | Out-Null; $r1.Text = "$($item.opcionMenu)" }
  }
  Write-Verbose "Resaltando capturas"
  foreach ($p in $doc.Paragraphs) {
    if ($p.Range.Text.StartsWith('[CAPTURA:')) { $p.Range.HighlightColorIndex = 7 }   # wdYellow
  }

  # ---------- Validación de marcadores sobrantes
  Write-Verbose "Validación de marcadores sobrantes"
  $texto = $doc.Content.Text
  foreach ($m in [regex]::Matches($texto, '<[^<>\r]{4,}>')) { $pendientes.Add("Marcador de plantilla sin llenar: $($m.Value)") }
  $capturas = ([regex]::Matches($texto, '\[CAPTURA:')).Count

  # Word no admite rutas de más de 255 caracteres: se guarda en una ruta corta y se mueve.
  [string]$tmpDoc = Join-Path $env:TEMP ("informe_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.docx')
  Write-Verbose "Guardando $tmpDoc"
  $doc.SaveAs2($tmpDoc, 16)
  Write-Verbose "Cerrando"
  $doc.Close()
  Move-Item -LiteralPath $tmpDoc -Destination $d.archivoSalida
  Write-Host "Documento generado: $($d.archivoSalida)"
  Write-Host "Capturas pendientes de pegar: $capturas"
  foreach ($p in $pendientes) { Write-Warning $p }
} finally {
  $word.Quit()
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
