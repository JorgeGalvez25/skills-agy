// Uso: node datos.js YYYYMM > datos.json
// Lee la caché compartida de #mtto (mtto-comun/canal.js; se actualiza con mtto-comun/canal.md), cruza standups, eventos, CambiosProceso, relaciones de fallos,
// acuerdos de versión y revisiones de PR, y devuelve un registro por caso con sus fechas por etapa.
const { spawnSync } = require('child_process');
const C = require('./comun');
const { fs, path } = C;

const EVENTOS_JS = path.join(__dirname, '..', '..', 'rcalidad', 'scripts', 'eventos.js');
const POST_ENTREGA = ['entregado', 'rsp', 'piloto', 'revpr', 'pruebas', 'ldp'];

// Mensajes de #mtto de la caché compartida. Con <mensajes_nuevos.json> <desde> los une antes (igual que "canal.js unir")
function cache(nuevos, desde) {
  const union = nuevos ? C.canal.unir(nuevos, desde) : null;
  const c = C.canal.leer();
  if (c.mensajes.length && (!c.cubreDesde || c.cubreDesde > C.INICIO_DATOS))
    throw new Error(`La caché de #mtto cubre desde ${c.cubreDesde || 'una fecha desconocida'} y este reporte necesita desde ${C.INICIO_DATOS}. Actualízala con "canal.js oldest ${C.dmy(C.deIso(C.INICIO_DATOS))}" (mtto-comun/canal.md).`);
  return { todos: c.mensajes, agregados: union ? union.agregados : 0 };
}

function eventos(msgs) {
  const tmp = path.join(require('os').tmpdir(), `rend_eventos_${process.pid}.json`);
  fs.writeFileSync(tmp, JSON.stringify(msgs.filter(m => C.EQUIPO.includes(C.colaborador(m.autor)) && /\b(LDP|LIBERADO|REABIERTO|ORIGEN)\b/.test(m.texto || ''))
    .map(m => ({ ...(m.ts ? { ts: m.ts } : { fecha: C.dmy(C.fechaMensaje(m)) }), autor: m.autor, texto: m.texto }))));
  const r = spawnSync(process.execPath, [EVENTOS_JS, tmp], { encoding: 'utf8', maxBuffer: 64 << 20 });
  fs.unlinkSync(tmp);
  if (r.status !== 0) throw new Error('eventos.js: ' + (r.stderr || r.stdout));
  return JSON.parse(r.stdout);
}

function cambiosProceso() {
  const f = C.leerHoja(C.RUTAS.procesos), enc = f[0].map(v => String(v || '').trim());
  const col = n => enc.indexOf(n);
  const iFa = col('Fecha asignación');
  const r = {};
  for (const x of f.slice(1)) {
    const id = C.tt(x[0]); if (!id) continue;
    r[id] = { titulo: String(x[1] || '').trim(), dev: C.colaborador(x[2]), estatus: x[3], asignacion: iFa >= 0 ? C.fecha(x[iFa]) : null };
  }
  return r;
}

// Detalle de cada MMYYYY_RelacionFallosAtendidos.xlsx (salida de /rfallos)
function relaciones() {
  const r = {};
  if (!fs.existsSync(C.RUTAS.indicadores)) return r;
  for (const mes of fs.readdirSync(C.RUTAS.indicadores).filter(d => /^\d{6}$/.test(d)).sort()) {
    const arch = path.join(C.RUTAS.indicadores, mes, `${mes.slice(4)}${mes.slice(0, 4)}_RelacionFallosAtendidos.xlsx`);
    if (!fs.existsSync(arch)) continue;
    const f = C.leerHoja(arch);
    if (String(f[0] && f[0][0]).trim() !== 'Título') continue;
    for (const x of f.slice(1)) {
      if (!x[0] || x[3] === 'Promedio' || x[0] === 'Criticidad') break;
      const id = C.tt(x[0]); if (!id) continue;
      const asignacion = C.fecha(x[2]), respuesta = C.fecha(x[3]), crit = String(x[1] || '').trim();
      r[id] = { mes, titulo: String(x[0]).trim(), criticidad: crit, asignacion, respuesta,
        tiempo: C.habiles(asignacion, respuesta), objetivo: C.OBJETIVOS[crit] || null };
      r[id].cumple = r[id].objetivo ? r[id].tiempo <= r[id].objetivo : null;
    }
  }
  return r;
}

