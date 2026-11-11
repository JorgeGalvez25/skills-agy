# Aclaraciones (`aclaraciones.json`)

Memoria de lo que los colaboradores explicaron y Jorge aceptó. El script excluye de `hallazgos` y `estancados` lo que coincida con una entrada vigente
y lo reporta en `aclarados`. Una entrada aplica cuando coinciden **todos** los campos que trae:

```json
[{
  "colaborador": "Saulo Lopez",        // nombre en Slack (obligatorio)
  "regla": "sin-caso",                 // regla del script (opcional)
  "tt": "TT104547",                    // opcional
  "texto": "piloto de transmisor",     // fragmento del detalle del hallazgo (opcional)
  "estatus": "En espera de logs",      // vale solo mientras el TT siga con este estatus (opcional)
  "hasta": "30/10/2026",               // vence después de esta fecha (opcional)
  "nota": "Mejora propia sin actividad; Jorge acepta hasta el piloto",  // obligatorio
  "fecha": "12/10/2026",
  "fuente": "DM Saulo 12/10/2026 08:49"
}]
```

**Cambio de ID confirmado:** `{"colaborador":"Saulo Lopez","regla":"cambio-id","tt":"TT12345","nuevo":"TT54321","nota":"…","fecha":"…","fuente":"…"}`.
No tapa hallazgos: el script une la historia de `tt` con la de `nuevo`, como con la marca `(antes TT#####)`.

(El archivo es JSON puro: sin los comentarios del ejemplo.) Haz cada aclaración lo más acotada posible: con `tt` o `texto`, y con `estatus` o `hasta`,
para que no tape problemas nuevos. Una aclaración sin `regla`, `tt` ni `texto` taparía todo lo del colaborador: no la guardes así.
Cuando revises, si una aclaración ya venció o su TT salió del standup, propón a Jorge quitarla.
