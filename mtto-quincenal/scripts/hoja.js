// Lee o agrega hojas del reporte quincenal "Casos por Desarrollador".
//   node hoja.js leer    <xlsx> [hoja]                      -> JSON con las filas de la hoja (default: la última)
//   node hoja.js titulos <CambiosProceso.xlsx>               -> JSON { "TT#####": "título completo" }
//   node hoja.js generar <xlsx> <spec.json> [--sobrescribir] -> agrega la hoja descrita en spec.json
//
// spec.json:
// { "hoja": "13-10",
//   "filas": [ { "dev": "Saulo", "caso": "TT104919 -EL TREBOL-...", "estatus": "Proceso", "obs": "...", "fecha": "2026-10-20", "nota": "..." } ],
//   "captura": { "dev": "Jorge", "filas": 5 } }
// "fecha" (opcional, AAAA-MM-DD) va en "Fecha cierre"; "nota" (opcional) se agrega como comentario de la celda Caso.
// "captura" agrega al final filas vacías con el color del desarrollador para llenarlas a mano.

const path = require('path');
const fs = require('fs');
const ExcelJS = require('exceljs');

const COLORES = {
  Saulo: 'FFD9E1F2',
  Miguel: 'FFE2EFDA',
  'Martín': 'FFFFF2CC',
  Susana: 'FFFCE4EC',
  Jorge: 'FFE4DFEC',
};
const COLOR_OTRO = 'FFEDEDED';
const BORDE = { style: 'thin', color: { argb: 'FFB0B0B0' } };
const BORDES = { left: BORDE, right: BORDE, top: BORDE, bottom: BORDE };
const TITULO = 'Seguimiento de Casos por Desarrollador';
const COLUMNAS = [
  { campo: 'dev', titulo: 'Desarrollador', ancho: 18, al: { horizontal: 'center', vertical: 'middle' } },
  { campo: 'caso', titulo: 'Caso', ancho: 92, al: { horizontal: 'left', vertical: 'middle', wrapText: true } },
  { campo: 'estatus', titulo: 'Estatus', ancho: 17.43, al: { horizontal: 'left', vertical: 'middle', wrapText: true } },
  { campo: 'obs', titulo: 'Observaciones', ancho: 37.14, al: { horizontal: 'left', vertical: 'middle', wrapText: true } },
  { campo: 'fecha', titulo: 'Fecha cierre', ancho: 16.29, al: { horizontal: 'center', vertical: 'middle' } },
];
const N = COLUMNAS.length;
const COL_FECHA = COLUMNAS.findIndex(c => c.campo === 'fecha') + 1;

function texto(v) {
  if (v == null) return '';
  if (v.richText) return v.richText.map(t => t.text).join('');
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (typeof v === 'object' && 'result' in v) return texto(v.result);
  return String(v);
}

// Ubica cada campo por el encabezado de la fila 2 (las hojas antiguas no tienen "Estatus").
function mapaColumnas(ws) {
  const mapa = {};
  ws.getRow(2).eachCell((c, k) => {
    const col = COLUMNAS.find(x => x.titulo.toLowerCase() === texto(c.value).trim().toLowerCase());
    if (col) mapa[col.campo] = k;
  });
  return mapa;
}

async function abrir(archivo) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(archivo);
  return wb;
}

async function leer(archivo, nombre) {
  const wb = await abrir(archivo);
  const ws = nombre ? wb.getWorksheet(nombre) : wb.worksheets[wb.worksheets.length - 1];
  if (!ws) throw new Error(`No existe la hoja ${nombre}`);
  const cols = mapaColumnas(ws);
  const filas = [];
  ws.eachRow((row, i) => {
    if (i < 3) return;
    const f = { fila: i };
    for (const { campo } of COLUMNAS) f[campo] = cols[campo] ? texto(row.getCell(cols[campo]).value).trim() : '';
    if (f.dev || f.caso) filas.push(f);
  });
  return { hojas: wb.worksheets.map(w => w.name), hoja: ws.name, filas };
}

async function titulos(archivo) {
  const wb = await abrir(archivo);
  const ws = wb.worksheets[0];
  const mapa = {};
  ws.eachRow((row, i) => {
    if (i === 1) return;
    const id = texto(row.getCell(1).value).trim().toUpperCase();
    const desc = texto(row.getCell(2).value).replace(/\s+/g, ' ').trim();
    if (/^TT\d+$/.test(id) && desc) mapa[id] = { titulo: desc, dev: texto(row.getCell(3).value).trim(), estatus: texto(row.getCell(4).value).trim() };
  });
  return mapa;
}

