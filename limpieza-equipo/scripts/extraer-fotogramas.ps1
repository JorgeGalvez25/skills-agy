# Extrae fotogramas JPG de un video usando las APIs WinRT de Windows (sin ffmpeg ni Python).
# Uso: extraer-fotogramas.ps1 -Video <ruta.mp4> -OutDir <carpeta> [-Step 3]
param([Parameter(Mandatory)][string]$Video, [Parameter(Mandatory)][string]$OutDir, [double]$Step = 3)
if (-not (Test-Path -LiteralPath $Video)) { Write-Error "No existe el video: $Video"; return }
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Editing.MediaComposition, Windows.Media.Editing, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Editing.MediaClip, Windows.Media.Editing, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path -LiteralPath $Video).Path)) ([Windows.Storage.StorageFile])
$clip = Await ([Windows.Media.Editing.MediaClip]::CreateFromFileAsync($file)) ([Windows.Media.Editing.MediaClip])
$comp = New-Object Windows.Media.Editing.MediaComposition
# En PowerShell 5.1 la colección WinRT no expone .Add(); se invoca por la interfaz genérica.
[System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]].GetMethod('Add').Invoke($comp.Clips, @($clip)) | Out-Null
$dur = $comp.Duration.TotalSeconds
"Duración: {0:N1} s" -f $dur
New-Item -ItemType Directory -Force $OutDir | Out-Null
$i = 0
for ($t = 0.5; $t -lt $dur; $t += $Step) {
  $stream = Await ($comp.GetThumbnailAsync([TimeSpan]::FromSeconds($t), 0, 0, [Windows.Media.Editing.VideoFramePrecision]::NearestFrame)) ([Windows.Graphics.Imaging.ImageStream])
  $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
  $name = Join-Path $OutDir ("f{0:D3}_{1:000.0}s.jpg" -f $i, $t)
  $fs = [System.IO.File]::Create($name); $net.CopyTo($fs); $fs.Close(); $net.Close()
  $i++
}
"Fotogramas: $i en $OutDir"
