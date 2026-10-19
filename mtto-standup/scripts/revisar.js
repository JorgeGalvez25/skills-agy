// Uso: node revisar.js mensajes.json [dd/mm/aaaa]
// mensajes.json: [{ "fecha": "2026-10-06 16:08", "autor": "Saulo Lopez", "texto": "..." }, ...] (o "ts" de Slack en lugar de "fecha").
// Revisa el último standup de cada colaborador del día indicado (por defecto el día hábil anterior; "hoy" para el día actual) contra sus standups anteriores
// e imprime en JSON los hallazgos por colaborador.
// Los hallazgos que coinciden con una aclaración vigente de ../aclaraciones.json (lo que el colaborador explicó por DM
// y Jorge aceptó) no se reportan como hallazgo: pasan a "aclarados" con la nota.
const fs = require('fs');
const path = require('path');
const ARCH_ACLARACIONES = path.join(__dirname, '..', 'aclaraciones.json');

const DIAS_ESTANCADO = 5;      // días hábiles con el mismo estatus
const DIAS_SIN_CASO = 5;       // días hábiles con trabajo "pendiente de caso" o sin TT
const DESFASE_SLACK_H = -7;    // Slack muestra los mensajes en MST (UTC-7)
const INICIO_SOLO_HOY = '2026-10-08'; // desde esta fecha el standup lleva solo el bloque "Hoy"
// Martín atiende directo al cliente JAG y registra ese tiempo en una actividad aparte: sus líneas de JAG sin TT no se marcan
const sinTtPermitido = (autor, linea) => /^mart[ií]n reyes$/i.test(autor) && /\bJAG\b/i.test(linea);

// ---------- Fechas ----------
const utc = (a, m, d) => new Date(Date.UTC(a, m - 1, d));
const pad = n => String(n).padStart(2, '0');
const dmy = d => `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
function leerFecha(v) {
  let m = String(v).match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?/);
  if (m) return { dia: utc(+m[1], +m[2], +m[3]), hora: m[4] ? `${pad(m[4])}:${m[5]}` : null };
  m = String(v).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?/);
  if (m) return { dia: utc(+m[3], +m[2], +m[1]), hora: m[4] ? `${pad(m[4])}:${m[5]}` : null };
  throw new Error(`Fecha no reconocida: "${v}"`);
}
function fechaTs(ts) {
  const d = new Date((parseFloat(ts) + DESFASE_SLACK_H * 3600) * 1000);
  return { dia: utc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()), hora: `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}` };
}
// Días de descanso obligatorio (LFT art. 74)
function nLunes(a, mes, n) { const d = new Date(Date.UTC(a, mes, 1)); return new Date(Date.UTC(a, mes, 1 + (8 - d.getUTCDay()) % 7 + 7 * (n - 1))); }
function feriados(a) {
  const l = [utc(a, 1, 1), nLunes(a, 1, 1), nLunes(a, 2, 3), utc(a, 5, 1), utc(a, 9, 16), nLunes(a, 10, 3), utc(a, 12, 25)];
  if ((a - 2024) % 6 === 0) l.push(utc(a, 10, 1));
  return new Set(l.map(f => f.getTime()));
}
const esHabil = d => d.getUTCDay() % 6 !== 0 && !feriados(d.getUTCFullYear()).has(d.getTime());
function habilesEntre(a, b) { // hábiles en (a, b]
  let n = 0;
  for (let t = a.getTime() + 864e5; t <= b.getTime(); t += 864e5) if (esHabil(new Date(t))) n++;
  return n;
}

// ---------- Texto ----------
const sinAcentos = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '');
const limpiar = l => l.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
  .replace(/<@[A-Z0-9]+(\|[^>]*)?>/g, '').replace(/[*_~`]/g, '')
  .replace(/^[\s•◦▪︎\-–·]+/, '').trim();
const RX_DIA = /^(ayer|hoy|viernes|lunes|martes|miercoles|jueves|sabado|domingo)\s*:?\s*$/i;
const RX_SECCION = /^(standby|stand by|seguimiento)\s*:?\s*$/i;
const RX_EVENTO = /^(LDP|LIBERADO|REABIERTO|ORIGEN)\b/i; // LIBERADO: eventos anteriores al 09/10/2026

