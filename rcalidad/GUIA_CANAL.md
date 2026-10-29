Mensaje fijado en #mtto (publicado el 07/10/2026, actualizado el 08/10/2026; texto del 09/10/2026 pendiente de publicar en el mensaje fijado): https://igasmx.slack.com/archives/C02CGD1D9NX/p1791397394905699

Texto (los ejemplos de eventos llevan prefijo "Ejemplo:" o "Formato:" para que /rcalidad no los lea como eventos):

**Standup diario y registro de eventos en #mtto** (actualizado el 09/10/2026)

**1. Standup diario** (~17:00, mencionándome)
Sin títulos de día ("Ayer", "Viernes", "Hoy"): directo con las secciones **standby** y **seguimiento**, una línea por caso con cómo queda al cierre del día. La fecha del mensaje indica el día.

```
@Jorge Gálvez
- standby
    ◦ TT100001: En espera de logs
- seguimiento
    ◦ TT100002: Codificando
    ◦ TT100003: Entregado, en espera de respuesta x2
    ◦ TT100004: RSP
    ◦ TT100005: LDP
    ◦ TT100006: CEC
    ◦ TT100007: Cancelado
```

- Todo trabajo lleva su número de caso: `TT#####`, con el prefijo y 5 o más dígitos.
- Actualicen el estatus de cada caso todos los días. Si se repite la misma acción, usen el contador (x2, x3…).
- Un caso solo sale del standup después de aparecer **una última vez con su estatus de cierre**: RSP, LDP, CEC o Cancelado. Si deja de aparecer sin ese estatus, no sabemos qué pasó con él.
- **RSP** (Revisión SCRUM Pendiente): el cliente dio por bueno el cambio o la corrección del fallo; falta integrarlo a MAIN y las pruebas previas a liberar la versión. El caso puede salir del standup y regresa a seguimiento cuando entra a integración y pruebas con el tester; indíquenlo en el estatus (p. ej. `TT#####: SDP enviada`, `TT#####: En pruebas con el tester`).
- **REVPR** (Revisión de PR): corrección de código por las observaciones al PR de un caso que ya pasó por RSP. Se anota con el mismo TT (`TT##### - F - REVPR: observaciones del PR`); no es reapertura y no lleva REABIERTO. Al atender las observaciones, el caso aparece una última vez como RSP o sigue a pruebas.
- **Una vez iniciadas las pruebas no hay retroceso ni reapertura:** lo que encuentre el tester se corrige en el mismo TT hasta la LDP.
- **LDP**: el tester terminó sus pruebas y mandó el correo de liberación de pruebas (cambios, mejoras y fallos). Ese día el caso aparece como `TT#####: LDP` y además se publica el evento LDP (abajo).
- Los casos que llegan y se resuelven el mismo día también se anotan, con su estatus final.
- **Cancelado** se anota dentro del standup (`TT#####: Cancelado` o `CANCELADO TT##### | CAMBIO | Cliente | dd/mm/aaaa`); con eso el caso deja de tener seguimiento. Pueden anotarlo en cuanto se decide cancelar, pero entonces el caso ya no aparece en el siguiente standup (si se va a cerrar con CEC, anoten directamente CEC). Si se retoma, es reapertura: lleva REABIERTO (abajo).

**2. Eventos**
Con ellos se calculan los indicadores de **Tasa de éxito de cambios liberados** y **Resolución definitiva de fallos**. Se evalúa al departamento, no a la persona.

**Cómo se registra:** un **mensaje aparte, de una sola línea**, publicado el mismo día en que ocurre el evento (no dentro del standup ni en un hilo).
- La palabra clave va al inicio y en MAYÚSCULAS.
- Los campos se separan con `|`.
- Si te equivocas, edita el mensaje; no publiques otro.

**a) El tester liberó el caso de pruebas (LDP)**
Formato: `LDP TT##### | CAMBIO, MEJORA o FALLO | Cliente | dd/mm/aaaa`
Ejemplo: `LDP TT100001 | CAMBIO | Estación Ejemplo | 09/10/2026`
- Se publica cuando llega el correo del tester con la LDP. La fecha es la **del correo de LDP**.
- Aplica a cambios, mejoras y fallos. Sustituye al antiguo LIBERADO, que ya no se usa.
- Lo publica el desarrollador responsable del TT.
- Un solo registro por TT.

**b) Un caso en RSP, con CEC o Cancelado regresa a revisión o desarrollo** (la solución no funcionó, el problema volvió o se retomó)
Formato: `REABIERTO TT##### | motivo breve`
Ejemplo: `REABIERTO TT100002 | siguen sin actualizarse los inventarios de aceites`
- Un caso Entregado que regresa a revisión no es reapertura: todavía no lo da por bueno el cliente.
- Después de la LDP el caso ya no se reabre: si aparece un problema, va en un TT nuevo y, si lo causó ese caso, con ORIGEN.

**c) Un caso nuevo causado por un TT anterior** (un cambio metió un error o un fallo corregido reapareció con otro número)
Formato: `ORIGEN TT_nuevo <- TT_anterior | causa breve`
Ejemplo: `ORIGEN TT100003 <- TT100001 | la factura de contado falla desde que se instaló la mejora`

**Qué cuenta y qué no** (en Slack va como viñetas, porque las tablas no se muestran al editar)
| Situación | ¿Se registra? |
|---|---|
| El caso estaba en RSP y el cliente dice que la corrección no resolvió el problema | Sí: REABIERTO |
| Un caso con CEC o Cancelado se retoma | Sí: REABIERTO |
| El caso estaba Entregado (en espera de respuesta) y regresa a revisión | No: va en el standup con su estatus nuevo |
| Después de la LDP aparece un error provocado por ese cambio | Sí: ORIGEN nuevo <- cambio |
| Caso nuevo con la misma causa raíz de uno ya corregido | Sí: ORIGEN nuevo <- anterior |
| El caso estaba en RSP y se corrige el código por observaciones al PR | No: va en el standup como REVPR, con el mismo TT |
| El tester encuentra algo una vez iniciadas las pruebas (antes de la LDP) | No: no hay retroceso ni reapertura; se corrige en el mismo TT |
| Un caso con LDP vuelve a fallar | No se reabre: TT nuevo con ORIGEN nuevo <- anterior |
| El cliente pide algo nuevo o distinto a lo acordado | No: es solicitud nueva |
| Problema distinto en el mismo módulo | No |
| El TT sigue "Entregado, en espera de respuesta" o en RSP | No: va en el standup |
| El caso se canceló | No: va en el standup como Cancelado |

**Por qué importa:** cada cambio se sigue desde su entrega hasta **30 días** después de su LDP, y cada fallo atendido durante **30 días**. Registrar una reapertura **no es una falta**; lo que sí afecta es no registrarla. Si tienes duda de si algo es reapertura, origen o solicitud nueva, pregunta aquí antes de registrarlo.

Cualquier duda, por aquí. ¡Gracias!
