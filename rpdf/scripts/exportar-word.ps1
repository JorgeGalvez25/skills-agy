param([string]$Dir, [string]$Out, [string]$Tmp)
# Exporta cada .docx de $Dir a $Out\<nombre>.pdf.
# Se trabaja sobre una copia local de cada documento, fuera de Dropbox.
New-Item -ItemType Directory -Force $Tmp | Out-Null
$wd = New-Object -ComObject Word.Application; $wd.Visible=$false; $wd.DisplayAlerts=0
try {
foreach ($f in Get-ChildItem (Join-Path $Dir "*.docx") | Where-Object { $_.Name -notlike '~$*' }) {
  $copia = Join-Path $Tmp $f.Name
  Copy-Item $f.FullName $copia -Force
  $doc = $wd.Documents.Open([string]$copia, $false, $true, $false)
  $pdf = [string](Join-Path $Out ($f.BaseName + ".pdf"))
  $doc.SaveAs2([ref]$pdf, [ref]17)  # 17 = wdFormatPDF
  $doc.Close([ref]$false)
  Remove-Item $copia -Force
  "PDF  $pdf"
}
} finally { $wd.Quit() }