// Acuerdos_IGAS_RSP*.xlsx de todas las versiones: responsable, tester, complejidad y módulos
function acuerdos() {
  const r = {}, lista = [];
  if (!fs.existsSync(C.RUTAS.versiones)) return { porTT: r, lista };
  for (const v of fs.readdirSync(C.RUTAS.versiones)) {
    const dir = path.join(C.RUTAS.versiones, v);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const a of fs.readdirSync(dir).filter(n => /^Acuerdos_IGAS_RSP.*\.xlsx$/i.test(n) && !n.startsWith('~$'))) {
      let f; try { f = C.leerHoja(path.join(dir, a)); } catch (e) { continue; }
      const enc = (f[0] || []).map(x => C.sinAcentos(x).trim().toLowerCase());
      const i = n => enc.indexOf(n);
      for (const x of f.slice(1)) {
        const id = C.tt(x[i('id')]); if (!id) continue;
        const reg = { version: v, id, idSoporte: C.tt(x[i('id soporte')]), titulo: String(x[i('descripcion')] || '').trim(), tipo: String(x[i('tipo')] || '').trim(),
          responsable: C.colaborador(x[i('responsable')]), tester: C.colaborador(x[i('tester')]), complejidad: String(x[i('complejidad')] || '').trim() || null,
          modulos: String(x[i('modulos')] || '').split(/\r?\n|,/).map(s => s.trim()).filter(Boolean) };
        lista.push(reg); r[id] = reg; if (reg.idSoporte) r[reg.idSoporte] = r[reg.idSoporte] || reg;
      }
    }
  }
  return { porTT: r, lista };
}

