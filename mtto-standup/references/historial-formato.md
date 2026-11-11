# Historial del formato del standup

Cuándo cambió cada regla y cómo se registraba antes. `SKILL.md` describe solo el formato vigente; `revisar.js` sigue leyendo los anteriores.
Consulta este archivo cuando revises una fecha anterior al 29/10/2026 o cuando un colaborador use un formato viejo.

| Desde | Cambio | Antes |
|---|---|---|
| 08/10/2026 | El standup lleva solo las secciones standby y seguimiento, sin títulos de día. Lo hecho el día anterior se lee en el standup anterior | Bloques "Ayer" (o "Viernes") + "Hoy". El script toma solo el bloque "Hoy"; un "Hoy" que todavía aparezca como título no se marca, "Ayer" sí (`estructura`) |
| 09/10/2026 | `RSP` = Revisión SCRUM Pendiente (el cliente dio por bueno). `LDP` = liberación de pruebas por el tester, para cambios, mejoras y fallos, con su evento `LDP` | El evento era `LIBERADO` (fecha de instalación, solo cambios y mejoras). Los `LIBERADO` ya publicados se leen como LDP de cambio |
| 16/10/2026 | Reapertura = pasar de RSP, CEC o Cancelado a revisión o desarrollo. Entregado → revisión ya no es reapertura | También contaba como reapertura regresar de Entregado a revisión |
| 21/10/2026 | `CEC` también para los cancelados; aparece solo el día del correo de cierre. `CAN` ya no se usa (con `INICIO_CODIGOS` se marca `formato`) | `TT#####: Cancelado` o la línea `CANCELADO TT##### \| …` dentro del standup. Se siguen leyendo como cierre: no se marca `desaparece` ni `estancados` |
| 21/10/2026 | Jorge envía las retros desde un borrador de Slack | Las retros terminaban en "Enviado usando Claude" |
| 28/10/2026 | `REVPR`: corrección por observaciones al PR de un caso que ya pasó por RSP, con el mismo TT | Aparecía como "corrección para liberación" (p. ej. TT98105 y TT102632 de Miguel, 21–22/10/2026): no se trata como cambio de ID ni como trabajo sin cierre |
| Pendiente (`INICIO_CODIGOS`) | El formato `TT##### - C/F/AP - Código: motivo` es obligatorio | `TT#####: estatus` en texto libre; el script lo acepta sin marcarlo |

Notas para revisar fechas anteriores:

- `estructura` por incluir "Ayer" en los primeros días después del 08/10/2026: se menciona como recordatorio amable, no como corrección.
- Las mejoras llevaban tipo `M`; ahora van con `C`.
- El formato de línea con códigos es el de la skill `reporte-daily` de Saulo.
