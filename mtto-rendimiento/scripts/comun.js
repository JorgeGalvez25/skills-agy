// Utilidades compartidas por datos.js y generar.js
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');
// Equipo, días hábiles y parser de standups: compartidos por todas las skills
const COMUN = path.join(__dirname, '..', '..', 'mtto-comun');
const { EQUIPO, colaborador, sinAcentos } = require(path.join(COMUN, 'equipo'));
const F = require(path.join(COMUN, 'fechas'));
const { casosDeHoy } = require(path.join(COMUN, 'standup'));
const canal = require(path.join(COMUN, 'canal'));

const MTTO = 'C:/Users/jorge/Dropbox/MTTO';
const RAIZ = process.env.RENDIMIENTO_RAIZ || `${MTTO}/Reportes Mensuales/Rendimiento`;
const RUTAS = {
  raiz: RAIZ,
  datos: `${RAIZ}/datos`,
  standups: canal.RUTA,                              // caché compartida de mensajes de #mtto (mtto-comun/canal.js)
  atribuciones: `${RAIZ}/datos/atribuciones.json`,   // decisiones de Jorge: { "TT#####": "Nombre Apellido" }
  procesos: `${MTTO}/ReportesMTTO/CambiosProceso.xlsm`,
  indicadores: `${MTTO}/Reportes Mensuales/Indicadores`,
  versiones: `${MTTO}/Versiones`
};
const INICIO_DATOS = '2026-09-01';   // primer día leído de #mtto
const MUESTRA_MIN = 3;               // casos mínimos para concluir fortaleza o dificultad
const OBJETIVOS = { P1: 2, P2: 4, P3: 8, P4: 12 };

// Fechas: Date UTC a medianoche
const { utc, pad, iso, dmy, deIso, hoy, habiles } = F;
function fecha(v) {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date) return utc(v.getUTCFullYear(), v.getUTCMonth() + 1, v.getUTCDate());
  if (typeof v === 'number') { const d = XLSX.SSF.parse_date_code(v); return utc(d.y, d.m, d.d); }
  const m = String(v).trim().match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})\b/);
  if (!m) return null;
  return utc(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[2], +m[1]);
}
// Día del mensaje: "2026-10-06 16:08" (fecha de Slack ya en MST) o ts
const fechaMensaje = m => F.fechaMensaje(m).dia;

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

// Casos del standup (bloque "Hoy") con los campos que usa datos.js; el parser es el de mtto-comun/standup.js
const parsearStandup = texto => casosDeHoy(texto).map(i => ({ tt: i.tt, seccion: i.seccion, linea: i.linea, tipo: i.tipoCaso, codigo: i.codigo,
  estatus: i.motivo, etapa: i.etapa, ...(i.antes ? { antes: i.antes } : {}), ...(i.fechaEntrega ? { fechaEntrega: i.fechaEntrega } : {}) }));

// Lectores de archivos
function leerHoja(archivo, hoja) {
  const wb = XLSX.readFile(archivo, { cellDates: false });
  return XLSX.utils.sheet_to_json(wb.Sheets[hoja || wb.SheetNames[0]], { header: 1, raw: true, defval: null });
}
const leerJson = (f, def) => fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : def;

const mediana = a => { if (!a.length) return null; const s = [...a].sort((x, y) => x - y), k = s.length >> 1; return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2; };
const promedio = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : null;

module.exports = { fs, path, XLSX, RUTAS, INICIO_DATOS, MUESTRA_MIN, OBJETIVOS, EQUIPO, colaborador, sinAcentos,
  utc, iso, dmy, deIso, hoy, fecha, fechaMensaje, habiles, canal, periodo, tt, numTT, partesTitulo,
  parsearStandup, leerHoja, leerJson, mediana, promedio };
