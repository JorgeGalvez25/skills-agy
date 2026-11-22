# Equipo de Mantenimiento para los scripts de PowerShell (datos en equipo.json). Solo ASCII: no necesita BOM.
# Uso: . (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'mtto-comun\equipo.ps1')
# Deja $MttoDatos (todo el JSON) y $MttoEquipo (arreglo de fichas: nombre, corto, slack, slackId, correo, colorHoja).
$MttoDatos = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'equipo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$MttoEquipo = @($MttoDatos.equipo | ForEach-Object { $_ })
