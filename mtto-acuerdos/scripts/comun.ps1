# Funciones compartidas por los scripts de /mtto-acuerdos (guardar en UTF-8 con BOM: PowerShell 5.1)

# Equipo actual, en el orden en que se agrupan las filas del archivo
$Equipo = @('Martín Reyes', 'Miguel Armenta', 'Saulo López', 'Susana Gámez')

# Nombre canónico a partir del nombre de pila (unifica Gamez/Gómez/Gámez, acentos, espacios)
function Normalize-Persona([string]$n) {
  $n = ($n -replace '\s+', ' ').Trim()
  foreach ($p in $Equipo) { if ((Remove-Acentos $n) -like ((Remove-Acentos ($p -split ' ')[0]) + '*')) { return $p } }
  return $n
}

function Get-OrdenPersona([string]$n) { $i = [array]::IndexOf($Equipo, (Normalize-Persona $n)); if ($i -lt 0) { 99 } else { $i } }

function Remove-Acentos([string]$s) {
  $d = $s.Normalize([Text.NormalizationForm]::FormD)
  -join ($d.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
}

# Clave de módulo para comparar entre versiones (sinónimos y errores de captura del historial)
function Get-ClaveModulo([string]$m) {
  $k = (Remove-Acentos $m).ToLower() -replace '[^a-z0-9]', ''
  switch -regex ($k) {
    '^(mastervol|masterdelphi)$' { return 'mastervol' }
    '^(masterfac|masterfacturacion)$' { return 'masterfac' }
    '^liq'                       { return 'liquidaciones' }
    '^(panel20|igascontrolador|controlador)$' { return 'controlador' }
    '^(igasfacturacion|facturacion)$' { return 'igasfacturacion' }
    '^(igasadministrador|igasadmin)$' { return 'igasadministrador' }
    '^convertidor'               { return 'convertidor' }
    '^actualizador'              { return 'actualizador' }
    default { return $k }
  }
}

# Módulos de una celda (separados por salto de línea, '/' o ',')
function Split-Modulos([string]$s) { @($s -split "[`r`n/,]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '-' }) }

function Get-PesoComplejidad([string]$g) { switch ($g) { 'Alta' { 3 } 'Media' { 2 } default { 1 } } }

# Lee un arreglo JSON (ConvertFrom-Json de PS 5.1 entrega el arreglo como un solo objeto)
function Read-JsonArray([string]$p) { $x = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; @($x | ForEach-Object { $_ }) }