// Cancelado: "TT#####: Cancelado" o la línea "CANCELADO TT##### | ..." dentro del standup.
// No incluye "se cancele", "cancelar", etc. (posibilidades, no estatus).
const RX_CANCELADO = /\bcancelad[oa]s?\b|\bcancelacion\b/i;
// LDP: el tester liberó de pruebas. "En espera de LDP", "SDP enviada"... no son cierre.
const esLdp = est => { const s = sinAcentos(est).toLowerCase(); return /\bldp\b|liberad[oa] de pruebas/.test(s) && !/espera|pendiente|falta|solicit|\bsdp\b/.test(s); };
const esCierre = est => /\bcec\b|cerrad/i.test(sinAcentos(est)) || RX_CANCELADO.test(sinAcentos(est)) || esLdp(est);

// Rango de avance del estatus (5 = cierre; un cerrado que reaparece es retroceso)
function rango(est) {
  const s = sinAcentos(est.toLowerCase());
  if (/cierre/.test(s) || esCierre(s)) return 5;
  if (/entreg|\brsp\b|liberad|instalad/.test(s)) return 4;
  if (/prueba|compila|integra|document/.test(s)) return 3;
  if (/codific|correcci|desarroll/.test(s)) return 2;
  if (/revis|analis|consult|espera|pausa|pendiente|standby/.test(s)) return 1;
  return 0;
}
const esRsp = est => /\brsp\b|revision scrum/i.test(sinAcentos(est));
const esFinal = est => esCierre(est) || esRsp(est);

// Pruebas iniciadas: una vez que el caso entra a pruebas no hay retroceso ni reapertura hasta la LDP;
// lo que encuentre el tester se corrige en el mismo TT. SDP, tester o "en espera de LDP" lo indican siempre;
// "pruebas", "integración", MAIN o SCRUM, solo después de RSP (antes pueden ser pruebas del desarrollo).
const RX_PRUEBAS = /\bsdp\b|tester|espera de (la )?ldp/;
const RX_PRUEBAS_RSP = /prueba|integraci|\bmain\b|scrum/;
function iniciaronPruebas(estatus) {
  let trasRsp = false;
  for (const e of estatus) {
    const s = sinAcentos(e).toLowerCase();
    if (RX_PRUEBAS.test(s)) return true;
    if (/\brsp\b|revision scrum/.test(s)) { trasRsp = true; continue; }
    if (trasRsp && RX_PRUEBAS_RSP.test(s)) return true;
  }
  return false;
}

// Vocabulario de estatus para detectar errores de dedo
const VOCAB = ['entregado', 'entrega', 'revisando', 'revision', 'pruebas', 'codificando', 'codificacion', 'pausado', 'pendiente',
  'espera', 'respuesta', 'cierre', 'analisis', 'documentacion', 'documentando', 'compilacion', 'retroalimentacion', 'correccion', 'integracion', 'consultar', 'estado'];
function distancia(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}
// Conjugaciones válidas que se parecen al vocabulario
const VALIDAS = ['entrego', 'entregue', 'entregar', 'entregas', 'reviso', 'revise', 'revisar', 'revisado', 'prueba', 'probando',
  'codifico', 'codificar', 'pausar', 'pausada', 'esperar', 'esperando', 'pendientes', 'respuestas', 'consulta', 'estados'];
function erroresDedo(texto) {
  const r = [];
  for (const p of sinAcentos(texto.toLowerCase()).replace(/x\s?\d+\b/g, ' ').split(/[^a-zñ]+/)) {
    if (p.length < 6 || VOCAB.includes(p) || VALIDAS.includes(p)) continue;
    const v = VOCAB.find(w => Math.abs(w.length - p.length) <= 1 && distancia(p, w) === 1);
    if (v) r.push(`"${p}" → "${v}"`);
  }
  return r;
}

// Códigos de estatus del formato abreviado de Saulo (RSP, CEC y LDP se quedan igual)
const CODIGOS = { P: 'Pausa', R: 'Revisando', AN: 'Analizando', D: 'Desarrollo', PIL: 'Piloto', ENT: 'Entregado', EST: 'Preguntar estatus', CAN: 'Cancelado' };

