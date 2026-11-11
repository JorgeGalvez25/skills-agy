// Uso: node generar.js YYYYMM datos.json [--sobrescribir]
// Calcula el rendimiento del mes por colaborador y crea MMYYYY_RendimientoColaboradores.xlsx en Rendimiento\YYYYMM.
const ExcelJS = require('exceljs');
const C = require('./comun');
const { fs } = C;

const ENC = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4F81BD' } };
const SUB = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFDCE6F1' } };
const VERDE = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE2EFDA' } };
const ROJO = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFCE4D6' } };
const TIPOS = { C: 'Cambio', F: 'Fallo', AP: 'Apoyo a soporte' };
const r1 = v => v === null || v === undefined ? null : Math.round(v * 10) / 10;
const enMes = (s, per) => { const d = C.deIso(s); return !!d && d >= per.inicio && d <= per.fin; };
const hasta = (s, per) => { const d = C.deIso(s); return !!d && d <= per.fin; };

function metricas(casos, datos, dev, per) {
  const mios = casos.filter(c => c.dev === dev);
  // Tiempos y calidad son del dueño (quien lo terminó); atendido cuenta para todos los que lo trajeron en su standup
  const atendidos = casos.filter(c => (c.diasPorDev[dev] || []).some(d => enMes(d, per))
    || (c.dev === dev && (enMes(c.entrega, per) || enMes(c.ldp, per) || enMes(c.cierre, per))));
  const ent = mios.filter(c => enMes(c.entrega, per) && c.diasEntrega !== null);
  const lib = mios.filter(c => enMes(c.ldp, per));
  const vals = (l, k) => l.map(c => c[k]).filter(v => v !== null);
  const fallos = mios.filter(c => c.mesRelacion === per.clave && c.cumpleCriticidad !== null);
  const wip = Object.entries((datos.wip || {})[dev] || {}).filter(([d]) => enMes(d, per)).map(([, w]) => w.activos);
  const prMes = mios.filter(c => c.pr && enMes(c.pr.fecha, per));
  const origenes = mios.flatMap(c => c.origenes.filter(o => enMes(o.fecha, per)).map(o => ({ tt: c.tt, ...o })));
  const reaperturas = mios.flatMap(c => c.reaperturas.filter(o => enMes(o.fecha, per)).map(o => ({ tt: c.tt, ...o })));
  const tester = ((datos.tester || {})[dev] || []).filter(t => t.dias.some(d => enMes(d, per)));
  const porTipo = t => l => l.filter(c => t === 'C' ? c.tipo === 'C' : c.tipo !== 'C');
  return {
    dev, atendidos: atendidos.length, nuevos: mios.filter(c => enMes(c.asignacion, per)).length,
    atendidosTipo: { C: atendidos.filter(c => c.tipo === 'C').length, F: atendidos.filter(c => c.tipo === 'F').length, AP: atendidos.filter(c => c.tipo === 'AP').length },
    entregados: ent.length, liberados: lib.length, cerradosCec: mios.filter(c => enMes(c.cierre, per) && !c.ldp).length,
    entregaMedC: C.mediana(vals(porTipo('C')(ent), 'diasEntrega')), entregaMedF: C.mediana(vals(porTipo('F')(ent), 'diasEntrega')),
    entregaProm: r1(C.promedio(vals(ent, 'diasEntrega'))),
    liberacionMed: C.mediana(vals(lib, 'diasLiberacion')), rspLdpMed: C.mediana(vals(lib, 'diasRspLdp')),
    fallosObj: fallos.length, fallosCumplen: fallos.filter(c => c.cumpleCriticidad).length,
    cumplimiento: fallos.length ? fallos.filter(c => c.cumpleCriticidad).length / fallos.length : null,
    incumplidos: fallos.filter(c => !c.cumpleCriticidad),
    origenes, reaperturas, conRevpr: atendidos.filter(c => c.revpr > 0).length,
    prAlta: prMes.reduce((s, c) => s + c.pr.alta, 0), prMedia: prMes.reduce((s, c) => s + c.pr.media, 0), prBaja: prMes.reduce((s, c) => s + c.pr.baja, 0), prCasos: prMes.length,
    wipProm: r1(C.promedio(wip)), wipMax: wip.length ? Math.max(...wip) : null, standups: wip.length,
    tester: tester.length, lista: atendidos
  };
}

