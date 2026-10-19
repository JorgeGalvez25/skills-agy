// Uso: node extraer.js YYYYMM
// Imprime en JSON los casos de la exportación de VTiger para asignarles criticidad.
const fs = require('fs');
const { rutasMes, leerCasos, dmy, esCancelado } = require('./comun');

try {
  const r = rutasMes(process.argv[2]);
  const casos = leerCasos(r.entrada);
  const enMes = d => d && d.getUTCFullYear() === r.anio && d.getUTCMonth() + 1 === r.mes;
  const avisos = [];
  for (const c of casos) {
    if (!c.asignacion) avisos.push(`${c.id}: sin fecha de asignación`);
    if (!c.respuesta) avisos.push(`${c.id}: sin fecha real de respuesta`);
    else if (!enMes(c.respuesta)) avisos.push(`${c.id}: fecha real de respuesta ${dmy(c.respuesta)} fuera del mes`);
    if (c.asignacion && c.respuesta && c.respuesta < c.asignacion) avisos.push(`${c.id}: respuesta anterior a la asignación`);
  }
  const ids = casos.map(c => c.id);
  ids.filter((x, i) => ids.indexOf(x) !== i).forEach(x => avisos.push(`${x}: caso duplicado`));
  console.log(JSON.stringify({
    entrada: r.entrada,
    salida: r.salida,
    salidaExiste: fs.existsSync(r.salida),
    evaluables: casos.filter(c => !esCancelado(c)).map(c => ({ id: c.id, tipo: c.tipo, estatus: c.estatus, asignacion: dmy(c.asignacion), respuesta: dmy(c.respuesta), titulo: c.titulo })),
    cancelados: casos.filter(esCancelado).map(c => ({ id: c.id, titulo: c.titulo })),
    avisos
  }, null, 2));
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(1);
}