// Revision_PR/TT#####.md de /mtto-revpr: hallazgos por severidad
function revisionesPR() {
  const r = {};
  if (!fs.existsSync(C.RUTAS.versiones)) return r;
  for (const v of fs.readdirSync(C.RUTAS.versiones)) {
    const dir = path.join(C.RUTAS.versiones, v, 'Revision_PR');
    if (!fs.existsSync(dir)) continue;
    for (const a of fs.readdirSync(dir).filter(n => /^TT\d+\.md$/i.test(n))) {
      const t = fs.readFileSync(path.join(dir, a), 'utf8');
      const fRev = (t.match(/Fecha de revisi[oó]n:\*\*\s*(\d{1,2}\/\d{1,2}\/\d{4})/) || [])[1];
      const resp = (t.match(/Responsable:\*\*\s*([^·*\n]+)/) || [])[1];
      const veredicto = (t.match(/Veredicto:\*\*\s*([^—\n]+)/) || [])[1];
      const sec = t.split(/^## Hallazgos/m)[1] || '';
      const tabla = sec.split(/^## /m)[0];
      const sev = { Alta: 0, Media: 0, Baja: 0 };
      for (const l of tabla.split('\n')) { const m = l.match(/^\|\s*\d+\s*\|\s*(Alta|Media|Baja)\s*\|/i); if (m) sev[m[1][0].toUpperCase() + m[1].slice(1).toLowerCase()]++; }
      r[a.replace(/\.md$/i, '').toUpperCase()] = { version: v, fecha: C.fecha(fRev), responsable: C.colaborador(resp), veredicto: veredicto ? veredicto.replace(/[❌⚠️✅]/g, '').trim() : null, ...sev };
    }
  }
  return r;
}

try {
  const [clave, nuevos, desde] = process.argv.slice(2);
  const per = C.periodo(clave);
  const { todos, agregados } = cache(nuevos, desde);
  if (!todos.length) throw new Error(`No hay mensajes en ${C.RUTAS.standups}. Actualízala desde ${C.INICIO_DATOS} (paso 1).`);

  // Historial por TT a partir de los standups del equipo
  const hist = {}, wip = {}, tester = {}, renombres = {};
  const diasStandup = new Set();
  for (const m of todos) {
    const dev = C.colaborador(m.autor);
    if (!dev || !C.EQUIPO.includes(dev)) continue;
    const items = C.parsearStandup(m.texto);
    if (!items.length) continue;
    const dia = C.fechaMensaje(m);
    diasStandup.add(C.iso(dia));
    let activos = 0, pausa = 0;
    for (const it of items) {
      if (it.antes) renombres[it.antes] = it.tt;
      if (it.etapa === 'tester') { (tester[dev] = tester[dev] || {})[it.tt] = (tester[dev][it.tt] || []).concat(C.iso(dia)); continue; }
      (hist[it.tt] = hist[it.tt] || []).push({ dia, dev, etapa: it.etapa, codigo: it.codigo, tipo: it.tipo, estatus: it.estatus, fechaEntrega: it.fechaEntrega || null });
      if (it.etapa === 'pausa') pausa++; else if (!['cierre', 'ldp', 'rsp'].includes(it.etapa)) activos++;
    }
    // Un standup por día por colaborador: se queda el último
    (wip[dev] = wip[dev] || {})[C.iso(dia)] = { activos, pausa };
  }
  // Cambio de ID: la historia del ID anterior pasa al nuevo
  const final = id => { let x = id, n = 0; while (renombres[x] && n++ < 10) x = renombres[x]; return x; };
  for (const id of Object.keys(hist)) {
    const f = final(id);
    if (f !== id) { hist[f] = (hist[f] || []).concat(hist[id]); delete hist[id]; }
  }
  for (const h of Object.values(hist)) h.sort((a, b) => a.dia - b.dia);
  const primerDia = [...diasStandup].sort()[0];

  const ev = eventos(todos);
  const cp = cambiosProceso(), rel = relaciones(), acu = acuerdos(), prs = revisionesPR();
  const atrib = C.leerJson(C.RUTAS.atribuciones, {});

  // Universo: casos con historia en standups, fallos de las relaciones y cambios asignados desde el inicio de los datos
  const inicio = C.deIso(C.INICIO_DATOS);
  const ids = new Set(Object.keys(hist));
  for (const [id, r] of Object.entries(rel)) if (r.respuesta >= inicio) ids.add(final(id));
  for (const [id, r] of Object.entries(cp)) if (r.asignacion && r.asignacion >= inicio) ids.add(id);

  const ldpEv = {};
  for (const e of [...ev.cambios, ...ev.fallosLdp]) { const id = final(e.tt), f = C.fecha(e.fecha); if (!ldpEv[id] || f < ldpEv[id]) ldpEv[id] = f; }
  const reab = {}, origen = {};
  for (const e of ev.reaperturas) (reab[final(e.tt)] = reab[final(e.tt)] || []).push({ fecha: C.fecha(e.fecha), motivo: e.motivo });
  for (const e of ev.origenes) (origen[final(e.anterior)] = origen[final(e.anterior)] || []).push({ nuevo: e.nuevo, fecha: C.fecha(e.fecha), causa: e.causa });

  const casos = [], dudas = { sinDueno: [], variosDuenos: [], reasignados: [], entregaAntesDeDatos: [] };
  for (const id of [...ids].sort((a, b) => C.numTT(a) - C.numTT(b))) {
    const h = hist[id] || [], c = cp[id], r = rel[id], a = acu.porTT[id], pr = prs[id];
    // Dueño: decisión de Jorge > quien lo trae en su standup > CambiosProceso > acuerdos
    const cuenta = {};
    for (const x of h) cuenta[x.dev] = (cuenta[x.dev] || 0) + 1;
    const duenos = Object.keys(cuenta).sort((x, y) => cuenta[y] - cuenta[x]);
    let dev = atrib[id] || duenos[0] || (c && c.dev) || (a && a.responsable) || null;
    let fuenteDev = atrib[id] ? 'Jorge' : duenos[0] ? 'standup' : c && c.dev ? 'CambiosProceso' : a && a.responsable ? 'acuerdos' : null;
    if (!atrib[id] && duenos.length > 1) dudas.variosDuenos.push({ tt: id, standups: cuenta, elegido: dev });
    if (c && c.dev && duenos[0] && c.dev !== duenos[0] && !atrib[id]) dudas.reasignados.push({ tt: id, cambiosProceso: c.dev, standup: duenos[0] });

    const tipoStd = (h.find(x => x.tipo) || {}).tipo;
    const titulo = (c && c.titulo) || (r && r.titulo) || (a && a.titulo) || null;
    let tipo = c ? 'C' : r ? (/APOYO A SOPORTE/i.test(C.sinAcentos(r.titulo)) ? 'AP' : 'F') : tipoStd || (a && (/fallo/i.test(a.tipo) ? 'F' : 'C')) || 'F'; // todo cambio está en CambiosProceso
    if (tipoStd === 'AP' && tipo === 'F') tipo = 'AP';
    if (!dev && (r || c)) dudas.sinDueno.push({ tt: id, tipo, titulo, mes: r ? r.mes : null });

    const primera = h[0] ? h[0].dia : null;
    // La más temprana: un caso puede atenderse primero con el ID de soporte
    const fuentes = [['ACA', c && c.asignacion], ['VTiger', r && r.asignacion], ['standup', primera]].filter(x => x[1]).sort((x, y) => x[1] - y[1]);
    let asignacion = fuentes.length ? fuentes[0][1] : null, fuenteAsig = fuentes.length ? fuentes[0][0] : null;
    // Ya venía abierto en los primeros standups leídos: la asignación real es anterior y no se conoce
    if (fuenteAsig === 'standup' && C.habiles(C.deIso(primerDia), asignacion) <= 3) { asignacion = null; fuenteAsig = 'antes de los datos'; }
    // Entrega: fallos con la fecha real de respuesta de VTiger; cambios con el primer estatus posterior a la entrega
    const pEnt = h.find(x => POST_ENTREGA.includes(x.etapa));
    let entrega = null, fuenteEnt = null;
    if (r && r.respuesta) { entrega = r.respuesta; fuenteEnt = 'VTiger'; }
    else if (pEnt) {
      // Si ya venía entregado en los primeros standups leídos, la entrega fue antes del inicio de los datos
      if (pEnt === h[0] && C.habiles(C.deIso(primerDia), pEnt.dia) <= 3) dudas.entregaAntesDeDatos.push(id);
      else { entrega = pEnt.dia; fuenteEnt = 'standup'; }
    }
    const pRsp = h.find(x => x.etapa === 'rsp');
    const rsp = pRsp ? (h.find(x => x.etapa === 'rsp' && x.fechaEntrega) || {}).fechaEntrega || pRsp.dia : null;
    const ldp = ldpEv[id] || (h.find(x => x.etapa === 'ldp') || {}).dia || null;
    const cierre = (h.find(x => x.etapa === 'cierre') || {}).dia || null;
    let revpr = 0;
    h.forEach((x, k) => { if (x.etapa === 'revpr' && (k === 0 || h[k - 1].etapa !== 'revpr')) revpr++; });
    const { cliente, modulo } = C.partesTitulo(titulo);

    casos.push({
      tt: id, dev, fuenteDev, tipo, titulo, cliente, modulo,
      criticidad: r ? r.criticidad : null, cumpleCriticidad: r ? r.cumple : null, mesRelacion: r ? r.mes : null,
      complejidad: a ? a.complejidad : null, version: a ? a.version : null, tester: a ? a.tester : null,
      asignacion: C.iso(asignacion), fuenteAsig, entrega: C.iso(entrega), fuenteEnt, rsp: C.iso(rsp), ldp: C.iso(ldp), cierre: C.iso(cierre),
      diasEntrega: C.habiles(asignacion, entrega), diasLiberacion: C.habiles(asignacion, ldp), diasRspLdp: C.habiles(rsp, ldp), diasCliente: C.habiles(entrega, rsp),
      revpr, reaperturas: (reab[id] || []).map(x => ({ fecha: C.iso(x.fecha), motivo: x.motivo })),
      origenes: (origen[id] || []).map(x => ({ nuevo: x.nuevo, fecha: C.iso(x.fecha), causa: x.causa })),
      pr: pr ? { version: pr.version, fecha: C.iso(pr.fecha), veredicto: pr.veredicto, alta: pr.Alta, media: pr.Media, baja: pr.Baja } : null,
      // Días en el standup de cada colaborador: un caso reasignado cuenta como atendido para ambos
      diasPorDev: h.reduce((o, x) => { const d = C.iso(x.dia); o[x.dev] = o[x.dev] || []; if (!o[x.dev].includes(d)) o[x.dev].push(d); return o; }, {}),
      ultimoEstatus: h.length ? h[h.length - 1].estatus : null
    });
  }

  // Mapa histórico de módulos de los acuerdos (desde 2024)
  const modulos = acu.lista.filter(x => x.responsable).map(x => ({ version: x.version, tt: x.id, dev: x.responsable, tipo: x.tipo, complejidad: x.complejidad, modulos: x.modulos }));
  const testerOut = {};
  for (const [d, o] of Object.entries(tester)) testerOut[d] = Object.entries(o).map(([t, dias]) => ({ tt: final(t), dias }));

  console.log(JSON.stringify({
    clave, mensajes: todos.length, agregados, rango: [primerDia, [...diasStandup].sort().pop()],
    casos, wip, tester: testerOut, modulos,
    eventos: { noLeidos: ev.noLeidos, avisos: ev.avisos },
    dudas
  }, null, 1));
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(1);
}
