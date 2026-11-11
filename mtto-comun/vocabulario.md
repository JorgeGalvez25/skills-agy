# Cómo leer los estatus de #mtto

Resumen para interpretar la salida de `canal.js estado`. El detalle de las reglas del formato está en `mtto-standup/SKILL.md`
y el de los eventos en `rcalidad/GUIA_CANAL.md`.

Cada colaborador publica su standup diario (~17:00) con las secciones **standby** y **seguimiento**, una línea por caso:
`TT##### - Tipo - Código: motivo` (antes del formato de códigos, `TT#####: estatus`). La línea dice cómo queda el caso al cierre del día.
Tipo: `C` cambio o mejora, `F` fallo, `AP` apoyo a soporte.

| `etapa` (script) | Códigos | Significado |
|---|---|---|
| `pausa` | `P` | Detenido: pausa, standby, en espera de logs |
| `trabajo` | `R`, `AN`, `D` | Revisando, analizando o en desarrollo |
| `piloto` | `PIL` | Liberado al cliente en piloto |
| `entregado` | `ENT`, `EST` | Entregado, en espera de respuesta de soporte o del cliente; `EST` = se preguntó el estatus |
| `rsp` | `RSP` | Revisión SCRUM Pendiente: el cliente dio por bueno; falta integrarlo a MAIN y las pruebas de la versión |
| `revpr` | `REVPR` | Después de RSP, corrige el código por las observaciones al PR. No es cierre ni reapertura |
| `pruebas` | `ESPLDP`, `BUGPRU` | Caso propio en pruebas con el tester; sigue abierto hasta la LDP |
| `tester` | `PRU`, `ESPBUG`, `FINPRU` | Caso de un compañero que este colaborador prueba |
| `ldp` | `LDP` | El tester liberó de pruebas (cierre) |
| `cierre` | `CEC`, Cancelado | Cierre sin pasar a RSP, incluidos los cancelados. "Probablemente se cancele" no cuenta |

- `contador`: "x2", "x3"… = veces que se ha repetido la misma acción (indica estancamiento).
- `enUltimo: false` con una etapa que no es `rsp`, `revpr`, `ldp` ni `cierre`: el caso **dejó de aparecer** sin estatus de cierre.
- `antes`: el caso se atendió primero con otro ID (el de soporte) y su historia ya viene unida.
- `sinTT`: trabajo sin número de caso. Un caso urgente sin ID aparece como `TTsinidN` hasta que recibe su TT.
- Eventos (mensaje aparte): `LDP` (antes `LIBERADO`), `REABIERTO`, `ORIGEN`.
- Los standups anteriores al 08/10/2026 traen bloques "Ayer" y "Hoy"; el script ya toma solo "Hoy".
