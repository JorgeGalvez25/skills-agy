// Uso: node eventos.js mensajes.json
// mensajes.json: [{ "ts": "1790575200.123456", "autor": "Saulo Lopez", "texto": "LDP TT106586 | CAMBIO | ..." }, ...]
// (en lugar de "ts" se acepta "fecha": "dd/mm/aaaa").
// Convierte los mensajes del canal en eventos LDP / REABIERTO / ORIGEN e imprime los que no se pudieron leer.
// Desde el 09/10/2026 LDP (liberación de pruebas, para cambios, mejoras y fallos) sustituye a LIBERADO;
// los LIBERADO ya publicados se siguen leyendo como cambios.
const fs = require('fs');
const { fecha, fechaSlack, dmy, numTT } = require('./comun');

// Quita formato de Slack, entidades HTML, acentos y viñetas/emojis al inicio
function limpiar(linea) {
  return linea
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
    .replace(/[*_~`]/g, '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/^[\s•◦▪︎\-–>]*(:[a-z0-9_+\-]+:\s*)*/i, '')
    .trim();
}

const TT = 'TT\\s*-?\\s*(\\d{4,})';
const RX = {
  ldp: new RegExp(`^(LDP|LIBERADO)\\s+${TT}\\s*\\|\\s*([A-Z]+)\\s*\\|\\s*([^|]*?)\\s*(?:\\|\\s*(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}))?\\s*$`, 'i'),
  reabierto: new RegExp(`^REABIERTO\\s+${TT}\\s*(?:\\|\\s*(.*))?$`, 'i'),
  origen: new RegExp(`^ORIGEN\\s+${TT}\\s*(?:<-+|←|<=+|<)\\s*${TT}\\s*(?:\\|\\s*(.*))?$`, 'i')
};
const CLAVE = /^(LDP|LIBERADO|REABIERTO|ORIGEN)\b/i;

try {
  const arch = process.argv[2];
  if (!arch || !fs.existsSync(arch)) throw new Error('Falta el archivo JSON de mensajes.');
  const mensajes = JSON.parse(fs.readFileSync(arch, 'utf8'));
  const cambios = [], fallosLdp = [], reaperturas = [], origenes = [], noLeidos = [], avisos = [];
  const vistos = new Set();

  for (const msg of mensajes) {
    // La búsqueda puede traer el mismo mensaje dos veces
    const llave = (msg.ts || msg.fecha) + '|' + msg.texto;
    if (vistos.has(llave)) continue;
    vistos.add(llave);
    const fMsg = msg.ts ? fechaSlack(msg.ts) : fecha(msg.fecha);
    for (const bruta of String(msg.texto || '').split(/\r?\n/)) {
      const l = limpiar(bruta);
      if (!CLAVE.test(l)) continue;
      const base = { autor: msg.autor || null, fechaMensaje: dmy(fMsg), ts: msg.ts || null };
      let m;
      if ((m = l.match(RX.ldp))) {
        const clave = m[1].toUpperCase(), tipo = m[3].toUpperCase();
        const validos = clave === 'LDP' ? ['CAMBIO', 'MEJORA', 'FALLO'] : ['CAMBIO', 'MEJORA'];
        if (!validos.includes(tipo)) { noLeidos.push({ ...base, linea: l, motivo: `tipo "${m[3]}" (solo ${validos.join(', ')})` }); continue; }
        let f = fMsg;
        if (m[5]) { try { f = fecha(m[5]); } catch (e) { noLeidos.push({ ...base, linea: l, motivo: e.message }); continue; } }
        else avisos.push(`TT${m[2]}: ${clave} sin fecha; se toma la del mensaje (${dmy(fMsg)})`);
        // Las LDP de fallos no entran al ind. 2; el universo del ind. 3 sale de /rfallos
        (tipo === 'FALLO' ? fallosLdp : cambios).push({ tt: 'TT' + m[2], tipo, clave, cliente: m[4] || null, fecha: dmy(f), ...base });
      } else if ((m = l.match(RX.reabierto))) {
        reaperturas.push({ tt: 'TT' + m[1], fecha: dmy(fMsg), motivo: (m[2] || '').trim() || null, ...base });
      } else if ((m = l.match(RX.origen))) {
        if (m[1] === m[2]) { noLeidos.push({ ...base, linea: l, motivo: 'el TT nuevo y el anterior son el mismo; usar REABIERTO' }); continue; }
        origenes.push({ nuevo: 'TT' + m[1], anterior: 'TT' + m[2], fecha: dmy(fMsg), causa: (m[3] || '').trim() || null, ...base });
      } else noLeidos.push({ ...base, linea: l, motivo: 'no sigue el formato' });
    }
  }

  // Un TT = un cambio: se conserva la primera liberación
  const porTT = {};
  for (const c of cambios) {
    const prev = porTT[c.tt];
    if (!prev) { porTT[c.tt] = c; continue; }
    if (prev.fecha !== c.fecha) avisos.push(`${c.tt}: varios LDP/LIBERADO (${prev.fecha} y ${c.fecha}); se usa el más antiguo`);
    if (fecha(c.fecha) < fecha(prev.fecha)) porTT[c.tt] = c;
  }
  const orden = (a, b) => numTT(a.tt || a.nuevo) - numTT(b.tt || b.nuevo);
  for (const r of reaperturas) if (!r.motivo) avisos.push(`${r.tt}: REABIERTO sin motivo`);
  for (const o of origenes) if (!o.causa) avisos.push(`${o.nuevo} <- ${o.anterior}: ORIGEN sin causa`);

  console.log(JSON.stringify({
    cambios: Object.values(porTT).sort(orden),
    fallosLdp: fallosLdp.sort(orden),
    reaperturas: reaperturas.sort(orden),
    origenes: origenes.sort(orden),
    noLeidos, avisos
  }, null, 2));
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(1);
}
