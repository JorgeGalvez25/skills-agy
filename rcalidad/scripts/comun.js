// Utilidades compartidas por preparar.js, eventos.js y generar.js
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

// RCALIDAD_RAIZ permite apuntar a otra carpeta (pruebas)
const RAIZ = process.env.RCALIDAD_RAIZ || 'C:/Users/jorge/Dropbox/MTTO/Reportes Mensuales/Indicadores';
const DIAS_SEGUIMIENTO = 30;
// Umbrales [EXCELENTE, BUENO, REGULAR] de la Hoja1
const MATRIZ = { cambios: [0.98, 0.95, 0.90], fallos: [0.97, 0.93, 0.85] };
// Slack muestra los mensajes en hora MST (UTC-7)
const DESFASE_SLACK_H = -7;

const utc = (a, m, d) => new Date(Date.UTC(a, m - 1, d));
const sumarDias = (d, n) => new Date(d.getTime() + n * 864e5);
const pad = n => String(n).padStart(2, '0');
const dmy = d => d ? `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}` : null;
const iso = d => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
const hoy = () => { const n = new Date(); return utc(n.getFullYear(), n.getMonth() + 1, n.getDate()); };

// Fecha "dd/mm/aaaa", "dd-mm-aaaa", serial de Excel o Date → Date UTC a medianoche
function fecha(v) {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date) return utc(v.getUTCFullYear(), v.getUTCMonth() + 1, v.getUTCDate());
  if (typeof v === 'number') { const d = XLSX.SSF.parse_date_code(v); return utc(d.y, d.m, d.d); }
  const m = String(v).trim().match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})\b/);
  if (!m) throw new Error(`Fecha no reconocida: "${v}"`);
  const a = m[3].length === 2 ? 2000 + +m[3] : +m[3];
  const d = utc(a, +m[2], +m[1]);
  if (d.getUTCMonth() + 1 !== +m[2]) throw new Error(`Fecha inválida: "${v}"`);
  return d;
}

// Timestamp de Slack ("1790575200.123") → fecha local del mensaje
const fechaSlack = ts => { const d = new Date((parseFloat(ts) + DESFASE_SLACK_H * 3600) * 1000); return utc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()); };

// Normaliza "TT 106390", "tt106390" → "TT106390"
const tt = s => { const m = String(s || '').match(/TT\s*-?\s*(\d{4,})/i); return m ? 'TT' + m[1] : null; };
const numTT = s => +String(s).replace(/\D/g, '');

// Valida YYYYMM (mes que se reporta y se evalúa) y arma el periodo y las rutas
function periodo(clave) {
  if (!/^\d{6}$/.test(clave || '')) throw new Error(`Clave inválida "${clave}". Formato esperado: YYYYMM (ej. 202609).`);
  const a = +clave.slice(0, 4), m = +clave.slice(4);
  if (m < 1 || m > 12) throw new Error(`Mes inválido en "${clave}".`);
  const inicio = utc(a, m, 1), fin = sumarDias(m === 12 ? utc(a + 1, 1, 1) : utc(a, m + 1, 1), -1);
  const carpeta = path.join(RAIZ, clave);
  const prefijo = pad(m) + a;
  return {
    clave, inicio, fin,
    // Lo liberado o cerrado el último día del mes termina su seguimiento aquí
    finSeguimiento: sumarDias(fin, DIAS_SEGUIMIENTO),
    carpeta,
    salidaCambios: path.join(carpeta, `${prefijo}_TasaExitoCambios.xlsx`),
    salidaFallos: path.join(carpeta, `${prefijo}_ResolucionDefinitivaFallos.xlsx`),
    relacionFallos: path.join(carpeta, `${prefijo}_RelacionFallosAtendidos.xlsx`)
  };
}

// Lee el detalle de la relación generada por /rfallos (hasta la fila "Promedio")
function leerRelacionFallos(archivo) {
  const wb = XLSX.readFile(archivo);
  const ws = wb.Sheets[wb.SheetNames[0]];
  const filas = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null });
  const enc = (filas[0] || []).map(v => String(v || '').trim());
  if (enc[0] !== 'Título' || enc[1] !== 'Criticidad' || enc[3] !== 'Fecha real de respuesta')
    throw new Error(`${archivo} no tiene el formato de /rfallos (Título | Criticidad | Asignación | Fecha real de respuesta ...).`);
  const casos = [];
  for (let i = 1; i < filas.length; i++) {
    const f = filas[i];
    if (!f[0] || f[3] === 'Promedio' || f[0] === 'Criticidad') break;
    casos.push({ tt: tt(f[0]), titulo: String(f[0]).trim(), criticidad: String(f[1] || '').trim(), fecha: fecha(f[3]) });
  }
  return casos;
}

const clasificar = (pct, umbrales) => pct === null ? 'N/A'
  : pct >= umbrales[0] ? 'EXCELENTE' : pct >= umbrales[1] ? 'BUENO' : pct >= umbrales[2] ? 'REGULAR' : 'NO ACEPTABLE';

module.exports = {
  RAIZ, DIAS_SEGUIMIENTO, MATRIZ, utc, sumarDias, dmy, iso, hoy, fecha, fechaSlack, tt, numTT,
  periodo, leerRelacionFallos, clasificar
};
