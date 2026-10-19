// Uso: node preparar.js YYYYMM
// Imprime en JSON el periodo evaluado, la ventana de búsqueda en Slack, el universo de fallos y las rutas de salida.
const fs = require('fs');
const { periodo, leerRelacionFallos, sumarDias, dmy, iso, hoy } = require('./comun');

try {
  const p = periodo(process.argv[2]);
  const corte = hoy() < p.finSeguimiento ? hoy() : p.finSeguimiento;
  const avisos = [];
  if (!fs.existsSync(p.carpeta)) avisos.push(`No existe la carpeta del reporte ${p.carpeta}.`);
  if (corte < p.finSeguimiento)
    avisos.push(`Seguimiento parcial al ${dmy(corte)}: los casos de fin de mes se siguen hasta el ${dmy(p.finSeguimiento)}.`);

  let fallos = null;
  if (fs.existsSync(p.relacionFallos)) {
    fallos = leerRelacionFallos(p.relacionFallos);
    for (const c of fallos) {
      if (!c.tt) avisos.push(`Sin número TT en el título: "${c.titulo}"`);
      if (!/^P[1-4]$/.test(c.criticidad)) avisos.push(`${c.tt}: criticidad "${c.criticidad}" no válida`);
      if (c.fecha && (c.fecha < p.inicio || c.fecha > p.fin)) avisos.push(`${c.tt}: respuesta ${dmy(c.fecha)} fuera del mes`);
    }
  } else avisos.push(`No existe la relación de /rfallos del mes: ${p.relacionFallos}`);

  console.log(JSON.stringify({
    mes: p.clave,
    periodo: { inicio: dmy(p.inicio), fin: dmy(p.fin) },
    finSeguimiento: dmy(p.finSeguimiento),
    corte: dmy(corte),
    seguimientoCompleto: corte >= p.finSeguimiento,
    // Filtros after/before de Slack son exclusivos
    // REABIERTO y ORIGEN de un cambio pueden ser anteriores al mes de su LDP: se buscan desde que existen los eventos
    slack: { canal: 'C02CGD1D9NX', after: iso(sumarDias(p.inicio, -1)), afterIncidencias: '2026-10-06', before: iso(sumarDias(corte, 1)) },
    carpetaExiste: fs.existsSync(p.carpeta),
    salidas: {
      cambios: p.salidaCambios, cambiosExiste: fs.existsSync(p.salidaCambios),
      fallos: p.salidaFallos, fallosExiste: fs.existsSync(p.salidaFallos)
    },
    relacionFallos: p.relacionFallos,
    fallos: fallos && fallos.map(c => ({ tt: c.tt, criticidad: c.criticidad, fecha: dmy(c.fecha), titulo: c.titulo })),
    avisos
  }, null, 2));
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(1);
}