// Convierte el texto de un standup en bloques { etiqueta, items[] }.
// Sin título de día, la primera sección standby/seguimiento abre el bloque "hoy".
function parsear(texto) {
  const bloques = [];
  let bloque = null, seccion = null;
  for (const bruta of texto.split(/\r?\n/)) {
    const l = limpiar(bruta);
    if (!l) continue;
    const mDia = sinAcentos(l).match(RX_DIA);
    if (mDia) { bloque = { etiqueta: mDia[1].toLowerCase(), items: [] }; bloques.push(bloque); seccion = null; continue; }
    if (RX_SECCION.test(l)) {
      if (!bloque) { bloque = { etiqueta: 'hoy', items: [] }; bloques.push(bloque); }
      seccion = l.replace(/:$/, '').trim().toLowerCase(); continue;
    }
    if (!bloque || RX_EVENTO.test(l)) continue;
    const item = { linea: l, seccion, tt: null, idSinPrefijo: false, estatus: l, contador: null };
    let m = l.match(/\bTT\s*-?\s*(\d+)/i);
    if (m) item.tt = 'TT' + m[1];
    else if ((m = l.match(/^(\d{5,6})\b/))) { item.tt = 'TT' + m[1]; item.idSinPrefijo = true; }
    if (item.tt) {
      const i = l.indexOf(':');
      item.estatus = i >= 0 ? l.slice(i + 1).trim() : l.replace(/\bTT\s*-?\s*\d+\s*/i, '').replace(/^\d{5,6}\s*/, '').trim();
      // Formatos con tipo y estatus antes de los dos puntos: "TT##### - C - RSP: ..." o "TT##### Cambio · Pausa: ..."
      const mT = l.match(/\bTT\s*-?\s*\d+\s*(?:[-–·]\s*)?(?:C|F|M|Cambio|Fallo|Mejora)\s*[-–·]\s*([^:]{1,25}?)\s*:\s*(.*)$/i);
      if (mT) item.estatus = `${CODIGOS[mT[1].toUpperCase()] || mT[1]}: ${mT[2]}`.trim();
      if (/^cancelad[oa]\b/i.test(sinAcentos(l)) && !RX_CANCELADO.test(sinAcentos(item.estatus))) item.estatus = 'Cancelado · ' + item.estatus;
    }
    const c = item.estatus.match(/(?:^|[a-záéíóú\s)])x\s?(\d{1,2})\b(?!\s*[a-z])/i);
    if (c) item.contador = +c[1];
    item.idCorto = item.tt && item.tt.length - 2 < 5;
    bloque.items.push(item);
  }
  return bloques;
}
// Bloque "Hoy" de un standup (con el formato anterior, el último bloque)
const bloqueHoy = s => s.bloques.find(b => b.etiqueta === 'hoy') || s.bloques[s.bloques.length - 1];
const llave = s => sinAcentos(s.toLowerCase()).replace(/x\s?\d+\b/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
// Línea sin TT: se identifica sin lo que va entre paréntesis, que suele cambiar ("pendiente de caso, ya le dije a…")
const llaveSinTt = l => llave(l.replace(/\([^)]*\)?/g, ''));
// Mismo estatus aunque cambie el formato ("pruebas" → "Pausa: pruebas", "EST: …" → "Preguntar estatus: …")
const mismoEstatus = (a, b) => a === b || (Math.min(a.length, b.length) >= 4 && (a.includes(b) || b.includes(a)));
// Actividades que no son casos y no necesitan TT
const RX_NO_CASO = /curso|udemy|capacitaci|scrum|informe|reuni|junta|posada|vacacion|eventos/i;
// Trabajo sin TT: empieza con el tipo ("Fallo - …", "Cambio: …", "Apoyo …") o dice que está pendiente de caso
const RX_TRABAJO = /^(fallo|cambio|mejora|apoyo)\b|pendiente de caso|sin id|sin caso/i;