// Fortalezas y dificultades: su mediana de días de entrega contra la del resto del equipo, por categoría, con todo lo acumulado
function perfil(casos, dev, per) {
  const base = casos.filter(c => c.dev && hasta(c.entrega, per) && c.diasEntrega !== null);
  const cats = [['Tipo', c => TIPOS[c.tipo] || null], ['Módulo', c => c.modulo], ['Criticidad', c => c.criticidad], ['Complejidad', c => c.complejidad]];
  const filas = [];
  for (const [cat, f] of cats) {
    const valores = [...new Set(base.filter(c => c.dev === dev).map(f).filter(Boolean))];
    for (const v of valores) {
      const suyos = base.filter(c => c.dev === dev && f(c) === v), resto = base.filter(c => c.dev !== dev && f(c) === v);
      const todosSuyos = casos.filter(c => c.dev === dev && f(c) === v && hasta(c.asignacion, per));
      const incid = todosSuyos.reduce((s, c) => s + c.origenes.filter(o => hasta(o.fecha, per)).length + c.reaperturas.filter(o => hasta(o.fecha, per)).length, 0);
      const fuera = todosSuyos.filter(c => c.cumpleCriticidad === false).length;
      const mS = C.mediana(suyos.map(c => c.diasEntrega)), mR = resto.length >= 2 ? C.mediana(resto.map(c => c.diasEntrega)) : null;
      const indice = mS !== null && mR ? mS / mR : null;
      let lectura;
      if (suyos.length < C.MUESTRA_MIN) lectura = 'Muestra insuficiente';
      else if (indice === null) lectura = 'Sin comparación (el resto del equipo tiene menos de 2 casos)';
      else if ((indice >= 1.25) || incid > 0 || fuera >= 2) lectura = 'Dificultad';
      else if (indice <= 0.8 && fuera === 0) lectura = 'Fortaleza';
      else lectura = 'En línea con el equipo';
      filas.push({ cat, valor: v, n: suyos.length, total: todosSuyos.length, mS, mR, indice: indice === null ? null : Math.round(indice * 100) / 100, incid, fuera, lectura });
    }
  }
  const orden = { Fortaleza: 0, Dificultad: 1, 'En línea con el equipo': 2 };
  return filas.sort((a, b) => (orden[a.lectura] ?? 3) - (orden[b.lectura] ?? 3) || b.n - a.n);
}

function mapaModulos(datos, casos) {
  const porTT = {};
  for (const m of datos.modulos) for (const mod of m.modulos) (porTT[m.tt] = porTT[m.tt] || { dev: m.dev, mods: new Set() }).mods.add(C.sinAcentos(mod).toUpperCase());
  for (const c of casos) if (c.dev && c.modulo && !porTT[c.tt]) porTT[c.tt] = { dev: c.dev, mods: new Set([c.modulo]) };
  // "MASTER VOL" y "MASTERVOL" son el mismo módulo
  const mapa = {}, nombre = {};
  for (const { dev, mods } of Object.values(porTT)) for (const m of mods) {
    const k = m.replace(/[^A-Z0-9]/g, ''); nombre[k] = nombre[k] || m;
    mapa[k] = mapa[k] || {}; mapa[k][dev] = (mapa[k][dev] || 0) + 1;
  }
  return Object.entries(mapa).map(([k, devs]) => {
    const modulo = nombre[k];
    const total = Object.values(devs).reduce((s, n) => s + n, 0), principal = Object.entries(devs).sort((a, b) => b[1] - a[1])[0];
    const cobertura = Object.keys(devs).length === 1 ? (total >= 2 ? 'Solo una persona' : 'Un solo caso') : principal[1] / total >= 0.8 ? 'Concentrado' : 'Compartido';
    return { modulo, devs, total, principal: principal[0], pct: principal[1] / total, cobertura };
  }).sort((a, b) => b.total - a.total);
}

function encabezado(ws, fila, textos, ancho) {
  const r = ws.getRow(fila);
  textos.forEach((t, i) => { const c = r.getCell(i + 1); c.value = t; c.fill = ENC; c.font = { bold: true, color: { argb: 'FFFFFFFF' } }; c.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }; });
  if (ancho) r.height = ancho;
}
const titulo = (ws, fila, texto) => { const c = ws.getCell(fila, 1); c.value = texto; c.font = { bold: true, size: 13, color: { argb: 'FF1F3864' } }; };
const fechaCel = s => s ? C.deIso(s) : null;

