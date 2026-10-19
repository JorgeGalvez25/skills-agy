param([string]$PdfDir, [string]$OutDir)
# Renderiza cada página de los PDF de $PdfDir a PNG (API Windows.Data.Pdf) para revisión visual.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType=WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asAction = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(); $task.Result }
New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($f in Get-ChildItem (Join-Path $PdfDir "*.pdf")) {
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($f.FullName)) ([Windows.Storage.StorageFile])
  $pdf = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
  for ($i = 0; $i -lt $pdf.PageCount; $i++) {
    $page = $pdf.GetPage($i)
    $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    # Ancho fijo legible: 2000 px para páginas horizontales, 1400 px para verticales
    $opts.DestinationWidth = if ($page.Size.Width -gt $page.Size.Height) { [uint32]2000 } else { [uint32]1400 }
    $ms = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $asAction.Invoke($null, @($page.RenderToStreamAsync($ms, $opts))).Wait()
    $png = Join-Path $OutDir ("{0}_p{1}.png" -f ($f.BaseName -replace '[^\w]','_'), ($i+1))
    $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ms.GetInputStreamAt(0))
    $fs = [System.IO.File]::Create($png); $net.CopyTo($fs); $fs.Close()
    "PNG  {0}  ({1:N0}x{2:N0}pt)" -f $png, ($page.Size.Width*0.75), ($page.Size.Height*0.75)
    $page.Dispose()
  }
}
