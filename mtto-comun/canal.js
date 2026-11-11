// Caché compartida de los mensajes de #mtto. Todas las skills leen el canal una sola vez (ver canal.md) y trabajan sobre este archivo.
//   node canal.js oldest [dd/mm/aaaa]            -> desde dónde hay que leer Slack: { oldest (Unix), desde (AAAA-MM-DD), ... }
//   node canal.js unir <nuevos.json> <desde>     -> une lo leído a la caché (lo leído sustituye a lo guardado desde <desde>)
//   node canal.js estado <dd/mm/aaaa> [dd/mm/aaaa] -> estado por colaborador y TT en ese periodo (para /mtto-fechas y /mtto-quincenal)
//   node canal.js mensajes <dd/mm/aaaa> [dd/mm/aaaa] -> mensajes del periodo tal como están en la caché
// Mensaje: { "ts": "1791234567.000100", "fecha": "AAAA-MM-DD HH:MM", "autor": "Saulo Lopez", "texto": "..." }
const fs = require('fs');
const path = require('path');
const F = require('./fechas');
const E = require('./equipo');
const S = require('./standup');

const MTTO = process.env.MTTO_RAIZ || 'C:/Users/jorge/Dropbox/MTTO';
const RUTA = process.env.MTTO_CANAL || `${MTTO}/ReportesMTTO/datos/canal_mtto.json`;
// Caché anterior de /mtto-rendimiento (un arreglo de mensajes leído desde el 01/09/2026): se copia la primera vez
const RUTA_ANTERIOR = `${process.env.RENDIMIENTO_RAIZ || `${MTTO}/Reportes Mensuales/Rendimiento`}/datos/standups.json`;
const INICIO_ANTERIOR = '2026-09-01';
const TRASLAPE_DIAS = 3;       // días que se vuelven a leer antes del último mensaje guardado (standups editados)

const leerJson = f => JSON.parse(fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, ''));
const dia = m => F.fechaMensaje(m).dia;
const llave = m => m.ts || `${m.fecha}|${m.autor}`;
const orden = (a, b) => dia(a) - dia(b) || String(a.ts || a.fecha).localeCompare(String(b.ts || b.fecha));

// { cubreDesde: "AAAA-MM-DD" | null, mensajes: [] }
function leer() {
  if (fs.existsSync(RUTA)) { const c = leerJson(RUTA); return Array.isArray(c) ? { cubreDesde: null, mensajes: c } : c; }
  if (fs.existsSync(RUTA_ANTERIOR)) {
    const c = { cubreDesde: INICIO_ANTERIOR, mensajes: leerJson(RUTA_ANTERIOR).sort(orden) };
    guardar(c);
    return c;
  }
  return { cubreDesde: null, mensajes: [] };
}
function guardar(c) {
  fs.mkdirSync(path.dirname(RUTA), { recursive: true });
  fs.writeFileSync(RUTA, JSON.stringify(c, null, 1));
}
// Mensajes cuyo día está en [desde, hasta] (Date; hasta opcional)
const ventana = (mensajes, desde, hasta) => mensajes.filter(m => { const d = dia(m); return d >= desde && (!hasta || d <= hasta); });

// Desde qué día hay que leer Slack para que la caché cubra desde `necesario` (Date o null) hasta hoy
function oldest(necesario) {
  const c = leer();
  const ult = c.mensajes.length ? dia(c.mensajes[c.mensajes.length - 1]) : null;
  const cubre = c.cubreDesde ? F.deIso(c.cubreDesde) : null;
  let desde;
  if (!ult || !cubre) desde = necesario || F.deIso(INICIO_ANTERIOR);                    // sin caché
  else if (necesario && necesario < cubre) desde = necesario;                           // la caché empieza después de lo que se necesita
  else desde = new Date(ult.getTime() - TRASLAPE_DIAS * 864e5);
  return { oldest: F.tsDeDia(desde), desde: F.iso(desde), cache: RUTA, mensajes: c.mensajes.length, cubreDesde: c.cubreDesde, ultimoMensaje: F.iso(ult) };
}

