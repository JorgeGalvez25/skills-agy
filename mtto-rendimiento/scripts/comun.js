// Utilidades compartidas por datos.js y generar.js
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

const MTTO = 'C:/Users/jorge/Dropbox/MTTO';
const RAIZ = process.env.RENDIMIENTO_RAIZ || `${MTTO}/Reportes Mensuales/Rendimiento`;
const RUTAS = {
  raiz: RAIZ,
  datos: `${RAIZ}/datos`,
  standups: `${RAIZ}/datos/standups.json`,           // caché acumulada de mensajes de #mtto
  atribuciones: `${RAIZ}/datos/atribuciones.json`,   // decisiones de Jorge: { "TT#####": "Nombre Apellido" }
  procesos: `${MTTO}/ReportesMTTO/CambiosProceso.xlsm`,
  indicadores: `${MTTO}/Reportes Mensuales/Indicadores`,
  versiones: `${MTTO}/Versiones`
};
const INICIO_DATOS = '2026-09-01';   // primer día leído de #mtto
const MUESTRA_MIN = 3;               // casos mínimos para concluir fortaleza o dificultad
const DESFASE_SLACK_H = -7;          // Slack muestra los mensajes en MST (UTC-7)
const OBJETIVOS = { P1: 2, P2: 4, P3: 8, P4: 12 };

const EQUIPO = ['Saulo López', 'Miguel Armenta', 'Martín Reyes', 'Susana Gámez'];
const sinAcentos = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
// "Saulo Lopez", "susana", "Gamez" → nombre oficial
function colaborador(nombre) {
  const n = sinAcentos(nombre).toLowerCase();
  if (!n.trim()) return null;
  return EQUIPO.find(e => sinAcentos(e).toLowerCase().split(' ').some(p => p.length > 3 && n.includes(p))) || null;
}

// Fechas: Date UTC a medianoche
const utc = (a, m, d) => new Date(Date.UTC(a, m - 1, d));
const pad = n => String(n).padStart(2, '0');
const iso = d => d ? `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` : null;
const dmy = d => d ? `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}` : null;
const deIso = s => s ? utc(+s.slice(0, 4), +s.slice(5, 7), +s.slice(8, 10)) : null;
const hoy = () => { const n = new Date(); return utc(n.getFullYear(), n.getMonth() + 1, n.getDate()); };
function fecha(v) {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date) return utc(v.getUTCFullYear(), v.getUTCMonth() + 1, v.getUTCDate());
  if (typeof v === 'number') { const d = XLSX.SSF.parse_date_code(v); return utc(d.y, d.m, d.d); }
  const m = String(v).trim().match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})\b/);
  if (!m) return null;
  return utc(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[2], +m[1]);
}
const fechaSlack = ts => { const d = new Date((parseFloat(ts) + DESFASE_SLACK_H * 3600) * 1000); return utc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()); };
// "2026-10-06 16:08" (fecha de Slack ya en MST) o ts
const fechaMensaje = m => m.fecha && /^\d{4}-\d{2}-\d{2}/.test(m.fecha) ? deIso(m.fecha.slice(0, 10)) : fechaSlack(m.ts);

// Días de descanso obligatorio (LFT art. 74) y días hábiles inclusivos, como NETWORKDAYS
function nLunes(a, mes, n) { const d = new Date(Date.UTC(a, mes, 1)); return new Date(Date.UTC(a, mes, 1 + (8 - d.getUTCDay()) % 7 + 7 * (n - 1))); }
const cacheFer = {};
function feriados(a) {
  if (!cacheFer[a]) {
    const l = [utc(a, 1, 1), nLunes(a, 1, 1), nLunes(a, 2, 3), utc(a, 5, 1), utc(a, 9, 16), nLunes(a, 10, 3), utc(a, 12, 25)];
    if ((a - 2024) % 6 === 0) l.push(utc(a, 10, 1));
    cacheFer[a] = new Set(l.map(d => d.getTime()));
  }
  return cacheFer[a];
}
function habiles(a, b) {
  if (!a || !b || b < a) return null;
  let n = 0;
  for (let t = a.getTime(); t <= b.getTime(); t += 864e5) {
    const d = new Date(t);
    if (d.getUTCDay() % 6 !== 0 && !feriados(d.getUTCFullYear()).has(t)) n++;
  }
  return n;
}

function periodo(clave) {
  if (!/^\d{6}$/.test(clave || '')) throw new Error(`Clave inválida "${clave}". Formato esperado: YYYYMM (ej. 202610).`);
  const a = +clave.slice(0, 4), m = +clave.slice(4);
  if (m < 1 || m > 12) throw new Error(`Mes inválido en "${clave}".`);
  const inicio = utc(a, m, 1), fin = new Date(utc(m === 12 ? a + 1 : a, m === 12 ? 1 : m + 1, 1).getTime() - 864e5);
  const carpeta = `${RAIZ}/${clave}`;
  return { clave, inicio, fin, carpeta, salida: `${carpeta}/${pad(m)}${a}_RendimientoColaboradores.xlsx` };
}

// TT: "TT 106390", "tt106390" → "TT106390"
const tt = s => { const m = String(s || '').match(/TT\s*-?\s*(\d{5,})/i); return m ? 'TT' + m[1] : null; };
const numTT = s => +String(s).replace(/\D/g, '');

