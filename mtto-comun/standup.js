// Parser único de los standups de #mtto. Lo usan /mtto-standup (revisar.js), /mtto-rendimiento (datos.js)
// y canal.js (estado por TT para /mtto-fechas y /mtto-quincenal). Una regla nueva del formato se cambia solo aquí.
const sinAcentos = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');

// Quita entidades HTML, menciones, formato de Slack y viñetas, citas o emojis al inicio de la línea
const limpiar = l => l.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
  .replace(/<@[^>]+>/g, '').replace(/[*_~`]/g, '')
  .replace(/^[\s•◦▪︎\-–·>]*(:[a-z0-9_+\-]+:\s*)*/i, '').trim();
const RX_DIA = /^(ayer|hoy|viernes|lunes|martes|miercoles|jueves|sabado|domingo)\s*:?\s*$/i;
const RX_SECCION = /^(standby|stand by|seguimiento)\s*:?\s*$/i;
const RX_EVENTO = /^(LDP|LIBERADO|REABIERTO|ORIGEN)\b/i; // LIBERADO: eventos anteriores al 09/10/2026

// Códigos del formato estándar "TT##### - C/F/AP - Código: motivo" y su texto (RSP, CEC y LDP se quedan igual).
// ESPLDP, BUGPRU, PRU, ESPBUG y FINPRU se traducen con "espera de LDP" o "tester" para que cuenten como pruebas iniciadas;
// los de quien prueba el caso de un compañero (PRU, ESPBUG, FINPRU) llevan "como tester".
const CODIGOS = { P: 'Pausa', R: 'Revisando', AN: 'Analizando', D: 'Desarrollo', PIL: 'Piloto', ENT: 'Entregado', EST: 'Preguntar estatus', CAN: 'Cancelado',
  ESPLDP: 'En espera de LDP', BUGPRU: 'Bug del tester en pruebas', PRU: 'Pruebas como tester', ESPBUG: 'Espera de corrección como tester',
  FINPRU: 'Fin de pruebas como tester', REVPR: 'Corrección por revisión de PR' };
const CODIGOS_TESTER = ['PRU', 'ESPBUG', 'FINPRU'];
const esCodigo = c => !!CODIGOS[c.toUpperCase()] || ['RSP', 'CEC', 'LDP'].includes(c.toUpperCase());

// Etapa del caso: pausa, trabajo, piloto, entregado, rsp, revpr, pruebas, tester, ldp, cierre
const ETAPA_CODIGO = { P: 'pausa', R: 'trabajo', AN: 'trabajo', D: 'trabajo', PIL: 'piloto', ENT: 'entregado', EST: 'entregado', CAN: 'cierre',
  RSP: 'rsp', REVPR: 'revpr', ESPLDP: 'pruebas', BUGPRU: 'pruebas', PRU: 'tester', ESPBUG: 'tester', FINPRU: 'tester', LDP: 'ldp', CEC: 'cierre' };
// Etapa a partir del texto del estatus (formato anterior "TT#####: Entregado, en espera de respuesta")
function etapaTexto(est, seccion) {
  const s = sinAcentos(est).toLowerCase();
  if (/como tester|probando el caso de|pruebas? del caso de/.test(s)) return 'tester';
  if (/\bcec\b|cancelad|cerrad|se cierra/.test(s)) return 'cierre';
  if (/\bldp\b|liberad[oa] de pruebas|\bliberado\b/.test(s) && !/espera|pendiente|falta|solicit|\bsdp\b/.test(s)) return 'ldp';
  if (/\brevpr\b|revision de(l)? pr\b|observaciones (del|al) pr/.test(s)) return 'revpr';
  if (/\bsdp\b|tester|espera de (la )?ldp|en pruebas|integraci/.test(s)) return 'pruebas';
  if (/\brsp\b|revision scrum/.test(s)) return 'rsp';
  if (/entregad|en espera de respuesta|espera de (respuesta|confirmaci|visto)|preguntar estatus|estatus/.test(s)) return 'entregado';
  if (/piloto/.test(s)) return 'piloto';
  if (seccion && /standby|stand by/.test(seccion)) return 'pausa';
  if (/pausa|en espera de (logs|informaci|acceso|bd|base)|detenid/.test(s)) return 'pausa';
  return 'trabajo';
}
function fechaDmy(v) {
  const m = String(v).match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})\b/);
  return m ? new Date(Date.UTC(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[2] - 1, +m[1])) : null;
}

// Convierte el texto de un standup en bloques { etiqueta, items[] }.
// Sin título de día, la primera sección standby/seguimiento abre el bloque "hoy".
// Cada item: linea, seccion, tt (null si la línea no trae caso), estatus (texto legible: el código traducido + motivo), contador (xN),
// y si trae TT: tipo (C, F, M, AP o null, como se escribió), codigo, motivo, crudo (lo que va después del TT),
// tipoCaso (C, F o AP; se infiere del texto si no viene), etapa, fechaEntrega (del RSP), antes / antesSinId (cambio de ID),
// sinId (TTsinidN), idSinPrefijo (ID sin "TT") e idCorto (menos de 5 dígitos).
function parsear(texto) {
  const bloques = [];
  let bloque = null, seccion = null;
  for (const bruta of String(texto || '').split(/\r?\n/)) {
    const l = limpiar(bruta);
    if (!l) continue;
    const mDia = sinAcentos(l).match(RX_DIA);
    if (mDia) { bloque = { etiqueta: mDia[1].toLowerCase(), items: [] }; bloques.push(bloque); seccion = null; continue; }
    if (RX_SECCION.test(l)) {
      if (!bloque) { bloque = { etiqueta: 'hoy', items: [] }; bloques.push(bloque); }
      seccion = l.replace(/:$/, '').trim().toLowerCase(); continue;
    }
    if (!bloque || RX_EVENTO.test(l)) continue;
    const item = { linea: l, seccion, tt: null, idSinPrefijo: false, estatus: l, contador: null, tipo: null, codigo: null };
    // Caso sin ID (urgencia): TTsinid1, TTsinid2… hasta que recibe su TT
    let m = l.match(/\bTT\s*-?\s*(\d+)|\bTT\s*sin\s*id\s*(\d+)/i);
    if (m) { item.tt = m[1] ? 'TT' + m[1] : 'TTsinid' + m[2]; item.sinId = !m[1]; }
    else if ((m = l.match(/^(\d{5,6})\b/))) { item.tt = 'TT' + m[1]; item.idSinPrefijo = true; }
    if (item.tt) {
      const i = l.indexOf(':');
      item.crudo = item.estatus = i >= 0 ? l.slice(i + 1).trim() : l.replace(/\bTT\s*-?\s*(?:sin\s*id\s*)?\d+\s*/i, '').replace(/^\d{5,6}\s*/, '').trim();
      item.motivo = item.crudo;
      // Formato estándar con tipo y código antes de los dos puntos: "TT##### - C - RSP: ...", "TT##### - AP - R: ...", "TT##### Cambio · Pausa: ...",
      // sin tipo ("TT##### - P: ...", solo con código válido) o sin motivo ("TT##### - C - P")
      const mT = l.match(/\bTT\s*-?\s*(?:sin\s*id\s*)?\d+\s*(?:[-–·]\s*)?(?:(C|F|M|Apoyo|AP|Cambio|Fallo|Mejora)\s*[-–·]\s*)?([^:]{1,25}?)\s*(?::\s*(.*)|\.?$)/i);
      if (mT && (mT[1] || esCodigo(mT[2]))) {
        item.tipo = mT[1] ? (/^ap/i.test(mT[1]) ? 'AP' : mT[1][0].toUpperCase()) : null;
        item.codigo = esCodigo(mT[2]) ? mT[2].toUpperCase() : null;
        item.estatus = `${CODIGOS[mT[2].toUpperCase()] || mT[2]}${mT[3] ? ': ' + mT[3] : ''}`.trim();
        if (item.codigo) item.motivo = mT[3] || item.codigo;
      }
      // Cambio de ID: "(antes TT#####)" en la línea del ID nuevo
      const mA = l.match(/\bantes:?\s+(?:era\s+)?(?:el\s+)?TT\s*-?\s*(\d+)/i);
      if (mA && 'TT' + mA[1] !== item.tt) item.antes = 'TT' + mA[1];
      else if (/\(antes sin id\)/i.test(l)) item.antesSinId = true;
      const cancelado = /^cancelad[oa]\b/i.test(sinAcentos(l));
      if (cancelado && !/\bcancelad[oa]s?\b|\bcancelacion\b/i.test(sinAcentos(item.estatus))) item.estatus = 'Cancelado · ' + item.estatus;
      // Tipo del caso: el escrito (las mejoras cuentan como cambio) o el que diga el texto
      const t = sinAcentos(l).toLowerCase();
      item.tipoCaso = item.tipo ? (item.tipo === 'M' ? 'C' : item.tipo)
        : /\bapoyo\b/.test(t) ? 'AP' : /\bfallo\b/.test(t) ? 'F' : /\b(cambio|mejora)\b/.test(t) ? 'C' : null;
      item.etapa = item.codigo ? ETAPA_CODIGO[item.codigo] : etapaTexto(item.motivo, seccion);
      if (/como tester/i.test(l)) item.etapa = 'tester';
      if (cancelado) item.etapa = 'cierre';
      // Fecha en que el cliente dio por bueno: "RSP: ... Fecha Entrega dd/mm/aaaa"
      const mF = item.motivo.match(/fecha\s+(?:de\s+)?entrega:?\s*(\d{1,2}\/\d{1,2}\/\d{2,4})/i);
      if (mF) item.fechaEntrega = fechaDmy(mF[1]);
    }
    const c = item.estatus.match(/(?:^|[a-záéíóú\s)])x\s?(\d{1,2})\b(?!\s*[a-z])/i);
    if (c) item.contador = +c[1];
    item.idCorto = item.tt && !item.sinId && item.tt.length - 2 < 5;
    bloque.items.push(item);
  }
  return bloques;
}
// Bloque "Hoy" de un standup (con el formato anterior a 08/10/2026, el último bloque)
const bloqueHoy = bloques => bloques.find(b => b.etiqueta === 'hoy') || bloques[bloques.length - 1];
// Casos con TT definitivo (5 dígitos o más) del bloque "Hoy": lo que cuenta para tiempos y carga
function casosDeHoy(texto) {
  const b = bloqueHoy(parsear(texto));
  return b ? b.items.filter(i => i.tt && !i.sinId && !i.idSinPrefijo && !i.idCorto) : [];
}

module.exports = { sinAcentos, limpiar, RX_DIA, RX_SECCION, RX_EVENTO, CODIGOS, CODIGOS_TESTER, ETAPA_CODIGO, esCodigo, etapaTexto,
  parsear, bloqueHoy, casosDeHoy };