// Une lo leído de Slack (desde `desde`, AAAA-MM-DD, hasta ahora). Lo leído manda: los mensajes guardados de ese periodo
// que ya no vienen (borrados en Slack) se quitan y los editados se actualizan.
function unir(archivo, desdeIso, forzar) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(desdeIso || '')) throw new Error('Falta <desde> (AAAA-MM-DD): el valor "desde" que devolvió "canal.js oldest".');
  const desde = F.deIso(desdeIso);
  const nuevos = leerJson(archivo);
  if (!Array.isArray(nuevos)) throw new Error(`${archivo} no es un arreglo de mensajes.`);
  nuevos.forEach((m, i) => {
    if (!m || typeof m.texto !== 'string' || !m.autor || !(m.ts || m.fecha)) throw new Error(`Mensaje ${i + 1} incompleto: lleva ts, fecha, autor y texto.`);
    if (!m.fecha || !/^\d{4}-\d{2}-\d{2}/.test(m.fecha)) { const f = F.fechaMensaje(m); m.fecha = `${F.iso(f.dia)}${f.hora ? ' ' + f.hora : ''}`; }
  });
  const fuera = nuevos.filter(m => dia(m) < desde).length;
  const c = leer();
  const previos = c.mensajes.filter(m => dia(m) >= desde);
  const leidos = new Map(nuevos.filter(m => dia(m) >= desde).map(m => [llave(m), m]));
  const quitados = previos.filter(m => !leidos.has(llave(m)));
  // Una lectura a medias (faltó paginar) borraría mensajes buenos: si falta más de la mitad de lo guardado, no se une
  if (!forzar && previos.length >= 4 && quitados.length > previos.length / 2)
    throw new Error(`La lectura trae ${leidos.size} mensajes desde ${desdeIso}, pero faltan ${quitados.length} de los ${previos.length} que ya estaban guardados de ese periodo. ` +
      'Parece una lectura incompleta (faltó paginar): vuelve a leer el canal. Si de verdad se borraron en Slack, repite con --forzar.');
  const antes = new Map(previos.map(m => [llave(m), m]));
  const agregados = [...leidos.keys()].filter(k => !antes.has(k)).length;
  const editados = [...leidos].filter(([k, m]) => antes.has(k) && antes.get(k).texto !== m.texto).length;
  c.mensajes = [...c.mensajes.filter(m => dia(m) < desde), ...leidos.values()].sort(orden);
  if (!c.cubreDesde || desdeIso < c.cubreDesde) c.cubreDesde = desdeIso;
  guardar(c);
  const porAutor = {};
  for (const m of leidos.values()) porAutor[m.autor] = (porAutor[m.autor] || 0) + 1;
  const conMensajes = new Set([...leidos.values()].map(m => dia(m).getTime()));
  const sinMensajes = [];
  for (let t = desde.getTime(); t <= F.hoy().getTime() - 864e5; t += 864e5) if (F.esLaborable(new Date(t)) && !conMensajes.has(t)) sinMensajes.push(F.dmy(new Date(t)));
  const dias = [...leidos.values()].map(dia).sort((a, b) => a - b);
  return { cache: RUTA, total: c.mensajes.length, cubreDesde: c.cubreDesde, leidos: leidos.size, agregados, editados, quitados: quitados.length,
    anterioresADesde: fuera, rango: dias.length ? [F.iso(dias[0]), F.iso(dias[dias.length - 1])] : null, porAutor,
    // Días hábiles del periodo leído sin ningún mensaje: festivo o lectura incompleta
    diasHabilesSinMensajes: sinMensajes };
}

