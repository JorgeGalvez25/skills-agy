// Uso: node generar.js YYYYMM datos.json [--sobrescribir]
// datos.json: salida de eventos.js ({ cambios, reaperturas, origenes }), revisada, con un campo opcional:
//   "fallos": [{ tt, titulo, criticidad, fecha }]  sustituye la relación de /rfallos (solo en transición)
const fs = require('fs');
const ExcelJS = require('exceljs');
const { DIAS_SEGUIMIENTO, MATRIZ, periodo, leerRelacionFallos, fecha, sumarDias, dmy, hoy, numTT, clasificar } = require('./comun');

const AZUL = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4F81BD' } };
const BLANCO = { color: { argb: 'FFFFFFFF' } };
const CENTRO = { horizontal: 'center' };
const DF = 'dd/mm/yyyy';
const CRITICIDADES = ['P1', 'P2', 'P3', 'P4', 'S/C'];

function hoja(wb, anchos) {
  const ws = wb.addWorksheet('Worksheet');
  ws.columns = anchos.map(width => ({ width }));
  ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0 };
  return ws;
}
const encabezado = (ws, fila, de, a) => { for (let c = de; c <= a; c++) { const x = ws.getRow(fila).getCell(c); x.fill = AZUL; x.font = BLANCO; } };
const formulaClasif = (celda, u) => `IF(${celda}="N/A","N/A",IF(${celda}>=${u[0]},"EXCELENTE",IF(${celda}>=${u[1]},"BUENO",IF(${celda}>=${u[2]},"REGULAR","NO ACEPTABLE"))))`;

// Etiqueta (estilo encabezado) en la columna cE y valor en cV
function filaDato(ws, f, cE, cV, etiqueta, valor, numFmt) {
  const fila = ws.getRow(f);
  fila.getCell(cE).value = etiqueta;
  fila.getCell(cV).value = valor;
  if (numFmt) fila.getCell(cV).numFmt = numFmt;
  fila.getCell(cV).alignment = CENTRO;
  encabezado(ws, f, cE, cV);
}

// Reaperturas del mismo TT u ORIGEN que lo apunten, dentro de [base, base + 30 días]
// Cambios (desdeEntrega): la reapertura ocurre entre el RSP y la LDP, así que cuenta todo lo anterior
// a la LDP más los 30 días posteriores. Fallos: los 30 días posteriores a la fecha real de respuesta.
function incidencias(id, base, datos, desdeEntrega) {
  const lim = sumarDias(base, DIAS_SEGUIMIENTO);
  const dentro = f => { const d = fecha(f); return (desdeEntrega || d >= base) && d <= lim; };
  return [
    ...datos.reaperturas.filter(r => r.tt === id && dentro(r.fecha))
      .map(r => ({ fecha: fecha(r.fecha), texto: `Reabierto${r.motivo ? ': ' + r.motivo : ''}` })),
    ...datos.origenes.filter(o => o.anterior === id && dentro(o.fecha))
      .map(o => ({ fecha: fecha(o.fecha), texto: `${o.nuevo}${o.causa ? ': ' + o.causa : ''}` }))
  ].sort((a, b) => a.fecha - b.fecha);
}

function resumenTexto(inc) { return inc.length ? inc.map(i => i.texto).join(' | ') : ''; }

async function reporteCambios(p, cambios, salida) {
  const wb = new ExcelJS.Workbook();
  const ws = hoja(wb, [14, 10, 36, 24, 20, 60, 20, 10]);
  ws.addRow(['Caso', 'Tipo', 'Cliente', 'Fecha de liberación', 'Fin de seguimiento', 'Incidencia atribuible', 'Fecha de incidencia', 'Sin fallo']);
  encabezado(ws, 1, 1, 8);
  const primera = 2, ultima = primera + Math.max(cambios.length, 1) - 1;
  if (!cambios.length) ws.addRow(['Sin cambios ni mejoras liberados en el periodo']);
  cambios.forEach((c, i) => {
    const f = primera + i;
    const fila = ws.addRow([c.tt, c.tipo, c.cliente, c.f,
      { formula: `D${f}+${DIAS_SEGUIMIENTO}`, result: sumarDias(c.f, DIAS_SEGUIMIENTO) },
      resumenTexto(c.inc), c.inc.length ? c.inc[0].fecha : null,
      { formula: `IF(F${f}="","Sí","No")`, result: c.ok ? 'Sí' : 'No' }]);
    fila.getCell(4).numFmt = fila.getCell(5).numFmt = fila.getCell(7).numFmt = DF;
    for (const k of [1, 2, 4, 5, 7, 8]) fila.getCell(k).alignment = CENTRO;
    fila.getCell(6).alignment = { wrapText: true, vertical: 'top' };
  });

  const n = cambios.length, ok = cambios.filter(c => c.ok).length, pct = n ? ok / n : null;
  const r0 = ultima + 2;
  filaDato(ws, r0, 3, 4, 'Periodo evaluado', `${dmy(p.inicio)} – ${dmy(p.fin)}`);
  filaDato(ws, r0 + 1, 3, 4, 'Cambios evaluables', n ? { formula: `COUNTA(A${primera}:A${ultima})`, result: n } : 0);
  filaDato(ws, r0 + 2, 3, 4, 'Sin fallo atribuible', n ? { formula: `COUNTIF(H${primera}:H${ultima},"Sí")`, result: ok } : 0);
  filaDato(ws, r0 + 3, 3, 4, 'Tasa de éxito', { formula: `IF(D${r0 + 1}=0,"N/A",D${r0 + 2}/D${r0 + 1})`, result: pct === null ? 'N/A' : pct }, '0.00%');
  filaDato(ws, r0 + 4, 3, 4, 'Clasificación', { formula: formulaClasif(`D${r0 + 3}`, MATRIZ.cambios), result: clasificar(pct, MATRIZ.cambios) });
  await wb.xlsx.writeFile(salida);
  return { total: n, sinFallo: ok, tasa: pct === null ? null : +(pct * 100).toFixed(2), clasificacion: clasificar(pct, MATRIZ.cambios) };
}

