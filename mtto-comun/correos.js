// Caché compartida de los correos de casos TT (Outlook). Se actualiza con correos.ps1 (ver correos.md).
//   node correos.js estado <dd/mm/aaaa> [dd/mm/aaaa] -> estado por caso, cambios de ID, CEC y anomalías de ID en ese periodo
// Correo: { id, fecha "AAAA-MM-DD HH:MM", carpeta, de, deNombre, para[], asunto, respuesta, tipo, tt, relaciones[{tt,tipo,evidencia}], extracto }
const fs = require('fs');
const F = require('./fechas');
const E = require('./equipo');

const RUTA = process.env.MTTO_CORREOS || 'C:/Users/jorge/Dropbox/MTTO/ReportesMTTO/datos/correos_mtto.json';
const JORGE = ['jorgegalvez@igas.com.mx', 'jorgegalvez@imagensoft.com.mx'];
const CORREOS_EQUIPO = E.DATOS.equipo.map(p => p.correo.toLowerCase());
const esEquipo = c => CORREOS_EQUIPO.includes(c.de);
const esJorge = c => JORGE.includes(c.de);

const leer = () => {
  if (!fs.existsSync(RUTA)) throw new Error(`No existe la caché de correos (${RUTA}). Actualízala primero (correos.md).`);
  return JSON.parse(fs.readFileSync(RUTA, 'utf8').replace(/^\uFEFF/, ''));
};
const dia = c => F.deIso(c.fecha.slice(0, 10));
const resumen = c => ({ fecha: c.fecha, tipo: c.tipo, de: c.de, asunto: c.asunto });

// Correos de los TT con actividad entre desde y hasta (Date; hasta opcional)
function estado(desde, hasta) {
  const cache = leer();
  const enRango = cache.correos.filter(c => dia(c) >= desde && (!hasta || dia(c) <= hasta));
  const casos = {}, cambiosId = [], atiendeCon = [], anomalias = [];
  for (const c of enRango) {
    const k = casos[c.tt] = casos[c.tt] || { responsable: null, soporte: null, atiendeCon: null, correos: [], ultimo: null, sinRespuesta: false };
    k.correos.push({ ...resumen(c), respuesta: c.respuesta });
    for (const r of c.relaciones) {
      const base = { fecha: c.fecha, asunto: c.asunto };
      if (r.tipo === 'soporte') { k.soporte = r.tt; cambiosId.push({ antes: r.tt, nuevo: c.tt, ...base, fuente: 'correo' }); }
      else if (r.tipo === 'atiende-con') { k.atiendeCon = r.tt; atiendeCon.push({ tt: c.tt, con: r.tt, ...base, evidencia: r.evidencia }); }
      else if (r.tipo === 'anomalia') anomalias.push({ tt: c.tt, otro: r.tt, ...base, evidencia: r.evidencia });
    }
    // Responsable: el colaborador que recibe la asignación o el que entrega
    const dueno = c.tipo === 'asignacion' && !c.respuesta ? c.para.map(p => E.DATOS.equipo.find(e => e.correo.toLowerCase() === p)).find(Boolean)
      : c.tipo === 'entrega' && esEquipo(c) ? E.DATOS.equipo.find(e => e.correo.toLowerCase() === c.de) : null;
    if (dueno) k.responsable = dueno.nombre;
    if (!c.respuesta && (esEquipo(c) || esJorge(c))) k.ultimo = resumen(c);
  }
  // Sin respuesta: tras el último entrega/estatus del equipo no hay un correo de alguien ajeno al equipo y a Jorge
  // ni un rsp/cec/ldp propio (no respuesta) del equipo o de Jorge
  for (const [tt, k] of Object.entries(casos)) {
    const propios = enRango.filter(c => c.tt === tt);
    const i = propios.map((c, j) => ['entrega', 'estatus'].includes(c.tipo) && esEquipo(c) ? j : -1).reduce((a, b) => Math.max(a, b), -1);
    k.sinRespuesta = i >= 0 && !propios.slice(i + 1).some(c => (!esEquipo(c) && !esJorge(c)) || (!c.respuesta && ['rsp', 'cec', 'ldp'].includes(c.tipo)));
  }
  return { rango: { desde: F.iso(desde), hasta: F.iso(hasta || F.hoy()), cache: { desde: cache.desde, actualizado: cache.actualizado } },
    casos, cambiosId, atiendeCon, anomalias };
}

module.exports = { RUTA, leer, estado };

if (require.main === module) {
  try {
    const [cmd, ...args] = process.argv.slice(2);
    if (cmd !== 'estado' || !args[0]) throw new Error('Uso: node correos.js estado <desde dd/mm/aaaa> [hasta dd/mm/aaaa]');
    const fechaArg = v => v ? F.leerFecha(v).dia : null;
    console.log(JSON.stringify(estado(fechaArg(args[0]), fechaArg(args[1])), null, 1));
  } catch (e) {
    console.error('ERROR: ' + e.message);
    process.exit(1);
  }
}
