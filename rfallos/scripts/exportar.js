// Uso: node exportar.js YYYYMM
// Arma desde VTiger la exportación "Relacion fallos atendidos" del mes (MMYYYY_RelacionFallosAtendidos.xls) en la carpeta del mes.
const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');
const { RAIZ } = require('./comun');
const { fallosAtendidos } = require(path.join(__dirname, '..', '..', 'mtto-comun', 'vtiger'));

(async () => {
  const clave = process.argv[2];
  const filas = await fallosAtendidos(clave);
  const carpeta = path.join(RAIZ, clave);
  if (!fs.existsSync(carpeta)) throw new Error(`No existe la carpeta ${carpeta}.`);
  const archivo = path.join(carpeta, `${clave.slice(4)}${clave.slice(0, 4)}_RelacionFallosAtendidos.xls`);
  if (fs.existsSync(archivo)) throw new Error(`Ya existe ${archivo}; no se sobrescribe.`);
  if (!filas.length) throw new Error('VTiger no tiene fallos con fecha real de respuesta en ese mes.');
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(filas), 'Relacion fallos atendidos');
  XLSX.writeFile(wb, archivo, { bookType: 'biff8' });
  console.log(JSON.stringify({ archivo, casos: filas.length }, null, 2));
})().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