function estiloFila(ws, r, argb) {
  const fill = { type: 'pattern', pattern: 'solid', fgColor: { argb } };
  const fuente = { name: 'Arial', size: 11, color: { argb: 'FF000000' } };
  for (let k = 1; k <= N; k++) {
    const c = ws.getCell(r, k);
    c.fill = fill;
    c.border = BORDES;
    c.alignment = COLUMNAS[k - 1].al;
    c.font = k === 1 ? { ...fuente, bold: true } : fuente;
  }
  ws.getCell(r, COL_FECHA).numFmt = 'd-mmm';
  ws.getRow(r).height = 28.5;
}

async function generar(archivo, specPath, sobrescribir) {
  const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
  if (!spec.hoja || !Array.isArray(spec.filas)) throw new Error('spec.json requiere "hoja" y "filas"');
  const wb = await abrir(archivo);
  const previa = wb.worksheets[wb.worksheets.length - 1];
  if (wb.getWorksheet(spec.hoja)) {
    if (!sobrescribir) throw new Error(`La hoja ${spec.hoja} ya existe (usa --sobrescribir con autorización)`);
    wb.removeWorksheet(wb.getWorksheet(spec.hoja).id);
  }
  const ws = wb.addWorksheet(spec.hoja, {
    views: [{ showGridLines: false, zoomScale: 115, zoomScaleNormal: 115 }],
    properties: { defaultRowHeight: 15 },
  });
  // Anchos de la hoja anterior por encabezado; si no tiene la columna, el default.
  const colsPrevia = mapaColumnas(previa);
  ws.columns = COLUMNAS.map(c => ({ width: (colsPrevia[c.campo] && previa.getColumn(colsPrevia[c.campo]).width) || c.ancho }));

  ws.mergeCells(1, 1, 1, N);
  const t = ws.getCell('A1');
  t.value = TITULO;
  t.font = { name: 'Arial', size: 16, bold: true, color: { argb: 'FFFFFFFF' } };
  t.alignment = { horizontal: 'center', vertical: 'middle' };
  t.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F4E78' } };
  ws.getRow(1).height = 20.25;

  COLUMNAS.forEach((col, i) => {
    const c = ws.getCell(2, i + 1);
    c.value = col.titulo;
    c.font = { name: 'Arial', size: 11, bold: true, color: { argb: 'FFFFFFFF' } };
    c.alignment = { horizontal: 'center', vertical: 'middle' };
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2E75B6' } };
    c.border = BORDES;
  });

  let r = 3;
  for (const f of spec.filas) {
    estiloFila(ws, r, COLORES[f.dev] || COLOR_OTRO);
    COLUMNAS.forEach((col, i) => {
      if (col.campo !== 'fecha') ws.getCell(r, i + 1).value = f[col.campo] || null;
    });
    if (f.fecha) {
      const [a, m, d] = f.fecha.split('-').map(Number);
      ws.getCell(r, COL_FECHA).value = new Date(Date.UTC(a, m - 1, d));
    }
    if (f.nota) ws.getCell(r, 2).note = f.nota;
    r++;
  }
  if (spec.captura && spec.captura.filas > 0) {
    for (let i = 0; i < spec.captura.filas; i++, r++) {
      estiloFila(ws, r, COLORES[spec.captura.dev] || COLOR_OTRO);
      ws.getCell(r, 1).value = spec.captura.dev;
    }
  }

  // Se escribe a un temporal y luego se reemplaza, para no dejar el original a medias.
  const tmp = path.join(path.dirname(archivo), `~tmp_${Date.now()}.xlsx`);
  await wb.xlsx.writeFile(tmp);
  fs.copyFileSync(tmp, archivo);
  fs.unlinkSync(tmp);
  return { archivo, hoja: spec.hoja, filas: spec.filas.length, captura: spec.captura ? spec.captura.filas : 0, hojas: wb.worksheets.map(w => w.name) };
}

(async () => {
  const [cmd, a, b] = process.argv.slice(2);
  const sobrescribir = process.argv.includes('--sobrescribir');
  let out;
  if (cmd === 'leer') out = await leer(a, b && !b.startsWith('--') ? b : null);
  else if (cmd === 'titulos') out = await titulos(a);
  else if (cmd === 'generar') out = await generar(a, b, sobrescribir);
  else throw new Error('Uso: node hoja.js leer|titulos|generar ...');
  console.log(JSON.stringify(out, null, 2));
})().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
