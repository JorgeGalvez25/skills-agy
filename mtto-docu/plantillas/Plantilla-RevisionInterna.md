# Revisión interna {{TT}} — {{TITULO}}

> Documento **interno** del departamento de mantenimiento. No se entrega a distribuidores.
> Generado por `/mtto-docu` el {{FECHA_GENERACION}}. Informe para distribuidor: `{{RUTA_DOCX}}`

## 1. Ficha

| Campo | Valor |
|---|---|
| Ticket VTiger | {{TT}} (soporte: {{TT_ORIGEN}}) _(en cambios, solo {{TT}})_ |
| Código pendiente de versionar | Ninguno / Justificado (ver 3.4) |
| Tipo | Corrección / Cambio |
| Cliente | {{CLIENTE}} |
| Producto / sistema | {{PRODUCTO}} |
| Desarrollador(es) | {{AUTORES}} |
| Revisor asignado | _(llenar)_ |
| Repos y ramas | {{REPO}}: `{{RAMA}}` ({{N}} commits) |
| Versión que se entrega | {{VERSION}} (actual en `.dof`: {{VERSION_DOF}}) |
| Complejidad / riesgo | Baja·Media·Alta / Bajo·Medio·Alto — _una línea_ |

## 2. Resumen técnico

_Máximo 3 viñetas en "Solución"; nombra unidades y métodos, no expliques el código línea por línea._

- **Problema / necesidad:**
- **Causa raíz:** _(en cambios: "No aplica, funcionalidad nueva")_
- **Solución:**
- **Fuera de alcance:** _(solo si hay algo que el revisor deba saber; si no, quitar la viñeta)_

## 3. Qué se entrega

### 3.1 Archivos modificados

| Archivo | Qué cambió (una línea) |
|---|---|
| | |

### 3.2 Ejecutables

| Ejecutable | Directo / indirecto | Versión actual → nueva |
|---|---|---|
| | | |

### 3.3 Base de datos y configuración

_Una tabla solo si hay scripts o DML; si no, una línea: "Sin cambios en base de datos."_

| BD | Objeto | Cambio | Script | ¿En Git? |
|---|---|---|---|---|
| | | | | Sí / **No** |

- Orden de instalación y configuración (variables, `.ini`, servicios): _solo lo que aplique_.

### 3.4 Código pendiente de versionar

_Lo que reportó `Get-CambiosTT.ps1` al generar este documento y la razón que dio el desarrollador. Si no hubo: "Ninguno al generar el documento."_

| Repo | Archivo / commits | Estado | Razón del desarrollador |
|---|---|---|---|
| | | Sin commit / Sin rastrear / Sin push | |

## 4. Revisión de código

_Solo hallazgos reales o probables con los datos del cliente. Máximo 6. Sin observaciones de estilo salvo que afecten el mantenimiento. Si no hay: "Sin hallazgos."_

| ID | Archivo:línea | Hallazgo y escenario | Severidad | Sugerencia |
|---|---|---|---|---|
| H1 | | | Alta / Media / Baja | |

**Ruido en el diff:** _una línea (p. ej. "posiciones en UFAGTURC.dfm y UGASMENU.dfm; descartar")_ o "Ninguno".

## 5. Plan de pruebas

**Preparación:** _viñetas cortas: ejecutables, scripts y los datos mínimos (importes, fechas, claves)._

| ID | Tipo | Caso y pasos | Resultado esperado | Estado |
|---|---|---|---|---|
| P01 | F | Escenario del ticket | | ☐ |

Tipos: **F** funcional · **N** negativo · **R** regresión · **BD** base de datos. Estado: ☐ pendiente · ✅ aceptado · ❌ rechazado (anotar en 6).

## 6. Defectos encontrados en la revisión

| # | Caso | Descripción | Severidad | Estado |
|---|---|---|---|---|
| | | | | |

## 7. Liberación

- [ ] Hallazgos atendidos o justificados; pruebas ejecutadas sin defectos Alta/Media abiertos.
- [ ] Sin código pendiente de versionar en la rama, o lo de 3.4 resuelto (commit/push) o descartado.
- [ ] Scripts de BD versionados y probados. _(quitar si no hay BD)_
- [ ] Versión incrementada en los `.dof` de los ejecutables afectados.
- [ ] Rama integrada a `main` por PR aprobado.
- [ ] Informe para distribuidor con capturas y `Test-InformeDistribuidor.ps1` en verde.

| Revisor | Fecha | Resultado (Aprobado / Con observaciones / Rechazado) | Observaciones |
|---|---|---|---|
| | | | |

## Anexo. Commits

| Repo | Commit | Fecha | Mensaje |
|---|---|---|---|
