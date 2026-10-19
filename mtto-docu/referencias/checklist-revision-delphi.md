# Checklist de revisión y caza de bugs (Delphi 7 / Firebird / iGas)

Úsalo al escribir las secciones "Revisión de código" y "Plan de pruebas" del documento interno.
Es una lista para **buscar**, no para copiar: incluye solo los puntos que aplican al diff, con
archivo y línea, y que pasen el filtro de relevancia de `SKILL.md` (pueden ocurrir con datos
normales de una estación o rompen otro módulo).

## Código Pascal
- Conversiones sin validar: `StrToInt`, `StrToFloat`, `StrToDate` sobre datos de usuario, BD o
  config → usar `TryStrTo...`/`...Def`. Cadenas vacías o `NULL` rompen en producción.
- Separador decimal/fecha: `FormatFloat`, `FloatToStr`, `DecimalSeparator`, `ShortDateFormat`.
  Las estaciones tienen configuraciones regionales distintas.
- Objetos creados sin `try..finally Free`; `TStringList`, `TQuery` dinámicos, formularios modales.
- Excepciones tragadas (`except end;`) que ocultan fallas; mensajes que no dicen qué hacer.
- Transacciones: `StartTransaction` sin `Commit`/`Rollback` en todas las rutas; locks en Firebird.
- SQL armado por concatenación con datos del usuario (comillas, inyección) → parámetros.
- Comparaciones de `Currency`/`Double` con `=`; redondeos de importes, IVA, IEPS, retenciones.
- Índices de cadena (`Copy`, `Pos`) con longitudes fijas: ¿qué pasa si la cadena es más corta?
- Variables globales/estado compartido entre formularios; eventos (`OnChange`, `AfterScroll`)
  que se disparan al abrir el dataset.
- Código duplicado en unidades gemelas (p. ej. `UGASPREC` y `UGASPRECEST`): ¿se corrigió en todas?

## Formularios (.dfm)
- Cambios de `Left/Top/Width/Height/TabOrder` no intencionales (se guardan al abrir el form en otra resolución). Señálalos para que se descarten si no son parte del cambio.
- Campos persistentes nuevos (`TField`): requieren el campo en la BD **de todas las estaciones**.
- Eventos desconectados (`OnClick = ` eliminado) o componentes borrados que el código aún usa.
- Antes de reportar un hallazgo en un evento, confirmar en el `.dfm` que esté asignado (`OnClick = ...`) o que alguien lo llame (`git grep`); si no, es código muerto.
- Longitud (`Size`) del `TStringField` igual a la del campo en BD.

## Unidades compartidas
- Si la unidad modificada está en `Imagen Ib Libs` o es un DataModule (`DDM*`), lista **todos**
  los ejecutables que la compilan: todos requieren recompilación, versión y pruebas de regresión.
- Cambios de firma de funciones públicas: buscar todos los llamadores en los demás repos.

## Base de datos (Firebird)
- Script idempotente o, al menos, que falle de forma clara si ya se ejecutó.
- Valores por defecto para registros existentes (`NULL` en campos nuevos).
- Orden de ejecución respecto a la actualización de ejecutables.
- Estaciones con BD de versión anterior: ¿el ejecutable nuevo abre sin el script? ¿el viejo con el script?
- Triggers/generadores/procedimientos afectados; permisos (`GRANT`) para usuarios de la aplicación.

## Dominio iGas (casos donde suelen aparecer bugs)
- Cortes y turnos: cambio de turno a medianoche, cortes sin ventas, corte reabierto.
- Precios: cambio de precio a mitad de turno, precio programado, liquidación con precio anterior.
- Facturación/CFDI: RFC genérico, cliente sin CP, cliente con RFC duplicado, notas de crédito,
  factura global, cancelación, timbrado sin conexión.
- Formas de pago: contado, crédito, vales, tarjetas, FlexPay, puntos; tickets mixtos.
- Volumétricos: jarreos, consignación, mermas, anexo 30/31, dispensarios de marcas distintas.
- Multi-estación / grupo de estaciones: datos de otra estación, permisos por usuario/módulo.
- Kiosco / Tablet: sin red, reintentos, impresora apagada, sesión expirada, máximo de usuarios.
- Fin de mes / fin de año: reportes y pólizas que cruzan periodos, DIOT, IVA del mes anterior.
