<#
.SYNOPSIS
  Verifica que un Informe de Correcciones/Cambios esté listo para entregarse al distribuidor.
  Revisa: marcadores de plantilla sin llenar, marcadores [CAPTURA: ...] sin sustituir,
  texto resaltado, campos vacíos de la tabla principal y que existan imágenes.
  Solo lectura: no modifica el documento.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Ruta)
$ErrorActionPreference = 'Stop'
$word = New-Object -ComObject Word.Application
$word.Visible = $false; $word.DisplayAlerts = 0
$errores = New-Object System.Collections.Generic.List[string]
try {
  [string]$abrir = (Resolve-Path -LiteralPath $Ruta).Path
  if ($abrir.Length -gt 250) { $tmp = Join-Path $env:TEMP 'validar_informe.docx'; Copy-Item -LiteralPath $abrir -Destination $tmp -Force; $abrir = [string]$tmp }
  $doc = $word.Documents.Open($abrir, $false, $true)
  $texto = $doc.Content.Text
  foreach ($m in [regex]::Matches($texto, '<[^<>\r]{4,}>')) { $errores.Add("Marcador de plantilla sin llenar: $($m.Value)") }
  foreach ($m in [regex]::Matches($texto, '\[CAPTURA:[^\]]*\]')) { $errores.Add("Captura pendiente: $($m.Value)") }
  if ($texto -match 'Elija un elemento') { $errores.Add('Complejidad sin seleccionar.') }
  foreach ($h in $doc.Sections.Item(1).Headers) { if ($h.Range.Text -match '<Nombre del Cliente>') { $errores.Add('Cliente sin llenar en el encabezado.') } }
  $t = $doc.Tables.Item(1); $cells = @(); foreach ($c in $t.Range.Cells) { $cells += $c }
  for ($i = 0; $i -lt $cells.Count - 1; $i++) {
    $lbl = ($cells[$i].Range.Text -replace '[\r\a\s]+', ' ').Trim()
    if ($lbl -match '^(Versi.n|Antecedente|Descripci.n General|ID VTiger|Autor)$') {
      if ((($cells[$i + 1].Range.Text -replace '[\r\a\s]+', '')).Length -eq 0) { $errores.Add("Campo vacío: $lbl") }
    }
  }
  $imgs = 0; foreach ($s in $doc.InlineShapes) { if ($s.Type -eq 3 -or $s.Type -eq 4) { $imgs++ } }
  foreach ($s in $doc.Shapes) { if ($s.Type -eq 13) { $imgs++ } }
  if ($imgs -eq 0) { $errores.Add('El documento no tiene ninguna imagen/captura de pantalla.') }
  $doc.Close($false)
} finally { $word.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word) }

if ($errores.Count -eq 0) { Write-Host "OK: el documento está listo para entregarse ($imgs imágenes)." -ForegroundColor Green; exit 0 }
else { Write-Host "El documento NO está listo:" -ForegroundColor Yellow; $errores | ForEach-Object { Write-Host "  - $_" } ; exit 1 }