async function reporteFallos(p, fallos, salida) {
  const wb = new ExcelJS.Workbook();
  const ws = hoja(wb, [86.25, 12, 24, 20, 60, 14, 16]);
  ws.addRow(['Título', 'Criticidad', 'Fecha real de respuesta', 'Fin de seguimiento', 'Reapertura o recurrencia', 'Fecha', 'Sin reapertura']);
  encabezado(ws, 1, 1, 7);
  const primera = 2, ultima = primera + Math.max(fallos.length, 1) - 1;
  if (!fallos.length) ws.addRow(['Sin fallos cerrados en el periodo']);
  fallos.forEach((c, i) => {
    const f = primera + i;
    const fila = ws.addRow([c.titulo, c.criticidad, c.f,
      { formula: `C${f}+${DIAS_SEGUIMIENTO}`, result: sumarDias(c.f, DIAS_SEGUIMIENTO) },
      resumenTexto(c.inc), c.inc.length ? c.inc[0].fecha : null,
      { formula: `IF(E${f}="","Sí","No")`, result: c.ok ? 'Sí' : 'No' }]);
    fila.getCell(3).numFmt = fila.getCell(4).numFmt = fila.getCell(6).numFmt = DF;
    for (const k of [2, 3, 4, 6, 7]) fila.getCell(k).alignment = CENTRO;
    fila.getCell(5).alignment = { wrapText: true, vertical: 'top' };
  });

  // Resumen por criticidad (S/C solo si hay casos sin clasificar)
  const niveles = CRITICIDADES.filter(x => x !== 'S/C' || fallos.some(c => c.criticidad === 'S/C'));
  const rS = ultima + 2, rUlt = rS + niveles.length;
  ['Criticidad', 'Fallos cerrados', 'Sin reapertura', 'Resolución definitiva'].forEach((v, i) => ws.getRow(rS).getCell(i + 1).value = v);
  encabezado(ws, rS, 1, 4);
  const resumen = {};
  niveles.forEach((nv, i) => {
    const f = rS + 1 + i, g = fallos.filter(c => c.criticidad === nv), k = g.filter(c => c.ok).length, fila = ws.getRow(f);
    resumen[nv] = { cerrados: g.length, sinReapertura: k, pct: g.length ? +(k / g.length * 100).toFixed(2) : null };
    fila.getCell(1).value = nv;
    fila.getCell(2).value = { formula: `COUNTIF($B$${primera}:$B$${ultima},A${f})`, result: g.length };
    fila.getCell(3).value = { formula: `COUNTIFS($B$${primera}:$B$${ultima},A${f},$G$${primera}:$G$${ultima},"Sí")`, result: k };
    fila.getCell(4).value = { formula: `IF(B${f}=0,"N/A",C${f}/B${f})`, result: g.length ? k / g.length : 'N/A' };
    fila.getCell(4).numFmt = '0.00%';
    for (let c = 2; c <= 4; c++) fila.getCell(c).alignment = CENTRO;
  });
  const n = fallos.length, ok = fallos.filter(c => c.ok).length, pct = n ? ok / n : null;
  const ft = ws.getRow(rUlt + 1);
  ft.getCell(1).value = 'Total';
  ft.getCell(2).value = { formula: `SUM(B${rS + 1}:B${rUlt})`, result: n };
  ft.getCell(3).value = { formula: `SUM(C${rS + 1}:C${rUlt})`, result: ok };
  ft.getCell(4).value = { formula: `IF(B${rUlt + 1}=0,"N/A",C${rUlt + 1}/B${rUlt + 1})`, result: pct === null ? 'N/A' : pct };
  ft.getCell(4).numFmt = '0.00%';
  for (let c = 2; c <= 4; c++) ft.getCell(c).alignment = CENTRO;
  encabezado(ws, rUlt + 1, 1, 4);
  filaDato(ws, rUlt + 2, 3, 4, 'Clasificación', { formula: formulaClasif(`D${rUlt + 1}`, MATRIZ.fallos), result: clasificar(pct, MATRIZ.fallos) });
  filaDato(ws, rUlt + 4, 3, 4, 'Periodo evaluado', `${dmy(p.inicio)} – ${dmy(p.fin)}`);
  await wb.xlsx.writeFile(salida);
  return { total: n, sinReapertura: ok, resolucion: pct === null ? null : +(pct * 100).toFixed(2), clasificacion: clasificar(pct, MATRIZ.fallos), resumen };
}

