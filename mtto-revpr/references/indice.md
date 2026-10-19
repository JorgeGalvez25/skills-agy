# Plantilla del índice `00_Resumen_Revision_PR_<versión>.md`

Los números salen de `contar.ps1` y de `digest.md`; no se cuentan a mano. Orden de la tabla: primero por nivel (Crítico, Atención, Señal, Acotado) y, dentro de cada nivel, por veredicto (❌, ⚠️, ✅).

```
# Revisión de pull requests — versión <versión>

**Fecha de revisión:** <dd/mm/aaaa> · **PR revisados:** <n> (<m> casos) · **Destino:** `main`

| Veredicto | Casos |
|---|---|
| ❌ Pedir cambios | <n> |
| ⚠️ Aprobar con observaciones | <n> |
| ✅ Aprobar | <n> |

Hallazgos en total: **<n> Alta**, <n> Media, <n> Baja.

## Resumen por caso

| TT | Nivel | Responsable → Tester | PR | Veredicto | Alta / Media / Baja | Lo más grave |
|---|---|---|---|---|---|---|
| [TT#####](TT#####.md) | … | … → … | 1715 | ❌ Pedir cambios | 1 / 3 / 2 | <una o dos frases> |

## Seguimiento de la nota de atención especial
<una viñeta por cada H1/H2 de la nota: sigue presente / corregido. Si la nota no existe, decirlo.>

## Acuerdos del Excel sin cumplir
<una viñeta por cada acuerdo concreto que no está en el PR, con el TT; o "Todos los acuerdos verificables se cumplen.">

## Riesgos de integración entre PR
<cada CONFLICTO y cada "sin base común" del digest, con lo que se pierde y cómo resolverlo; los cruces sin conflicto que requieren probar juntos los casos.>

## Orden de instalación que exigen los cambios
<solo los casos que lo requieren: BD → Master → ejecutables, Master y Kioscos juntos, scripts al ActualizadorBD, etc.>

## Casos sin PR para revisar
<TT sin PR, con PR ya completado o abandonado, y PR activos que no están en el Excel; o "Ninguno.">

## Notas
- Revisión estática del código de cada PR, comparada contra el Excel de acuerdos, el informe interno del desarrollador y la nota de atención especial. No se compiló ni se ejecutó.
- No se revisó lo que no viene en los PR (procedimientos almacenados, triggers, scripts de BD y clases fuera del diff); cada informe lo detalla en "No verificable".
- <Hallazgos Alta verificados por segunda vez contra el código.>
```
