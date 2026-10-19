# Mapa de bases de datos → casillas de la plantilla

La plantilla oficial tiene 7 casillas fijas. Usa **exactamente** estos textos en `basesDatos`
del JSON: `BD Admón.`, `BD Ventas`, `BD Gasolinera`, `BD Volumétrico`, `BD I-Gas Master`,
`BD Nóminas`, `BD FACELE`.

Decide la casilla con el **alias de BDE/IBX (`DatabaseName`)** del dataset afectado, no solo
por el prefijo de la tabla: `DGEN*` existe tanto en Admón como en Ventas.

| DatabaseName (alias en .dfm)                              | Casilla            | Prefijos de tabla habituales |
|-----------------------------------------------------------|--------------------|------------------------------|
| DBIMAGEN, DBIMAGEN2, DBIMAGENM, DBAdmon                   | BD Admón.          | DGEN, DCNT, DCXP, DIVA, DBNC, DPRE, DFIS, DCFG |
| DBVentas1, DBVentas2, DBVentasD1, DBVentasO1, DBVtaDom1, DBComer | BD Ventas   | DFAC, DINV, DCXC, DCPR, DORT, DVDM, DGEN |
| DBGASOL1, DBGASOL2, DBGas                                 | BD Gasolinera      | DGAS |
| DBGASCONSOLA (Gas Consola)                                | BD Volumétrico     | DPVG |
| (proyectos de `Imagen Ib Volumetricos\Master`, iGasMaster) | BD I-Gas Master   | — |
| DBNOMI                                                    | BD Nóminas         | DNOM, DCRH |
| (FACELE)                                                  | BD FACELE          | — |

Mapa confirmado por el jefe de mantenimiento el 29/09/2026. Si aparece un alias que no esté
en la tabla, **pregunta al desarrollador** y no marques la casilla por suposición.

Hotel / RyB (DBHotel*, DBHotRyb*) no tienen casilla en la plantilla: menciónalo en
"Configuraciones Especiales" si aplica.

## Cómo detectar que un cambio toca la BD

- Campo persistente nuevo en un `.dfm` (`object T_XxxCampo: TStringField` + `FieldName`): la
  tabla **debe** tener el campo. Sin el script, *todos* los ejecutables que compilan ese
  DataModule fallan al abrir la tabla ("Field 'X' not found").
- DDL/DML en el código o en `.sql` (ALTER/CREATE/DROP, INSERT de catálogos, UPDATE masivos).
- Cambios de constantes `VersionBD...` o validaciones de migración.
- Tablas nuevas en `TableName` o en SQL de TQuery.

Los scripts suelen **no** estar versionados en Git. Si detectas cambio de BD y no hay `.sql`,
pídele al desarrollador la ruta del script. Nunca inventes un script para el documento del
distribuidor; en el documento interno sí puedes proponer el DDL marcado como *PROPUESTO*.
