// Pruebas de revisar.js: corre la revisión sobre standups de ejemplo y compara con la salida guardada en esperado/.
//   node probar.js               -> compara; termina con error si alguna fecha cambió
//   node probar.js --actualizar  -> guarda la salida actual como la esperada (después de revisar que el cambio es el que se quería)
// Sirve para que una regla nueva no rompa otra: si una fecha cambia sin que la hayas tocado a propósito, es una regresión.
// Para cubrir un caso nuevo, agrega el standup a standups.json (y, si aplica, una entrada a aclaraciones.json) y actualiza.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const AQUI = __dirname;
const REVISAR = path.join(AQUI, '..', 'scripts', 'revisar.js');
const MENSAJES = path.join(AQUI, 'standups.json');
const ESPERADO = path.join(AQUI, 'esperado');
const actualizar = process.argv.includes('--actualizar');

// Se revisa cada día que tiene standups
const dias = [...new Set(JSON.parse(fs.readFileSync(MENSAJES, 'utf8')).map(m => m.fecha.slice(0, 10)))].sort();
const resumen = r => Object.entries(r.colaboradores || {}).flatMap(([autor, c]) => [
  ...c.hallazgos.map(h => `${autor} | ${h.regla} | ${h.tt || '-'}`),
  ...c.estancados.map(e => `${autor} | estancados | ${e.tt}`),
  ...c.aclarados.map(a => `${autor} | aclarado:${a.regla} | ${a.tt || '-'}`),
  ...c.cambiosId.map(x => `${autor} | cambio aplicado | ${x.antes} -> ${x.nuevo}`)]);

let fallas = 0, hallazgos = 0;
for (const d of dias) {
  const fecha = `${d.slice(8)}/${d.slice(5, 7)}/${d.slice(0, 4)}`;
  const p = spawnSync(process.execPath, [REVISAR, MENSAJES, fecha], { encoding: 'utf8',
    env: { ...process.env, MTTO_ACLARACIONES: path.join(AQUI, 'aclaraciones.json'), MTTO_FERIADOS_EXTRA: path.join(AQUI, 'sin-feriados-extra.json') } });
  if (p.status !== 0) { console.log(`✗ ${fecha}: revisar.js terminó con error\n${p.stderr || p.stdout}`); fallas++; continue; }
  const arch = path.join(ESPERADO, `${d}.json`);
  const actual = JSON.parse(p.stdout);
  hallazgos += resumen(actual).length;
  if (actualizar) { fs.writeFileSync(arch, JSON.stringify(actual, null, 2) + '\n'); continue; }
  if (!fs.existsSync(arch)) { console.log(`✗ ${fecha}: no hay salida esperada (corre con --actualizar)`); fallas++; continue; }
  const esperado = JSON.parse(fs.readFileSync(arch, 'utf8'));
  if (JSON.stringify(esperado) === JSON.stringify(actual)) { console.log(`✓ ${fecha}`); continue; }
  fallas++;
  const a = resumen(esperado), b = resumen(actual);
  console.log(`✗ ${fecha}`);
  for (const x of a.filter(x => !b.includes(x))) console.log(`    ya no sale:  ${x}`);
  for (const x of b.filter(x => !a.includes(x))) console.log(`    sale nuevo:  ${x}`);
  if (a.join() === b.join()) console.log('    mismos hallazgos, cambió el texto o un dato (compara con esperado/' + d + '.json)');
}
if (actualizar) console.log(`Salida esperada guardada: ${dias.length} fechas, ${hallazgos} señales.`);
else console.log(fallas ? `\n${fallas} de ${dias.length} fechas cambiaron. Si el cambio es intencional: node probar.js --actualizar`
  : `\nSin cambios en ${dias.length} fechas (${hallazgos} señales).`);
process.exit(fallas ? 1 : 0);
