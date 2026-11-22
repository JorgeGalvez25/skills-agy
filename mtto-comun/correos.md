# Actualizar la caché de correos

Las skills que cruzan los standups con los correos de los casos (`/mtto-standup`, `/mtto-fechas`) trabajan sobre la misma caché:
`C:\Users\jorge\Dropbox\MTTO\ReportesMTTO\datos\correos_mtto.json`. Guarda solo los correos con un TT en el asunto de la Bandeja de entrada
y Elementos enviados de `jorgegalvez@igas.com.mx`. Outlook se lee con el script, en solo lectura; no edites la caché a mano.

## Actualizar

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jorge\.gemini\config\skills\mtto-comun\correos.ps1" [-Desde dd/mm/aaaa]
```

Sin `-Desde` relee desde 3 días antes del último correo guardado (si no hay caché, 120 días) y reemplaza lo de ese periodo (descarta lo anterior al inicio y deduplica por `id` al unir).
Con `-Desde` relee desde ese día (úsalo si la skill necesita un periodo que la caché no cubre: ver `desde` en la caché). Imprime
el periodo leído, los correos leídos, el total y las relaciones por tipo. Si falla, Outlook debe estar abierto con esa cuenta.

## Consultar

```powershell
node "C:\Users\jorge\.gemini\config\skills\mtto-comun\correos.js" estado <desde dd/mm/aaaa> [hasta dd/mm/aaaa]
```

Devuelve por caso (TT) sus correos del periodo, responsable, último correo propio y si la entrega/estatus quedó sin respuesta (`sinRespuesta`; se apaga con un correo de alguien fuera del equipo y de Jorge, o con un `rsp`, `cec` o `ldp` propio posterior), más:

- `cambiosId`: asignaciones con `CASO SOPORTE: TT…` (el caso pasó del ID de soporte al definitivo).
- `atiendeCon`: CEC cuyo trabajo sigue en otro TT (no es cambio de ID); toma el primer TT del texto distinto al del asunto ("atenderá", "atendido mediante", "cerrará"…).
- `anomalias`: entregas cuya ruta apunta a un TT distinto al del asunto (posible ID equivocado).

La variable `MTTO_CORREOS` apunta a otra caché (pruebas). Los correos completos están en el JSON (`extracto` trae el inicio del cuerpo propio).