// Módulo y cliente del título "TT##### -CLIENTE-MÓDULO-DESCRIPCIÓN"
const ALIAS_MODULO = { KIOSKO: 'KIOSCO', 'IGAS ADMINISTRADOR': 'ADMINISTRADOR', LIQUIDACION: 'LIQUIDACIONES', REPORTE: 'REPORTES', FACTURA: 'FACTURACION', 'APOYO SOPORTE': 'APOYO A SOPORTE' };
function partesTitulo(titulo) {
  const s = sinAcentos(String(titulo || '')).toUpperCase().replace(/^\s*TT\s*-?\s*\d+\s*/, '');
  const p = s.split(/\s*-\s*/).map(x => x.trim()).filter(Boolean);
  let modulo = p[1] || null;
  if (modulo) modulo = ALIAS_MODULO[modulo] || modulo;
  // "APOYO A SOPORTE-KIOSCO-..." : el módulo real es el siguiente
  if (modulo === 'APOYO A SOPORTE' && p[2] && p.length > 3) modulo = ALIAS_MODULO[p[2]] || p[2];
  // "-CLIENTE-CAMBIO-DESCRIPCIÓN": el título no trae módulo
  if (['CAMBIO', 'MEJORA', 'FALLO', 'APOYO A SOPORTE'].includes(modulo)) modulo = null;
  return { cliente: p[0] || null, modulo };
}

// ---- Standups ----
const limpiar = l => l.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
  .replace(/<@[^>]+>/g, '').replace(/[*_~`]/g, '').replace(/^[\s•◦▪︎\->]*(:[a-z0-9_+\-]+:\s*)*/i, '').trim();
const RX_DIA = /^(ayer|hoy|viernes|lunes|martes|miercoles|jueves|sabado|domingo)\s*:?\s*$/i;
const RX_SECCION = /^(standby|stand by|seguimiento)\s*:?\s*$/i;
const RX_EVENTO = /^(LDP|LIBERADO|REABIERTO|ORIGEN)\s+TT/i;
const CODIGOS = ['P', 'R', 'AN', 'D', 'PIL', 'ENT', 'EST', 'CAN', 'RSP', 'REVPR', 'ESPLDP', 'BUGPRU', 'PRU', 'ESPBUG', 'FINPRU', 'LDP', 'CEC'];
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

// Un standup → items { tt, tipo, codigo, etapa, estatus, seccion, antes }
function parsearStandup(texto) {
  const bloques = []; let bloque = null, seccion = null;
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
    let m = l.match(/\bTT\s*-?\s*(\d{5,})/i);
    if (!m) continue;
    const item = { tt: 'TT' + m[1], seccion, linea: l, tipo: null, codigo: null };
    const i = l.indexOf(':');
    item.estatus = i >= 0 ? l.slice(i + 1).trim() : l.replace(/\bTT\s*-?\s*\d+\s*/i, '').trim();
    const mT = l.match(/\bTT\s*-?\s*\d+\s*(?:[-–·]\s*)?(?:(C|F|M|Apoyo|AP|Cambio|Fallo|Mejora)\s*[-–·]\s*)?([^:]{1,25}?)\s*(?::\s*(.*)|\.?$)/i);
    if (mT) {
      if (mT[1]) item.tipo = /^ap/i.test(mT[1]) ? 'AP' : /^(c|m)/i.test(mT[1]) ? 'C' : 'F';
      const cod = (mT[2] || '').trim().toUpperCase();
      if (CODIGOS.includes(cod)) { item.codigo = cod; item.estatus = mT[3] || cod; }
    }
    if (!item.tipo) {
      const t = sinAcentos(l).toLowerCase();
      if (/\bapoyo\b/.test(t)) item.tipo = 'AP'; else if (/\bfallo\b/.test(t)) item.tipo = 'F'; else if (/\b(cambio|mejora)\b/.test(t)) item.tipo = 'C';
    }
    item.etapa = item.codigo ? ETAPA_CODIGO[item.codigo] : etapaTexto(item.estatus, seccion);
    if (/como tester/i.test(l)) item.etapa = 'tester';
    if (/^cancelad[oa]\b/i.test(sinAcentos(l))) item.etapa = 'cierre';
    const mA = l.match(/\bantes:?\s+(?:era\s+)?(?:el\s+)?TT\s*-?\s*(\d+)/i);
    if (mA && 'TT' + mA[1] !== item.tt) item.antes = 'TT' + mA[1];
    // Fecha en que el cliente dio por bueno: "RSP: ... Fecha Entrega dd/mm/aaaa"
    const mF = item.estatus.match(/fecha\s+(?:de\s+)?entrega:?\s*(\d{1,2}\/\d{1,2}\/\d{2,4})/i);
    if (mF) item.fechaEntrega = fecha(mF[1]);
    bloque.items.push(item);
  }
  const hoyB = bloques.find(b => b.etiqueta === 'hoy') || bloques[bloques.length - 1];
  return hoyB ? hoyB.items : [];
}

// Lectores de archivos
function leerHoja(archivo, hoja) {
  const wb = XLSX.readFile(archivo, { cellDates: false });
  return XLSX.utils.sheet_to_json(wb.Sheets[hoja || wb.SheetNames[0]], { header: 1, raw: true, defval: null });
}
const leerJson = (f, def) => fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : def;

const mediana = a => { if (!a.length) return null; const s = [...a].sort((x, y) => x - y), k = s.length >> 1; return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2; };
const promedio = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : null;

module.exports = { fs, path, XLSX, RUTAS, INICIO_DATOS, MUESTRA_MIN, OBJETIVOS, EQUIPO, colaborador, sinAcentos,
  utc, iso, dmy, deIso, hoy, fecha, fechaSlack, fechaMensaje, habiles, periodo, tt, numTT, partesTitulo,
  parsearStandup, leerHoja, leerJson, mediana, promedio };