async function main() {
  const [clave, archDatos, bandera] = process.argv.slice(2);
  const p = periodo(clave);
  if (!fs.existsSync(p.carpeta)) throw new Error(`No existe la carpeta ${p.carpeta}.`);
  if (!archDatos || !fs.existsSync(archDatos)) throw new Error('Falta el archivo JSON de datos.');
  if (bandera !== '--sobrescribir')
    for (const s of [p.salidaCambios, p.salidaFallos]) if (fs.existsSync(s)) throw new Error(`Ya existe ${s}. Usa --sobrescribir solo si el usuario lo autorizó.`);
  const datos = JSON.parse(fs.readFileSync(archDatos, 'utf8'));
  datos.cambios = datos.cambios || []; datos.reaperturas = datos.reaperturas || []; datos.origenes = datos.origenes || [];
  const corte = hoy() < p.finSeguimiento ? hoy() : p.finSeguimiento;

  // Validaciones
  const errores = [];
  const revisaFecha = (f, quien) => { try { if (!fecha(f)) errores.push(`${quien} sin fecha`); } catch (e) { errores.push(`${quien}: ${e.message}`); } };
  datos.cambios.forEach(c => { revisaFecha(c.fecha, c.tt); if (!/^TT\d+$/.test(c.tt || '')) errores.push(`Cambio con TT inválido "${c.tt}"`); });
  datos.reaperturas.forEach(r => revisaFecha(r.fecha, `REABIERTO ${r.tt}`));
  datos.origenes.forEach(o => revisaFecha(o.fecha, `ORIGEN ${o.nuevo}`));
  const listaFallos = datos.fallos
    ? datos.fallos.map(c => ({ ...c, fecha: c.fecha && fecha(c.fecha) }))
    : fs.existsSync(p.relacionFallos) ? leerRelacionFallos(p.relacionFallos) : null;
  if (!listaFallos) errores.push(`No existe ${p.relacionFallos} y datos.json no trae "fallos".`);
  else listaFallos.forEach(c => {
    if (!c.tt) errores.push(`Fallo sin TT: "${c.titulo}"`);
    if (!CRITICIDADES.includes(c.criticidad)) errores.push(`${c.tt}: criticidad inválida "${c.criticidad}"`);
    if (!c.fecha) errores.push(`${c.tt}: sin fecha real de respuesta`);
  });
  if (errores.length) throw new Error('Datos inválidos:\n - ' + errores.join('\n - '));

  // Indicador 2: cambios y mejoras liberados en el mes evaluado
  const enPeriodo = d => d >= p.inicio && d <= p.fin;
  const cambios = [], fueraDePeriodo = [];
  for (const c of datos.cambios) {
    const f = fecha(c.fecha);
    if (!enPeriodo(f)) { fueraDePeriodo.push(`${c.tt} (${c.fecha})`); continue; }
    const inc = incidencias(c.tt, f, datos, true);
    cambios.push({ ...c, f, inc, ok: !inc.length });
  }
  cambios.sort((a, b) => a.f - b.f || numTT(a.tt) - numTT(b.tt));

  // Indicador 3: fallos atendidos en el mes evaluado
  const fallos = listaFallos.map(c => { const inc = incidencias(c.tt, c.fecha, datos); return { ...c, f: c.fecha, inc, ok: !inc.length }; })
    .sort((a, b) => numTT(a.tt) - numTT(b.tt));

  // Eventos que no apuntan a ningún caso evaluado
  const evaluados = new Set([...cambios.map(c => c.tt), ...fallos.map(c => c.tt)]);
  const sinCaso = [
    ...datos.reaperturas.filter(r => !evaluados.has(r.tt)).map(r => `REABIERTO ${r.tt} (${r.fecha})`),
    ...datos.origenes.filter(o => !evaluados.has(o.anterior)).map(o => `ORIGEN ${o.nuevo} <- ${o.anterior} (${o.fecha})`)
  ];

  const r2 = await reporteCambios(p, cambios, p.salidaCambios);
  const r3 = await reporteFallos(p, fallos, p.salidaFallos);
  const det = l => l.filter(c => !c.ok).map(c => ({ tt: c.tt, fecha: dmy(c.f), incidencias: c.inc.map(i => `${dmy(i.fecha)} ${i.texto}`) }));
  console.log(JSON.stringify({
    mes: p.clave, periodo: `${dmy(p.inicio)} – ${dmy(p.fin)}`, corte: dmy(corte),
    seguimientoCompleto: corte >= p.finSeguimiento,
    indicador2: { salida: p.salidaCambios, ...r2, conFallo: det(cambios) },
    indicador3: { salida: p.salidaFallos, ...r3, reabiertos: det(fallos) },
    cambiosFueraDePeriodo: fueraDePeriodo,
    eventosSinCasoEvaluado: sinCaso
  }, null, 2));
}

main().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
