// Uso: node soporte.js <casos.json>
// Completa el ID Soporte de los Fallos que quedaron en "-" con el ticket de soporte de VTiger (cf_1275) y avisa si el del informe no coincide.
const fs = require('fs');
const path = require('path');
const { casos } = require(path.join(__dirname, '..', '..', 'mtto-comun', 'vtiger'));

(async () => {
  const archivo = process.argv[2];
  const lista = [].concat(JSON.parse(fs.readFileSync(archivo, 'utf8').replace(/^﻿/, '')));
  const fallos = lista.filter(c => c.tipo === 'Fallo');
  const vt = (await casos(fallos.map(c => c.id))).casos;
  const llenados = [], difieren = [], sinSoporte = [];
  for (const c of fallos) {
    const s = vt[c.id] && vt[c.id].soporte;
    if (!s) { if (c.soporte === '-') sinSoporte.push(c.id); continue; }
    if (s === c.soporte) continue;
    // En un Excel existente (fila con número) no se toca la columna B: solo se avisa
    if (c.soporte === '-' && !c.fila) { c.soporte = s; llenados.push(`${c.id} → ${s}`); }
    else difieren.push(`${c.id}: ${c.fila ? 'Excel' : 'informe'} ${c.soporte}, VTiger ${s}`);
  }
  fs.writeFileSync(archivo, JSON.stringify(lista, null, 2));
  console.log(JSON.stringify({ llenados, difieren, sinSoporte }, null, 2));
})().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