async function main() {
  const args = process.argv.slice(2);
  const [clave, archDatos] = args, sobrescribir = args.includes('--sobrescribir');
  const per = C.periodo(clave);
  const datos = C.leerJson(archDatos, null);
  if (!datos) throw new Error(`No existe ${archDatos}`);
  if (fs.existsSync(per.salida) && !sobrescribir) throw new Error(`Ya existe ${per.salida}. Usa --sobrescribir solo con autorización.`);
  const casos = datos.casos;

  // Meses de la tendencia: desde el primer mes completo con datos hasta el reportado
  const meses = [];
  for (let d = C.deIso(C.INICIO_DATOS); d <= per.inicio; d = C.utc(d.getUTCFullYear() + (d.getUTCMonth() === 11 ? 1 : 0), (d.getUTCMonth() + 1) % 12 + 1, 1))
    meses.push(`${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}`);
  const tendencia = meses.map(m => ({ mes: m, por: Object.fromEntries(C.EQUIPO.map(dev => [dev, metricas(casos, datos, dev, C.periodo(m))])) }));
  const actual = Object.fromEntries(C.EQUIPO.map(dev => [dev, metricas(casos, datos, dev, per)]));
  const perfiles = Object.fromEntries(C.EQUIPO.map(dev => [dev, perfil(casos, dev, per)]));
  const mapa = mapaModulos(datos, casos);

  const wb = new ExcelJS.Workbook();
  wb.creator = 'Jorge Gálvez';
  const nombreMes = per.inicio.toLocaleDateString('es-MX', { month: 'long', year: 'numeric', timeZone: 'UTC' });

  // Hoja Equipo
  const we = wb.addWorksheet('Equipo', { views: [{ state: 'frozen', xSplit: 1, ySplit: 3 }] });
  titulo(we, 1, `Rendimiento por colaborador — ${nombreMes} (uso interno)`);
  const colsE = ['Colaborador', 'Atendidos', 'Cambios', 'Fallos', 'Apoyos', 'Nuevos asignados', 'Entregados', 'Liberados (LDP)', 'Cerrados con CEC',
    'Entrega cambios (mediana, días háb.)', 'Entrega fallos/AP (mediana)', 'Entrega (promedio)', 'Asignación → LDP (mediana)', 'RSP → LDP (mediana)',
    'Fallos con objetivo', 'Dentro del objetivo', 'Cumplimiento', 'ORIGEN causados', 'Reaperturas', 'Casos con REVPR', 'Hallazgos PR Alta', 'Media', 'Baja',
    'Carga activa (prom.)', 'Carga máx.', 'Probados como tester'];
  // El alineado de columna va antes del encabezado para no pisar su ajuste de texto
  we.getColumn(1).width = 20;
  for (let k = 2; k <= colsE.length; k++) { we.getColumn(k).width = 14; we.getColumn(k).alignment = { horizontal: 'center' }; }
  encabezado(we, 3, colsE, 62);
  C.EQUIPO.forEach((dev, i) => {
    const m = actual[dev];
    we.addRow([dev, m.atendidos, m.atendidosTipo.C, m.atendidosTipo.F, m.atendidosTipo.AP, m.nuevos, m.entregados, m.liberados, m.cerradosCec,
      m.entregaMedC, m.entregaMedF, m.entregaProm, m.liberacionMed, m.rspLdpMed, m.fallosObj, m.fallosCumplen, m.cumplimiento,
      m.origenes.length, m.reaperturas.length, m.conRevpr, m.prAlta, m.prMedia, m.prBaja, m.wipProm, m.wipMax, m.tester]);
  });
  we.getColumn(17).numFmt = '0%';
  const fN = 4 + C.EQUIPO.length + 1;
  we.getCell(fN, 1).value = 'Días hábiles (lunes a viernes sin feriados LFT ni días no laborables de la empresa), contados como NETWORKDAYS. Entrega de fallos = fecha real de respuesta de VTiger; de cambios = primer standup en Entregado o posterior. Carga activa = casos propios en seguimiento por standup (sin pausa, RSP ni cierre).';
  we.getCell(fN, 1).font = { italic: true, size: 9, color: { argb: 'FF595959' } };

  // Hoja por colaborador
  for (const dev of C.EQUIPO) {
    const m = actual[dev], ws = wb.addWorksheet(dev.split(' ')[0]);
    ws.columns = [{ width: 34 }, { width: 14 }, { width: 14 }, { width: 14 }, { width: 14 }, { width: 12 }, { width: 12 }, { width: 40 }];
    titulo(ws, 1, `${dev} — ${nombreMes}`);
    const prev = tendencia.slice(0, -1).map(t => t.por[dev]).filter(x => x.atendidos);
    const pm = k => prev.length ? r1(C.promedio(prev.map(x => x[k]).filter(v => v !== null && v !== undefined))) : null;
    const eq = k => r1(C.promedio(C.EQUIPO.map(d => actual[d][k]).filter(v => v !== null && v !== undefined)));
    encabezado(ws, 3, ['Métrica', 'Este mes', 'Meses anteriores (prom.)', 'Promedio del equipo']);
    const kpis = [['Casos atendidos', 'atendidos'], ['Nuevos asignados', 'nuevos'], ['Entregados', 'entregados'], ['Liberados (LDP)', 'liberados'],
      ['Entrega de cambios, mediana (días háb.)', 'entregaMedC'], ['Entrega de fallos/AP, mediana', 'entregaMedF'], ['Asignación → LDP, mediana', 'liberacionMed'],
      ['RSP → LDP, mediana', 'rspLdpMed'], ['Cumplimiento por criticidad', 'cumplimiento'], ['Casos con REVPR', 'conRevpr'], ['Hallazgos PR Alta', 'prAlta'],
      ['Carga activa promedio', 'wipProm'], ['Carga máxima', 'wipMax'], ['Casos probados como tester', 'tester']];
    for (const [t, k] of kpis) {
      const r = ws.addRow([t, m[k], pm(k), eq(k)]);
      if (k === 'cumplimiento') [2, 3, 4].forEach(i => r.getCell(i).numFmt = '0%');
      [2, 3, 4].forEach(i => r.getCell(i).alignment = { horizontal: 'center' });
    }
    ws.addRow([`ORIGEN causados: ${m.origenes.length} · Reaperturas: ${m.reaperturas.length}`]);

    let f = ws.lastRow.number + 2;
    titulo(ws, f, `Fortalezas y dificultades (acumulado del ${C.dmy(C.deIso(C.INICIO_DATOS))} al ${C.dmy(per.fin)})`);
    encabezado(ws, f + 1, ['Categoría / valor', 'Casos entregados', 'Su mediana (días)', 'Resto del equipo', 'Índice', 'ORIGEN + reaperturas', 'Fuera de objetivo', 'Lectura'], 30);
    for (const p of perfiles[dev]) {
      const r = ws.addRow([`${p.cat}: ${p.valor}`, p.n, p.mS, p.mR, p.indice, p.incid, p.fuera, p.lectura]);
      [2, 3, 4, 5, 6, 7].forEach(i => r.getCell(i).alignment = { horizontal: 'center' });
      if (p.lectura === 'Fortaleza') r.eachCell(c => c.fill = VERDE);
      if (p.lectura === 'Dificultad') r.eachCell(c => c.fill = ROJO);
    }
    ws.addRow(['Índice = su mediana ÷ mediana del resto del equipo (< 1 = más rápido). Fortaleza: índice ≤ 0.8 sin fallos fuera de objetivo. Dificultad: índice ≥ 1.25, alguna ORIGEN o reapertura, o 2 o más fallos fuera de objetivo. Se requieren 3 casos.'])
      .getCell(1).font = { italic: true, size: 9, color: { argb: 'FF595959' } };

    const incid = [...m.incumplidos.map(c => [c.tt, `Fuera de objetivo ${c.criticidad}`, c.diasEntrega, C.OBJETIVOS[c.criticidad], c.titulo]),
      ...m.origenes.map(o => [o.tt, `ORIGEN → ${o.nuevo}`, null, null, o.causa]), ...m.reaperturas.map(o => [o.tt, 'REABIERTO', null, null, o.motivo]),
      ...m.lista.filter(c => c.pr && c.pr.alta).map(c => [c.tt, `PR ${c.pr.version}: ${c.pr.alta} Alta`, null, null, c.pr.veredicto])];
    if (incid.length) {
      f = ws.lastRow.number + 2;
      titulo(ws, f, 'Incidencias del mes');
      encabezado(ws, f + 1, ['Caso', 'Incidencia', 'Días', 'Objetivo', 'Detalle']);
      for (const x of incid) ws.addRow(x);
    }
  }

  // Tendencia
  const wt = wb.addWorksheet('Tendencia');
  titulo(wt, 1, 'Tendencia mensual');
  encabezado(wt, 3, ['Mes', 'Colaborador', 'Atendidos', 'Entregados', 'Liberados', 'Entrega cambios (med.)', 'Entrega fallos (med.)', 'Cumplimiento', 'ORIGEN + reaperturas', 'Carga activa'], 30);
  for (const t of tendencia) for (const dev of C.EQUIPO) {
    const m = t.por[dev];
    const r = wt.addRow([t.mes, dev, m.atendidos, m.entregados, m.liberados, m.entregaMedC, m.entregaMedF, m.cumplimiento, m.origenes.length + m.reaperturas.length, m.wipProm]);
    r.getCell(8).numFmt = '0%';
  }
  wt.columns.forEach((c, i) => { c.width = i === 1 ? 17 : 14; });

  // Mapa de módulos
  const wm = wb.addWorksheet('Módulos');
  titulo(wm, 1, 'Conocimiento por módulo (acuerdos de versión desde 2024 + casos desde 09/2026)');
  encabezado(wm, 3, ['Módulo', ...C.EQUIPO, 'Total', 'Principal', '% principal', 'Cobertura'], 30);
  for (const x of mapa) {
    const r = wm.addRow([x.modulo, ...C.EQUIPO.map(d => x.devs[d] || null), x.total, x.principal, x.pct, x.cobertura]);
    r.getCell(9).numFmt = '0%';
    if (x.cobertura === 'Solo una persona') r.eachCell(c => c.fill = ROJO);
  }
  wm.columns.forEach((c, i) => { c.width = i === 0 ? 34 : 13; });

  // Detalle
  const wd = wb.addWorksheet('Detalle', { views: [{ state: 'frozen', ySplit: 1 }] });
  const colsD = ['Caso', 'Colaborador', 'Tipo', 'Título', 'Módulo', 'Criticidad', 'Complejidad', 'Asignación', 'Fuente asig.', 'Entrega', 'RSP', 'LDP', 'Cierre CEC',
    'Días entrega', 'Días a LDP', 'RSP → LDP', 'Cumple criticidad', 'REVPR', 'Reaperturas', 'ORIGEN causados', 'PR A/M/B', 'Último estatus'];
  encabezado(wd, 1, colsD, 30);
  const delMes = casos.filter(c => c.dev && C.EQUIPO.includes(c.dev) && actual[c.dev].lista.includes(c));
  for (const c of delMes.sort((a, b) => a.dev.localeCompare(b.dev) || C.numTT(a.tt) - C.numTT(b.tt))) {
    wd.addRow([c.tt, c.dev, TIPOS[c.tipo] || c.tipo, c.titulo, c.modulo, c.criticidad, c.complejidad, fechaCel(c.asignacion), c.fuenteAsig, fechaCel(c.entrega), fechaCel(c.rsp),
      fechaCel(c.ldp), fechaCel(c.cierre), c.diasEntrega, c.diasLiberacion, c.diasRspLdp, c.cumpleCriticidad === null ? null : c.cumpleCriticidad ? 'Sí' : 'No',
      c.revpr || null, c.reaperturas.length || null, c.origenes.length || null, c.pr ? `${c.pr.alta}/${c.pr.media}/${c.pr.baja}` : null, c.ultimoEstatus]);
  }
  [8, 10, 11, 12, 13].forEach(k => wd.getColumn(k).numFmt = 'dd/mm/yyyy');
  const anchos = [10, 15, 12, 55, 18, 11, 13, 12, 11, 11, 11, 11, 12, 9, 9, 9, 12, 8, 13, 10, 10, 40];
  anchos.forEach((w, i) => wd.getColumn(i + 1).width = w);
  wd.autoFilter = { from: 'A1', to: { row: 1, column: colsD.length } };

  wb.eachSheet(ws => ws.eachRow(r => r.eachCell(c => { if (!c.font || !c.font.name) c.font = { ...(c.font || {}), name: 'Calibri' }; })));
  fs.mkdirSync(per.carpeta, { recursive: true });
  await wb.xlsx.writeFile(per.salida);

  const resumen = Object.fromEntries(C.EQUIPO.map(dev => {
    const { lista, incumplidos, ...m } = actual[dev];
    return [dev, { ...m, incumplidos: incumplidos.map(c => `${c.tt} ${c.criticidad} ${c.diasEntrega}/${C.OBJETIVOS[c.criticidad]}`),
      fortalezas: perfiles[dev].filter(p => p.lectura === 'Fortaleza').map(p => `${p.cat}: ${p.valor} (n=${p.n}, índice ${p.indice})`),
      dificultades: perfiles[dev].filter(p => p.lectura === 'Dificultad').map(p => `${p.cat}: ${p.valor} (n=${p.n}, índice ${p.indice}, incid. ${p.incid}, fuera ${p.fuera})`) }];
  }));
  console.log(JSON.stringify({ salida: per.salida, casosDelMes: delMes.length, resumen,
    modulosUnaPersona: mapa.filter(x => x.cobertura === 'Solo una persona').map(x => `${x.modulo} (${x.principal}, ${x.total})`) }, null, 1));
}

main().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
