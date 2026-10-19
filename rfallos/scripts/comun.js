// Utilidades compartidas por extraer.js y generar.js
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

// RFALLOS_RAIZ permite apuntar a otra carpeta (pruebas)
const RAIZ = process.env.RFALLOS_RAIZ || 'C:/Users/jorge/Dropbox/MTTO/Reportes Mensuales/Indicadores';
const OBJETIVOS = { P1: 2, P2: 4, P3: 8, P4: 12 };

// Valida YYYYMM y arma rutas de la carpeta del mes
function rutasMes(clave) {
  if (!/^\d{6}$/.test(clave || '')) throw new Error(`Clave inválida "${clave}". Formato esperado: YYYYMM (ej. 202609).`);
  const anio = clave.slice(0, 4), mes = clave.slice(4);
  if (+mes < 1 || +mes > 12) throw new Error(`Mes inválido en "${clave}".`);
  const carpeta = path.join(RAIZ, clave);
  if (!fs.existsSync(carpeta)) throw new Error(`No existe la carpeta ${carpeta}.`);
  const prefijo = mes + anio;
  const salida = path.join(carpeta, `${prefijo}_RelacionFallosAtendidos.xlsx`);
  const candidatos = fs.readdirSync(carpeta).filter(f =>
    /RelacionFallosAtendidos/i.test(f) && /\.(xls|xlsx|csv)$/i.test(f) && !f.startsWith('~$') &&
    path.join(carpeta, f) !== salida);
  const preferido = candidatos.find(f => f.toLowerCase() === `${prefijo}_relacionfallosatendidos.xls`);
  const entrada = preferido || (candidatos.length === 1 ? candidatos[0] : null);
  if (!entrada) throw new Error(candidatos.length
    ? `Hay varios archivos de casos en ${carpeta}: ${candidatos.join(', ')}. Indica cuál usar.`
    : `No se encontró la exportación de VTiger (*RelacionFallosAtendidos*.xls) en ${carpeta}.`);
  return { anio: +anio, mes: +mes, carpeta, entrada: path.join(carpeta, entrada), salida };
}

// Fecha VTiger "dd-mm-aaaa[ hh:mm:ss]" o serial de Excel → Date UTC a medianoche
function fecha(v) {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number') { const d = XLSX.SSF.parse_date_code(v); return new Date(Date.UTC(d.y, d.m - 1, d.d)); }
  const m = String(v).trim().match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
  if (!m) throw new Error(`Fecha no reconocida: "${v}"`);
  return new Date(Date.UTC(+m[3], +m[2] - 1, +m[1]));
}

const NOMBRES = {
  id: 'Id Caso', titulo: 'Título', tipo: 'Tipo', estatus: 'Estatus fallo',
  asignacion: 'Asignación de caso', respuesta: 'Fecha real de respuesta'
};

function leerCasos(archivo) {
  const wb = XLSX.readFile(archivo);
  const filas = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { raw: true, defval: null });
  if (!filas.length) throw new Error('La exportación no tiene casos.');
  const faltan = Object.values(NOMBRES).filter(n => !(n in filas[0]));
  if (faltan.length) throw new Error(`Faltan columnas en la exportación: ${faltan.join(', ')}`);
  return filas.filter(f => f[NOMBRES.id]).map(f => ({
    id: String(f[NOMBRES.id]).trim(),
    titulo: String(f[NOMBRES.titulo] || '').trim(),
    tipo: f[NOMBRES.tipo],
    estatus: f[NOMBRES.estatus],
    asignacion: fecha(f[NOMBRES.asignacion]),
    respuesta: fecha(f[NOMBRES.respuesta])
  }));
}

// Días de descanso obligatorio en México (LFT art. 74)
function nLunes(anio, mes, n) {
  const d = new Date(Date.UTC(anio, mes, 1));
  const desfase = (8 - d.getUTCDay()) % 7;
  return new Date(Date.UTC(anio, mes, 1 + desfase + 7 * (n - 1)));
}
function feriados(anio) {
  const l = [
    new Date(Date.UTC(anio, 0, 1)), nLunes(anio, 1, 1), nLunes(anio, 2, 3),
    new Date(Date.UTC(anio, 4, 1)), new Date(Date.UTC(anio, 8, 16)),
    nLunes(anio, 10, 3), new Date(Date.UTC(anio, 11, 25))
  ];
  if ((anio - 2024) % 6 === 0) l.push(new Date(Date.UTC(anio, 9, 1)));
  return l;
}
function feriadosEntre(ini, fin) {
  const r = [];
  for (let a = ini.getUTCFullYear(); a <= fin.getUTCFullYear(); a++)
    for (const f of feriados(a)) if (f >= ini && f <= fin && f.getUTCDay() % 6 !== 0) r.push(f);
  return r.sort((a, b) => a - b);
}

// Equivalente a NETWORKDAYS (inclusivo en ambos extremos)
function diasHabiles(a, b, fer) {
  const set = new Set(fer.map(f => f.getTime()));
  let n = 0;
  for (let t = a.getTime(); t <= b.getTime(); t += 864e5) {
    const w = new Date(t).getUTCDay();
    if (w !== 0 && w !== 6 && !set.has(t)) n++;
  }
  return n;
}

const dmy = d => d ? `${String(d.getUTCDate()).padStart(2, '0')}/${String(d.getUTCMonth() + 1).padStart(2, '0')}/${d.getUTCFullYear()}` : null;
const esCancelado = c => String(c.estatus || '').trim().toLowerCase() === 'cancelado';

module.exports = { RAIZ, OBJETIVOS, rutasMes, leerCasos, feriadosEntre, diasHabiles, dmy, esCancelado };
