// Fechas, feriados y días hábiles: única fuente para todas las skills.
// Todas las fechas son Date UTC a medianoche.
const DESFASE_SLACK_H = -7;    // Slack muestra los mensajes en MST (UTC-7)

const utc = (a, m, d) => new Date(Date.UTC(a, m - 1, d));
const pad = n => String(n).padStart(2, '0');
const iso = d => d ? `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` : null;
const dmy = d => d ? `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}` : null;
const deIso = s => s ? utc(+s.slice(0, 4), +s.slice(5, 7), +s.slice(8, 10)) : null;
const hoy = () => { const n = new Date(); return utc(n.getFullYear(), n.getMonth() + 1, n.getDate()); };

// "AAAA-MM-DD[ HH:MM]" o "dd/mm/aaaa[ HH:MM]" → { dia, hora }
function leerFecha(v) {
  let m = String(v).match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?/);
  if (m) return { dia: utc(+m[1], +m[2], +m[3]), hora: m[4] ? `${pad(m[4])}:${m[5]}` : null };
  m = String(v).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?/);
  if (m) return { dia: utc(+m[3], +m[2], +m[1]), hora: m[4] ? `${pad(m[4])}:${m[5]}` : null };
  throw new Error(`Fecha no reconocida: "${v}"`);
}
// Timestamp de Slack ("1790575200.123") → { dia, hora } en la hora que muestra Slack
function fechaTs(ts) {
  const d = new Date((parseFloat(ts) + DESFASE_SLACK_H * 3600) * 1000);
  return { dia: utc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()), hora: `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}` };
}
// Mensaje de #mtto { fecha: "AAAA-MM-DD HH:MM" (la que muestra Slack) y/o ts } → { dia, hora }
const fechaMensaje = m => m.fecha && /^\d{4}-\d{2}-\d{2}/.test(m.fecha) ? leerFecha(m.fecha) : m.ts ? fechaTs(m.ts) : leerFecha(m.fecha);
// Medianoche MST de un día → timestamp Unix (para oldest/latest de Slack)
const tsDeDia = d => d.getTime() / 1000 - DESFASE_SLACK_H * 3600;

// Días de descanso obligatorio (LFT art. 74) más los días no laborables propios de la empresa (feriados-extra.json)
function nLunes(a, mes, n) { const d = new Date(Date.UTC(a, mes, 1)); return new Date(Date.UTC(a, mes, 1 + (8 - d.getUTCDay()) % 7 + 7 * (n - 1))); }
const ARCH_EXTRA = process.env.MTTO_FERIADOS_EXTRA || require('path').join(__dirname, 'feriados-extra.json');
let extra = null;
// [{ dia (Date), motivo }] de feriados-extra.json; una fecha mal escrita detiene el script en lugar de ignorarse
function feriadosExtra() {
  if (!extra) {
    const fs = require('fs');
    const d = fs.existsSync(ARCH_EXTRA) ? JSON.parse(fs.readFileSync(ARCH_EXTRA, 'utf8').replace(/^\uFEFF/, '')) : { dias: [] };
    extra = (d.dias || []).map(x => {
      const m = String(x.fecha || '').match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
      const dia = m ? utc(+m[3], +m[2], +m[1]) : null;
      if (!dia || dia.getUTCDate() !== +m[1] || dia.getUTCMonth() + 1 !== +m[2]) throw new Error(`feriados-extra.json: fecha no válida "${x.fecha}" (formato dd/mm/aaaa).`);
      return { dia, motivo: x.motivo || null };
    });
  }
  return extra;
}
const cacheFer = {};
function feriados(a) {   // Set de getTime()
  if (!cacheFer[a]) {
    const l = [utc(a, 1, 1), nLunes(a, 1, 1), nLunes(a, 2, 3), utc(a, 5, 1), utc(a, 9, 16), nLunes(a, 10, 3), utc(a, 12, 25)];
    if ((a - 2024) % 6 === 0) l.push(utc(a, 10, 1));   // transmisión del Poder Ejecutivo
    for (const x of feriadosExtra()) if (x.dia.getUTCFullYear() === a) l.push(x.dia);
    cacheFer[a] = new Set(l.map(d => d.getTime()));
  }
  return cacheFer[a];
}
// Lunes a viernes que no es feriado
const esLaborable = d => d.getUTCDay() % 6 !== 0 && !feriados(d.getUTCFullYear()).has(d.getTime());
// Feriados entre semana dentro de [ini, fin], en orden
function feriadosEntre(ini, fin) {
  const r = [];
  for (let a = ini.getUTCFullYear(); a <= fin.getUTCFullYear(); a++)
    for (const t of feriados(a)) { const f = new Date(t); if (f >= ini && f <= fin && f.getUTCDay() % 6 !== 0) r.push(f); }
  return r.sort((a, b) => a - b);
}
// Días hábiles de a a b, inclusivo en ambos extremos, como NETWORKDAYS (null si falta una fecha o b < a)
function habiles(a, b) {
  if (!a || !b || b < a) return null;
  let n = 0;
  for (let t = a.getTime(); t <= b.getTime(); t += 864e5) if (esLaborable(new Date(t))) n++;
  return n;
}

module.exports = { DESFASE_SLACK_H, utc, pad, iso, dmy, deIso, hoy, leerFecha, fechaTs, fechaMensaje, tsDeDia,
  feriados, feriadosExtra, feriadosEntre, esLaborable, habiles };
