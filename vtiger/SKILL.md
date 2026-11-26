---
name: vtiger
description: 'Consulta y actualiza casos de VTiger del Departamento de Mantenimiento. Lee directo de VTiger (detalle de un TT, comentarios, caso de soporte relacionado, búsqueda por número, ticket de soporte o título, tablero de casos abiertos por colaborador y estatus) y mueve estatus y fechas de Cambios y Fallos (soporte y testing) por la API de MelissaVirtual, siempre con confirmación y registro. Usar cuando digan "/vtiger", "revisa el TT##### en VTiger", "en qué estatus está", "quién tiene el TT", "busca el caso de soporte", "tablero de VTiger", "casos abiertos de <colaborador>", "pasa el TT a pruebas/entregado/liberado/terminado", "mueve la fecha promesa" o "cancela el caso".'
---

# VTiger (/vtiger)

Todo pasa por `C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js` (en adelante `vtiger.js`). Las respuestas son JSON.

- **Lecturas:** directo al webservice de VTiger con el access key de Jorge.
- **Escrituras:** solo por la API de MelissaVirtual con la cuenta de Jorge, que aplica las reglas de transición y envía los correos. Nunca uses `revise` directo para mover un caso.
- **Credenciales:** `C:\Users\jorge\.mtto\vtiger.json` (`usuario`, `password`, `accessKey`, `url`, `api`). Nunca imprimas, copies ni muestres su contenido.

## Lecturas

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" caso TT#####      # campos con valor, soporte relacionado (cf_1275), definitivos que apuntan a él, comentarios
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" buscar TT#####    # el caso y los que lo tienen como ticket de soporte
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" buscar <texto>    # por título (LIKE)
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" casos TT##### TT##### ...   # ficha corta de varios casos: { casos: { TT: {...} }, faltan: [] }
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" tablero [nombre]  # abiertos de Proyectos del equipo: { colaborador: { "Tipo - Estatus": [casos] } }
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" vista TT#####     # encabezado del caso como lo muestra VTiger (lo usa la imagen de /mtto-aca)
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" promesas [nombre] # tablero de fallos: PROCESO (Revisión, promesa de entrega) y ENTREGADO (promesa de respuesta)
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" fallos YYYYMM     # relación de fallos atendidos del mes (columnas del reporte de VTiger)
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" query "SELECT ... FROM HelpDesk WHERE ..."   # VTQL libre, sin LIMIT (pagina solo)
```

- VTQL no acepta paréntesis para agrupar `OR`; usa `IN(...)` o varias consultas.
- No existe historial de cambios en el webservice: VTiger solo dice el estado actual.
- El estatus del flujo es `cf_1086` en Cambios y `cf_1084` en Fallos; `estatus` ya trae el que corresponde.
- En la práctica el equipo solo mueve el estatus y casi nunca llena las fechas del flujo. Para métricas, la fuente siguen siendo #mtto, los correos y CambiosProceso.xlsm; VTiger sirve para el estado actual y para contrastar.

Presenta el resultado en tablas cortas (caso, título, estatus, status, asignado, fechas con valor), no el JSON.

## Escrituras

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\vtiger.js" mover TT##### <acción> [fecha=AAAA-MM-DD] [usuario=Nombre] [motivo=...] [observaciones=...] [notificar=si|no]
```

El controlador se elige solo: `Cambio` para cambios; `FalloTesting` si el fallo está en Codificación pendiente, Codificando, Corrección de bugs, Integración o Pruebas; `Fallo` (soporte) en otro caso.

| Controlador | Acciones (parámetros) |
|---|---|
| Cambio | `analizando` (usuario, fecha de asignación) · `codificando` (usuario, fecha de asignación de codificación) · `pruebas` · `entregado` · `liberado` · `terminado` · `cancelado` (fecha) |
| Fallo | `en-proceso` (usuario, fecha, notificar) · `regresa-pendiente` (motivo, notificar) · `promesa-entrega` · `promesa-respuesta` · `regresa-en-proceso` (fecha **obligatoria**) · `entregado` · `terminado` · `cerrado` · `cancelado` (fecha) |
| FalloTesting | `codificacion` (usuario, fecha, notificar) · `regresa-pendiente` (motivo, notificar) · `integracion` (observaciones, notificar) · `pruebas` (observaciones, fecha, notificar) · `bugs` · `liberado` (fecha) |

- Si no das `fecha`, se usa la de hoy, salvo en las promesas, donde es obligatoria. La API rechaza fechas futuras o anteriores a la asignación y salta fines de semana y feriados al calcular promesas.
- `usuario` acepta el nombre del colaborador ("Martín", "Saulo López").
- Cambio en Entregado deja `ticketstatus` = Wait For Response; Terminado cierra el caso con Resolución = Resuelto, y Cancelado con Resolución = Cancelado.

**Flujo obligatorio:**

1. Corre `mover` **sin** `--confirmar`. Solo arma la llamada y muestra el estado actual (`antes`), la ruta y los parámetros.
2. Muéstrale a Jorge el caso, el estatus de origen y destino, las fechas y si la acción envía correo. Espera su confirmación explícita, una por caso o una para un lote que él revisó completo.
3. Con su "sí", repite el comando con `--confirmar`. El resultado trae `http`, `respuesta` y `despues` (el caso vuelto a leer). Si `despues.estatus` no es el esperado, dilo.
4. Cada escritura queda en `C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\vtiger_escrituras.log` (una línea JSON). Da esa ruta al terminar.

Errores comunes: `Estado actual "X" no permite el cambio` (el caso no está en un estatus de origen válido, revisa con `caso`); `Fecha ... inválida`; `401/403` (el rol de la cuenta no tiene permiso para esa acción); `Permission to read given object is denied` (la API escribe con la sesión VTiger de cada usuario: su rol no puede editar Casos o esos campos; los desarrolladores de Mantenimiento van en el rol H38 "ANALISTA - DESARROLLADOR MTTO", perfil 29).

## La API

`api` de `vtiger.json` apunta a producción, `https://melissavirtualapi.azurewebsites.net/api`. `CambioController` solo tiene rutas `PUT`: un `GET` a `/api/Cambio` da 404 aunque esté publicado.

Para probar cambios de la API antes de publicarlos, levántala local y apunta `api` a `http://localhost:5240/api` mientras tanto:

```powershell
Set-Location "C:\Users\jorge\Dropbox\Proyectos\MelissaVirtual\MelissaVirtualAPI"; dotnet build -v q; if ($?) { $env:ASPNETCORE_ENVIRONMENT = 'Development'; dotnet run --no-build --no-launch-profile --urls http://localhost:5240 }
```