// Estado por colaborador y TT entre desde y hasta (Date), a partir de los standups del equipo:
// último estatus de cada caso, cuándo cambió y si sigue en el último standup de su responsable.
function estado(desde, hasta) {
  const msgs = ventana(leer().mensajes, desde, hasta);
  const sinX = s => S.sinAcentos(s).toLowerCase().replace(/x\s?\d+\b/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
  const devs = {}, eventos = [], otros = {};
  for (const m of msgs) {
    const f = F.fechaMensaje(m);
    for (const l of String(m.texto || '').split(/\r?\n/).map(S.limpiar)) if (S.RX_EVENTO.test(l)) eventos.push({ fecha: F.iso(f.dia), autor: m.autor, linea: l });
    const dev = E.colaborador(m.autor);
    const b = S.bloqueHoy(S.parsear(m.texto));
    if (!b || !b.items.length) continue;
    if (!dev) { otros[m.autor] = (otros[m.autor] || 0) + 1; continue; }
    // Un standup por día: el último publicado
    (devs[dev] = devs[dev] || {})[F.iso(f.dia)] = b.items;
  }
  const salida = {};
  for (const nombre of E.EQUIPO) {
    const porDia = devs[nombre] || {};
    const dias = Object.keys(porDia).sort();
    const ultimo = dias[dias.length - 1] || null;
    const tts = {}, sinTT = {}, alias = {};
    for (const d of dias) for (const it of porDia[d]) if (it.antes) alias[it.antes] = it.tt;
    const final = id => { let x = id, n = 0; while (alias[x] && n++ < 10) x = alias[x]; return x; };
    for (const d of dias) for (const it of porDia[d]) {
      if (!it.tt) {
        const k = sinX(it.linea.replace(/\([^)]*\)?/g, ''));
        sinTT[k] = sinTT[k] || { texto: it.linea, desde: d };
        Object.assign(sinTT[k], { texto: it.linea, hasta: d, enUltimo: d === ultimo });
        continue;
      }
      const id = final(it.tt);
      const c = tts[id] = tts[id] || { tt: id, historial: [] };
      if (it.tt !== id) c.antes = [...new Set([...(c.antes || []), it.tt])];
      const h = c.historial[c.historial.length - 1];
      // El historial guarda solo los cambios de estatus (un contador x2 → x3 no es cambio)
      if (h && sinX(h[1]) === sinX(it.estatus)) h[1] = it.estatus; else c.historial.push([d, it.estatus]);
      Object.assign(c, { tipo: it.tipoCaso, codigo: it.codigo, etapa: it.etapa, seccion: it.seccion, estatus: it.estatus, contador: it.contador,
        fecha: d, enUltimo: d === ultimo });
    }
    salida[nombre] = { corto: E.ficha(nombre).corto, standups: dias.length, ultimoStandup: ultimo,
      tts: Object.values(tts).sort((a, b) => a.tt.localeCompare(b.tt)), sinTT: Object.values(sinTT) };
  }
  const dias = msgs.map(dia).sort((a, b) => a - b);
  return { rango: dias.length ? `${F.dmy(dias[0])}–${F.dmy(dias[dias.length - 1])}` : null, mensajes: msgs.length, devs: salida, eventos,
    // Mensajes con forma de standup de alguien que no está en equipo.json
    ...(Object.keys(otros).length ? { standupsDeOtros: otros } : {}) };
}

module.exports = { RUTA, leer, ventana, oldest, unir, estado };

if (require.main === module) {
  try {
    const [cmd, ...args] = process.argv.slice(2);
    const fechaArg = v => v ? F.leerFecha(v).dia : null;
    let r;
    if (cmd === 'oldest') r = oldest(fechaArg(args[0]));
    else if (cmd === 'unir') r = unir(args[0], args[1], args.includes('--forzar'));
    else if (cmd === 'estado' || cmd === 'mensajes') {
      if (!args[0]) throw new Error(`Uso: node canal.js ${cmd} <desde dd/mm/aaaa> [hasta dd/mm/aaaa]`);
      r = cmd === 'estado' ? estado(fechaArg(args[0]), fechaArg(args[1])) : ventana(leer().mensajes, fechaArg(args[0]), fechaArg(args[1]));
      if (cmd === 'estado' && !r.mensajes) throw new Error(`La caché (${RUTA}) no tiene mensajes de ese periodo. Actualízala primero (canal.md).`);
    } else throw new Error('Uso: node canal.js oldest [dd/mm/aaaa] | unir <nuevos.json> <desde> | estado <desde> [hasta] | mensajes <desde> [hasta]');
    console.log(JSON.stringify(r, null, 1));
  } catch (e) {
    console.error('ERROR: ' + e.message);
    process.exit(1);
  }
}