// Aclaración vigente que cubre el hallazgo x (regla, tt, detalle) del colaborador autor.
// Campos (solo colaborador y nota son obligatorios): regla, tt, texto (fragmento del detalle),
// estatus (vale mientras el TT siga con ese estatus en el standup revisado), hasta (dd/mm/aaaa).
function aclaracion(aclaraciones, autor, x, estatusHoy, dia) {
  return aclaraciones.find(a => llave(a.colaborador) === llave(autor) &&
    (!a.regla || a.regla === x.regla) &&
    (!a.tt || a.tt.toUpperCase() === x.tt) &&
    (!a.texto || llave(x.detalle).includes(llave(a.texto))) &&
    (!a.hasta || dia <= leerFecha(a.hasta).dia) &&
    (!a.estatus || (!!x.tt && estatusHoy(x.tt) !== null && llave(estatusHoy(x.tt)) === llave(a.estatus))));
}

try {
  const [arch, fechaArg] = process.argv.slice(2);
  if (!arch || !fs.existsSync(arch)) throw new Error('Falta el archivo JSON de mensajes.');
  const crudos = JSON.parse(fs.readFileSync(arch, 'utf8'));
  const hoyN = new Date();
  const diaActual = utc(hoyN.getFullYear(), hoyN.getMonth() + 1, hoyN.getDate());
  let dia = diaActual;
  if (!fechaArg || /^ayer$/i.test(fechaArg)) do dia = new Date(dia.getTime() - 864e5); while (!esHabil(dia));
  else if (!/^hoy$/i.test(fechaArg)) dia = leerFecha(fechaArg).dia;
  const aclaraciones = fs.existsSync(ARCH_ACLARACIONES) ? JSON.parse(fs.readFileSync(ARCH_ACLARACIONES, 'utf8')) : [];

  // Standups y eventos
  const standups = {}, eventos = [];
  for (const m of crudos) {
    const f = m.ts ? fechaTs(m.ts) : leerFecha(m.fecha);
    const texto = String(m.texto || '');
    for (const l of texto.split(/\r?\n/).map(limpiar)) if (RX_EVENTO.test(l)) {
      const tt = (l.match(/TT\s*-?\s*(\d+)/i) || [])[1];
      eventos.push({ tipo: l.split(/\s/)[0].toUpperCase(), tt: tt ? 'TT' + tt : null, linea: l, dia: f.dia });
    }
    const bloques = parsear(texto);
    if (!bloques.length) continue;
    (standups[m.autor] = standups[m.autor] || []).push({ dia: f.dia, hora: f.hora, bloques, texto });
  }

  const resultado = { fecha: dmy(dia), colaboradores: {} };
  for (const [autor, lista] of Object.entries(standups)) {
    // Uno por día: el último publicado
    const porDia = {};
    for (const s of lista.sort((a, b) => a.dia - b.dia || String(a.hora).localeCompare(String(b.hora)))) porDia[s.dia.getTime()] = s;
    const serie = Object.values(porDia).sort((a, b) => a.dia - b.dia);
    const act = serie.find(s => s.dia.getTime() === dia.getTime());
    const h = [];
    const r = { standupDeHoy: !!act, hora: act ? act.hora : null, hallazgos: h, estancados: [], aclarados: [], faltantes: [] };
    resultado.colaboradores[autor] = r;
    // Un día sin standup no es hallazgo por sí solo: se revisa en el siguiente que publique (solo informativo para Jorge)
    if (!act) {
      const ult = serie.filter(s => s.dia < dia).pop();
      r.faltantes.push({ dia: dmy(dia), ultimoStandup: ult ? dmy(ult.dia) : null });
      continue;
    }
    const previos = serie.filter(s => s.dia < dia);
    const ant = previos[previos.length - 1];
    const bHoy = bloqueHoy(act);
    // Estatus del TT en sus standups anteriores y hoy, en orden
    const historial = tt => [...previos, act].map(p => bloqueHoy(p).items.find(i => i.tt === tt)).filter(Boolean).map(i => i.estatus);

    // Estructura: solo secciones standby/seguimiento con casos, sin títulos de día
    const titulos = [...new Set(act.bloques.map(b => b.etiqueta).filter(e => e !== 'hoy'))];
    if (titulos.length && dia >= leerFecha(INICIO_SOLO_HOY).dia)
      h.push({ regla: 'estructura', detalle: `Incluye el bloque "${titulos.join('", "')}"; desde el ${dmy(leerFecha(INICIO_SOLO_HOY).dia)} el standup lleva solo las secciones standby y seguimiento.` });
    if (!bHoy.items.length)
      h.push({ regla: 'estructura', detalle: 'El standup no tiene casos en standby ni en seguimiento.' });

    // Días hábiles sin standup desde el anterior: se toleran si la continuidad cuadra (ver más abajo)
    const faltan = ant ? habilesEntre(ant.dia, dia) - 1 : 0;
    if (faltan > 0) for (let t = ant.dia.getTime() + 864e5; t < dia.getTime(); t += 864e5)
      if (esHabil(new Date(t))) r.faltantes.push({ dia: dmy(new Date(t)), ultimoStandup: dmy(ant.dia) });

    if (ant) {
      const set = b => new Map(b.items.filter(i => i.tt).map(i => [i.tt, i]));
      const mHoyAnt = set(bloqueHoy(ant)), mHoy = set(bHoy);

      // Seguimiento copiado sin cambios del standup anterior (standby puede repetirse)
      const lineas = b => b.items.filter(i => !/stand/.test(i.seccion || '')).map(i => i.linea).sort().join('|');
      if (lineas(bHoy) && lineas(bHoy) === lineas(bloqueHoy(ant)))
        h.push({ regla: 'copiado', detalle: `La sección de seguimiento es idéntica a la del standup del ${dmy(ant.dia)}: ningún caso cambió de estatus ni de contador.` });

      // TT que sale del "Hoy" sin estatus final
      for (const [tt, it] of mHoyAnt) if (!mHoy.has(tt) && !esFinal(it.estatus))
        h.push({ regla: 'desaparece', tt, detalle: `${tt} estaba en su standup del ${dmy(ant.dia)} ("${it.estatus}") y ya no aparece, sin estatus de cierre (RSP, LDP, CEC, cancelado).` });

      // Contadores
      for (const [tt, it] of mHoy) {
        const prev = mHoyAnt.get(tt);
        if (!prev) continue;
        if (prev.contador && it.contador && (it.contador < prev.contador || it.contador > prev.contador + 1 + faltan))
          h.push({ regla: 'contador', tt, detalle: `${tt}: el contador pasó de x${prev.contador} a x${it.contador}.` });
        if (prev.contador && !it.contador && llave(prev.estatus) === llave(it.estatus))
          h.push({ regla: 'contador', tt, detalle: `${tt}: tenía x${prev.contador} y hoy no trae contador con el mismo estatus.` });
      }
      // Reapertura: de RSP regresa a revisión/codificación (de Entregado no: es parte del ciclo antes de que el cliente
      // lo dé por bueno). Se compara con la última vez que apareció, porque un caso en RSP puede salir del standup y volver días después.
      for (const [tt, it] of mHoy) {
        let ult = null;
        for (const p of previos) { const x = bloqueHoy(p).items.find(i => i.tt === tt); if (x) ult = { it: x, dia: p.dia }; }
        if (!ult || esCierre(ult.it.estatus) || !esRsp(ult.it.estatus) || iniciaronPruebas(historial(tt))) continue;
        const r1 = rango(it.estatus);
        if (r1 < 1 || r1 > 2) continue;
        if (eventos.some(e => e.tt === tt && e.tipo === 'REABIERTO' && e.dia >= ult.dia)) continue; // ya registrada
        h.push({ regla: 'retroceso', tt, detalle: `${tt} pasó de "${ult.it.estatus}" (${dmy(ult.dia)}) a "${it.estatus}" y no hay mensaje REABIERTO en el canal.` });
      }
      // Cerrado (CEC, cancelado, LDP) que reaparece. CEC o cancelado que regresa a trabajo es reapertura (lleva REABIERTO);
      // LDP no se reabre. Un cancelado ya no aparece en el siguiente standup, aunque sea con otro cierre (p. ej. CEC).
      const avisados = new Set();
      for (const p of previos) for (const b of p.bloques) for (const it of b.items) {
        if (!it.tt || !esCierre(it.estatus) || !mHoy.has(it.tt) || avisados.has(it.tt)) continue;
        const hoyEst = mHoy.get(it.tt).estatus;
        const cancelado = RX_CANCELADO.test(sinAcentos(it.estatus));
        let detalle = null;
        if (esLdp(it.estatus)) {
          if (!esLdp(hoyEst)) detalle = `${it.tt} se reportó "${it.estatus}" el ${dmy(p.dia)} y vuelve a aparecer hoy ("${hoyEst}"). Después de la LDP el caso no se reabre: el problema nuevo va en otro TT (con ORIGEN si lo causó este).`;
        } else if (rango(hoyEst) < 5) {
          if (!eventos.some(e => e.tt === it.tt && e.tipo === 'REABIERTO' && e.dia >= p.dia))
            detalle = `${it.tt} se reportó "${it.estatus}" el ${dmy(p.dia)} y vuelve a aparecer hoy ("${hoyEst}") sin mensaje REABIERTO en el canal.`;
        } else if (cancelado && !RX_CANCELADO.test(sinAcentos(hoyEst)))
          detalle = `${it.tt} se reportó "${it.estatus}" el ${dmy(p.dia)} y hoy aparece con "${hoyEst}". Un cancelado ya no aparece en el siguiente standup; si iba a cerrarse con otro estatus, se anota ese directamente.`;
        if (detalle) { avisados.add(it.tt); h.push({ regla: 'retroceso', tt: it.tt, detalle }); }
      }
    }

    // IDs, duplicados y errores de dedo en el standup de hoy
    for (const b of act.bloques) {
      const vistos = new Set();
      for (const it of b.items) {
        if (it.idSinPrefijo) h.push({ regla: 'id', tt: it.tt, detalle: `"${it.linea}": el ID va sin el prefijo TT.` });
        if (it.idCorto) h.push({ regla: 'id', tt: it.tt, detalle: `"${it.linea}": el ID tiene menos de 5 dígitos.` });
        if (it.tt && vistos.has(it.tt)) h.push({ regla: 'id', tt: it.tt, detalle: `${it.tt} aparece dos veces en el bloque "${b.etiqueta}".` });
        if (it.tt) vistos.add(it.tt);
        if ((/tt\s*sin\s*id/i.test(it.linea) || /^tt\s*:/i.test(it.linea)) && !sinTtPermitido(autor, it.linea)) h.push({ regla: 'id', detalle: `"${it.linea}": trabajo registrado sin número de caso.` });
        // Trabajo nuevo sin TT (si ya venía de antes, lo cubre sin-caso)
        else if (!it.tt && b === bHoy && RX_TRABAJO.test(it.linea) && !RX_NO_CASO.test(it.linea) && !sinTtPermitido(autor, it.linea) &&
          !(ant && bloqueHoy(ant).items.some(x => !x.tt && llaveSinTt(x.linea) === llaveSinTt(it.linea))))
          h.push({ regla: 'id', detalle: `"${it.linea}": trabajo sin número de caso.` });
        for (const e of erroresDedo(it.estatus)) h.push({ regla: 'ortografia', tt: it.tt, detalle: `Posible error de dedo ${e} en "${it.linea}".` });
        // REABIERTO aplica a lo que ya estuvo en RSP (si ya se marcó retroceso, no se repite)
        const tuvoRsp = it.tt && previos.some(p => bloqueHoy(p).items.some(x => x.tt === it.tt && !esCierre(x.estatus) && esRsp(x.estatus)));
        if (tuvoRsp && !iniciaronPruebas(historial(it.tt)) && !h.some(x => x.regla === 'retroceso' && x.tt === it.tt) &&
          /reabr|regres[oó]|volvi[oó] a|otra vez|de nuevo/i.test(it.estatus) && !eventos.some(e => e.tt === it.tt && /REABIERTO|ORIGEN/.test(e.tipo)))
          h.push({ regla: 'evento', tt: it.tt, detalle: `${it.tt} estuvo en RSP, hoy dice "${it.estatus}" y no hay mensaje REABIERTO u ORIGEN en el canal.` });
        if (it.tt && esLdp(it.estatus) && !eventos.some(e => e.tt === it.tt && /LDP|LIBERADO/.test(e.tipo)))
          h.push({ regla: 'evento', tt: it.tt, detalle: `${it.tt} dice "${it.estatus}" y no hay mensaje LDP en el canal.` });
      }
    }

    // Estancamiento y trabajo sin caso a lo largo de la serie
    const desde = {};
    for (const s of serie.filter(x => x.dia <= dia)) {
      for (const it of bloqueHoy(s).items) {
        const k = it.tt || 'sin:' + llaveSinTt(it.linea);
        const e = it.tt ? llave(it.estatus) : '';
        if (!desde[k] || !mismoEstatus(desde[k].e, e)) desde[k] = { e, dia: s.dia, it };
        desde[k].e = e; desde[k].it = it; // se compara contra la redacción más reciente
        desde[k].ultimo = s.dia;
      }
    }
    for (const [k, v] of Object.entries(desde)) {
      if (v.ultimo.getTime() !== dia.getTime()) continue;
      const n = habilesEntre(v.dia, dia);
      if (k.startsWith('sin:') && !RX_NO_CASO.test(v.it.linea) && n >= DIAS_SIN_CASO && !sinTtPermitido(autor, v.it.linea))
        h.push({ regla: 'sin-caso', detalle: `"${v.it.linea}" lleva al menos ${n} días hábiles sin número de caso (desde el ${dmy(v.dia)}).` });
      if (!k.startsWith('sin:') && n >= DIAS_ESTANCADO && !esFinal(v.it.estatus))
        r.estancados.push({ tt: k, estatus: v.it.estatus, desde: dmy(v.dia), diasHabiles: n });
    }

    // Hueco de standups: solo se señala si al comparar con el anterior algo no cuadra
    const CONTINUIDAD = ['desaparece', 'copiado', 'contador', 'retroceso', 'evento'];
    if (faltan > 0 && h.some(x => CONTINUIDAD.includes(x.regla)))
      h.unshift({ regla: 'sin-standup', detalle: `No hay standup en ${faltan} día(s) hábil(es) entre el ${dmy(ant.dia)} y hoy, y al comparar con el del ${dmy(ant.dia)} hay cambios sin explicar.` });

    // Lo que el colaborador ya aclaró (y Jorge aceptó) no se vuelve a señalar
    const estatusHoy = tt => { const i = bHoy.items.find(x => x.tt === tt); return i ? i.estatus : null; };
    const aplicar = lista => lista.filter(x => {
      const a = aclaracion(aclaraciones, autor, x, estatusHoy, dia);
      if (a) r.aclarados.push({ regla: x.regla, tt: x.tt, detalle: x.detalle, nota: a.nota, fuente: a.fuente });
      return !a;
    });
    r.hallazgos = aplicar(h);
    r.estancados = aplicar(r.estancados.map(e => ({ regla: 'estancados', detalle: `${e.tt}: "${e.estatus}" desde el ${e.desde}`, ...e })))
      .map(({ regla, detalle, ...e }) => e);
  }

  // TT reportado por más de un colaborador hoy
  const duenos = {};
  for (const [autor, lista] of Object.entries(standups)) for (const s of lista) if (s.dia.getTime() === dia.getTime())
    for (const b of s.bloques) for (const it of b.items) if (it.tt) (duenos[it.tt] = duenos[it.tt] || new Set()).add(autor);
  // Sin hallazgos repetidos
  for (const c of Object.values(resultado.colaboradores)) {
    const v = new Set();
    c.hallazgos = c.hallazgos.filter(x => { const k = x.regla + '|' + x.detalle.replace(/ x\d+/g, ''); return !v.has(k) && v.add(k); });
  }
  resultado.ttCompartidos = Object.entries(duenos).filter(([, s]) => s.size > 1).map(([tt, s]) => ({ tt, colaboradores: [...s] }));
  resultado.ventana = { standups: Object.values(standups).flat().length, eventos: eventos.length, aclaraciones: aclaraciones.length };
  console.log(JSON.stringify(resultado, null, 2));
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(1);
}
