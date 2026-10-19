// Uso: node generar.js YYYYMM criticidades.json [--sobrescribir]
// criticidades.json: { "TT######": "P1|P2|P3|P4", ... } con todos los casos evaluables (no cancelados).
const fs = require('fs');
const ExcelJS = require('exceljs');
const { OBJETIVOS, rutasMes, leerCasos, feriadosEntre, diasHabiles, dmy, esCancelado } = require('./comun');

async function main() {
  const [clave, archCrit, bandera] = process.argv.slice(2);
  const r = rutasMes(clave);
  if (!archCrit || !fs.existsSync(archCrit)) throw new Error('Falta el archivo JSON de criticidades.');
  if (fs.existsSync(r.salida) && bandera !== '--sobrescribir')
    throw new Error(`Ya existe ${r.salida}. Usa --sobrescribir solo si el usuario lo autorizó.`);
  const crit = JSON.parse(fs.readFileSync(archCrit, 'utf8'));

  const casos = leerCasos(r.entrada);
  const num = c => +c.id.replace(/\D/g, '');
  const ev = casos.filter(c => !esCancelado(c)).sort((a, b) => num(a) - num(b));
  const canc = casos.filter(esCancelado).sort((a, b) => num(a) - num(b));

  // Validaciones de criticidad
  const errores = [];
  for (const c of ev) {
    if (!crit[c.id]) errores.push(`${c.id} sin criticidad`);
    else if (!OBJETIVOS[crit[c.id]]) errores.push(`${c.id} con criticidad inválida "${crit[c.id]}"`);
    if (!c.asignacion || !c.respuesta) errores.push(`${c.id} sin fecha de asignación o de respuesta`);
  }
  for (const k of Object.keys(crit)) if (!ev.some(c => c.id === k)) errores.push(`${k} no es un caso evaluable del mes`);
  if (errores.length) throw new Error('Criticidades inválidas:\n - ' + errores.join('\n - '));

  // Feriados que caen dentro del periodo evaluado
  const ini = new Date(Math.min(...ev.map(c => c.asignacion)));
  const fin = new Date(Math.max(...ev.map(c => c.respuesta)));
  const fer = feriadosEntre(ini, fin);
  const argFer = fer.length === 0 ? ''
    : fer.length === 1 ? `,DATE(${fer[0].getUTCFullYear()},${fer[0].getUTCMonth() + 1},${fer[0].getUTCDate()})`
    : `,{${fer.map(f => Math.round(f.getTime() / 864e5) + 25569).join(',')}}`;

  for (const c of ev) { c.c = crit[c.id]; c.n = diasHabiles(c.asignacion, c.respuesta, fer); c.ok = c.n <= OBJETIVOS[c.c]; }

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Worksheet');
  ws.columns = [{ width: 86.25 }, { width: 12 }, { width: 19.75 }, { width: 24 }, { width: 20.75 }, { width: 12 }, { width: 10 }];
  const azul = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4F81BD' } };
  const blanco = { color: { argb: 'FFFFFFFF' } };
  const encabezado = (fila, de, a) => { for (let c = de; c <= a; c++) { const x = ws.getRow(fila).getCell(c); x.fill = azul; x.font = blanco; } };
  const centro = { horizontal: 'center' };
  const DF = 'dd/mm/yyyy';

  // Detalle de fallos evaluables
  ws.addRow(['Título', 'Criticidad', 'Asignación de caso', 'Fecha real de respuesta', 'Tiempo de atención', 'Objetivo', 'Cumple']);
  encabezado(1, 1, 7);
  const primera = 2, ultima = primera + ev.length - 1, rS = ultima + 3, rP4 = rS + 4;
  ev.forEach((c, i) => {
    const f = primera + i;
    const fila = ws.addRow([c.titulo, c.c, c.asignacion, c.respuesta,
      { formula: `NETWORKDAYS(C${f},D${f}${argFer})`, result: c.n },
      { formula: `VLOOKUP(B${f},$A$${rS + 1}:$B$${rS + 4},2,FALSE)`, result: OBJETIVOS[c.c] },
      { formula: `IF(E${f}<=F${f},"Sí","No")`, result: c.ok ? 'Sí' : 'No' }]);
    fila.getCell(2).alignment = fila.getCell(6).alignment = fila.getCell(7).alignment = centro;
    fila.getCell(3).numFmt = fila.getCell(4).numFmt = DF;
    fila.getCell(5).numFmt = '0';
  });
  const prom = ev.reduce((s, c) => s + c.n, 0) / ev.length;
  const fp = ws.getRow(ultima + 1);
  fp.getCell(4).value = 'Promedio';
  fp.getCell(5).value = { formula: `AVERAGE(E${primera}:E${ultima})`, result: prom };
  fp.getCell(5).numFmt = '0.00';
  encabezado(ultima + 1, 4, 5);

  // Resumen por criticidad
  const fs_ = ws.getRow(rS);
  ['Criticidad', 'Objetivo (días hábiles)', 'Fallos evaluables', 'Dentro del objetivo', 'Cumplimiento'].forEach((v, i) => fs_.getCell(i + 1).value = v);
  encabezado(rS, 1, 5);
  const resumen = {};
  ['P1', 'P2', 'P3', 'P4'].forEach((p, i) => {
    const f = rS + 1 + i, g = ev.filter(c => c.c === p), k = g.filter(c => c.ok).length, fila = ws.getRow(f);
    resumen[p] = { objetivo: OBJETIVOS[p], evaluables: g.length, cumplen: k, pct: g.length ? +(k / g.length * 100).toFixed(2) : null };
    fila.getCell(1).value = p;
    fila.getCell(2).value = OBJETIVOS[p];
    fila.getCell(3).value = { formula: `COUNTIF($B$${primera}:$B$${ultima},A${f})`, result: g.length };
    fila.getCell(4).value = { formula: `COUNTIFS($B$${primera}:$B$${ultima},A${f},$G$${primera}:$G$${ultima},"Sí")`, result: k };
    fila.getCell(5).value = { formula: `IF(C${f}=0,"N/A",D${f}/C${f})`, result: g.length ? k / g.length : 'N/A' };
    fila.getCell(5).numFmt = '0.00%';
    for (let c = 2; c <= 5; c++) fila.getCell(c).alignment = centro;
  });
  const tot = ev.length, ok = ev.filter(c => c.ok).length, pct = ok / tot;
  const ft = ws.getRow(rP4 + 1);
  ft.getCell(1).value = 'Total';
  ft.getCell(3).value = { formula: `SUM(C${rS + 1}:C${rP4})`, result: tot };
  ft.getCell(4).value = { formula: `SUM(D${rS + 1}:D${rP4})`, result: ok };
  ft.getCell(5).value = { formula: `D${rP4 + 1}/C${rP4 + 1}`, result: pct };
  ft.getCell(5).numFmt = '0.00%';
  encabezado(rP4 + 1, 1, 5);
  for (let c = 2; c <= 5; c++) ft.getCell(c).alignment = centro;
  const clasif = pct >= 0.97 ? 'EXCELENTE' : pct >= 0.93 ? 'BUENO' : pct >= 0.85 ? 'REGULAR' : 'NO ACEPTABLE';
  const fc = ws.getRow(rP4 + 2);
  fc.getCell(4).value = 'Clasificación';
  fc.getCell(5).value = { formula: `IF(E${rP4 + 1}>=0.97,"EXCELENTE",IF(E${rP4 + 1}>=0.93,"BUENO",IF(E${rP4 + 1}>=0.85,"REGULAR","NO ACEPTABLE")))`, result: clasif };
  encabezado(rP4 + 2, 4, 5);
  fc.getCell(5).alignment = centro;

  // Casos no evaluables
  const rN = rP4 + 4;
  if (canc.length) {
    const fn = ws.getRow(rN);
    ['Casos no evaluables (cancelados)', 'Estatus', 'Asignación de caso', 'Fecha real de respuesta'].forEach((v, i) => fn.getCell(i + 1).value = v);
    encabezado(rN, 1, 4);
    canc.forEach((c, i) => {
      const fila = ws.getRow(rN + 1 + i);
      fila.getCell(1).value = c.titulo;
      fila.getCell(2).value = 'Cancelado';
      fila.getCell(3).value = c.asignacion;
      fila.getCell(4).value = c.respuesta;
      fila.getCell(3).numFmt = fila.getCell(4).numFmt = DF;
      fila.getCell(2).alignment = centro;
    });
  }

  ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0 };

  await wb.xlsx.writeFile(r.salida);
  console.log(JSON.stringify({
    salida: r.salida,
    feriadosDescontados: fer.map(dmy),
    total: tot, cumplen: ok, cumplimiento: +(pct * 100).toFixed(2), clasificacion: clasif,
    promedioDias: +prom.toFixed(2),
    resumen,
    incumplidos: ev.filter(c => !c.ok).map(c => ({ id: c.id, criticidad: c.c, dias: c.n, objetivo: OBJETIVOS[c.c], titulo: c.titulo })),
    cancelados: canc.map(c => c.id)
  }, null, 2));
}

main().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
