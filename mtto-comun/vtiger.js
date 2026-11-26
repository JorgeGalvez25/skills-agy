// VTiger: lecturas directas al webservice (access key propio) y escrituras por la API de MelissaVirtual (cuenta propia).
// Credenciales en C:\Users\jorge\.mtto\vtiger.json { usuario, password, accessKey, url, api }. Nunca se imprimen.
//   node vtiger.js caso TT#####                     -> detalle del caso, comentarios y caso de soporte relacionado
//   node vtiger.js buscar <TT#####|texto>           -> casos por número, por ticket de soporte (cf_1275) o por título
//   node vtiger.js tablero [colaborador]            -> casos abiertos de Proyectos del equipo, por colaborador y estatus
//   node vtiger.js casos TT##### [TT#####...]        -> ficha corta de varios casos (y los definitivos que los tienen como soporte)
//   node vtiger.js vista TT#####                    -> encabezado del caso como lo muestra VTiger (para la imagen del ACA)
//   node vtiger.js promesas [colaborador]           -> fallos en PROCESO (Revisión) y ENTREGADO con su fecha promesa
//   node vtiger.js fallos YYYYMM                    -> relación de fallos atendidos del mes (mismas columnas que el reporte de VTiger)
//   node vtiger.js query "<VTQL sin LIMIT>"         -> consulta libre, paginada
//   node vtiger.js mover TT##### <acción> [fecha=AAAA-MM-DD] [usuario=Nombre] [motivo=..] [observaciones=..] [notificar=si|no] [--confirmar]
//                                                    -> sin --confirmar solo muestra lo que haría
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const E = require('./equipo');

const CRED = process.env.MTTO_VTIGER || path.join(require('os').homedir(), '.mtto', 'vtiger.json');
const LOG = process.env.MTTO_VTIGER_LOG || 'C:/Users/jorge/Dropbox/MTTO/ReportesMTTO/datos/vtiger_escrituras.log';
const cfg = () => JSON.parse(fs.readFileSync(CRED, 'utf8').replace(/^\uFEFF/, ''));
const pad = n => String(n).padStart(2, '0');
const hoy = () => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };

// Campos de HelpDesk que usan las skills
const CAMPOS = {
  id: 'Id', ticket_no: 'Caso', ticket_title: 'Título', cf_867: 'Tipo', cf_751: 'Clase', ticketstatus: 'Status',
  cf_1086: 'Estatus cambio', cf_1084: 'Estatus fallo', assigned_user_id: 'Asignado a', cf_1113: 'Desarrollador',
  cf_1111: 'Tester', cf_1275: 'Ticket soporte', cf_871: 'Suite', cf_875: 'Solicitante', cf_1191: 'Versión',
  createdtime: 'Creado', modifiedtime: 'Modificado', cf_873: 'Fecha de hoy', cf_1066: 'Asignación caso',
  cf_1068: 'Asignación codificación', cf_1072: 'Promesa envío pruebas', cf_895: 'Primer envío pruebas',
  cf_897: 'Último envío pruebas', cf_899: 'Última respuesta pruebas', cf_1104: 'Entrega', cf_901: 'Liberación',
  cf_903: 'Cierre', cf_1229: 'Promesa entrega corrección', cf_1076: 'Entrega corrección', cf_1078: 'Promesa respuesta',
  cf_1082: 'Respuesta real', cf_753: 'Resolución',
};
const LISTA = Object.keys(CAMPOS).join(',');

// Acciones de la API por controlador: acción → [ruta, { parámetro de mover → parámetro de la API }]
const ACCIONES = {
  Cambio: {
    analizando: ['Analizando', { usuario: 'assignedUserId', fecha: 'asignacionCaso' }],
    codificando: ['Codificando', { usuario: 'assignedUserId', fecha: 'asignacionCodificacion' }],
    pruebas: ['Pruebas', { fecha: 'envioPruebas' }],
    entregado: ['Entregado', { fecha: 'fechaEntrega' }],
    liberado: ['Liberado', { fecha: 'fechaLiberacion' }],
    terminado: ['Terminado', { fecha: 'fechaCierre' }],
    cancelado: ['Cancelado', { fecha: 'fechaCierre' }],
  },
  Fallo: {
    'en-proceso': ['EnProceso', { usuario: 'assignedUserId', fecha: 'asignacionCaso', notificar: 'notificarEmail' }],
    'regresa-pendiente': ['RegresaPendiente', { motivo: 'motivo', notificar: 'notificarEmail' }],
    'promesa-entrega': ['PromesaEntrega', { fecha: 'promesaEntrega' }],
    entregado: ['Entregado', { fecha: 'fechaEntrega' }],
    'promesa-respuesta': ['PromesaRespuesta', { fecha: 'promesaRespuesta' }],
    'regresa-en-proceso': ['RegresaEnProceso', { fecha: 'promesaEntrega' }],
    terminado: ['Terminado', { fecha: 'fechaRespuesta' }],
    cerrado: ['Cerrado', { fecha: 'fechaCierre' }],
    cancelado: ['Cancelado', { fecha: 'fechaCierre' }],
  },
  FalloTesting: {
    codificacion: ['Codificacion', { usuario: 'assignedUserId', fecha: 'asignacionCodificacion', notificar: 'notificarEmail' }],
    'regresa-pendiente': ['RegresaPendiente', { motivo: 'motivo', notificar: 'notificarEmail' }],
    integracion: ['Integracion', { observaciones: 'observaciones', notificar: 'notificarEmail' }],
    pruebas: ['Pruebas', { observaciones: 'observaciones', fecha: 'envioPruebas', notificar: 'notificarEmail' }],
    bugs: ['Bugs', { fecha: 'ultimaRespuestaPruebas' }],
    liberado: ['Liberado', { fecha: 'fechaLiberacion' }],
  },
};
// Estatus de fallo que atiende FalloTesting; el resto, Fallo (soporte)
const ESTATUS_TESTING = ['Codificación pendiente', 'Codificando', 'Corrección de bugs', 'Integración', 'Pruebas'];
const controlador = t => t.cf_867 === 'Cambio' ? 'Cambio' : ESTATUS_TESTING.includes(t.cf_1084) ? 'FalloTesting' : 'Fallo';
const estatus = t => t.cf_867 === 'Cambio' ? t.cf_1086 : t.cf_1084;

// --- Webservice ---
let sesion = null;
async function vt(params, post) {
  const { url } = cfg();
  const r = post ? await fetch(url, { method: 'POST', body: new URLSearchParams(params) })
    : await fetch(`${url}?${new URLSearchParams(params)}`);
  const j = JSON.parse(await r.text());
  if (!j.success) throw new Error(`VTiger ${params.operation}: ${j.error && j.error.message}`);
  return j.result;
}
async function login() {
  if (sesion) return sesion;
  const c = cfg();
  const { token } = await vt({ operation: 'getchallenge', username: c.usuario });
  const r = await vt({ operation: 'login', username: c.usuario, accessKey: crypto.createHash('md5').update(token + c.accessKey).digest('hex') }, true);
  return sesion = r.sessionName;
}
// VTQL sin LIMIT ni punto y coma; regresa todas las filas paginando de 100 en 100
async function query(vtql) {
  const s = await login(), base = vtql.trim().replace(/;$/, ''), filas = [];
  for (let i = 0; ; i += 100) {
    const r = await vt({ operation: 'query', sessionName: s, query: `${base} LIMIT ${i},100;` });
    filas.push(...r);
    if (r.length < 100) return filas;
  }
}
const retrieve = async id => vt({ operation: 'retrieve', sessionName: await login(), id });
const q = v => `'${String(v).replace(/'/g, "\\'")}'`;

// Usuarios de VTiger: id → nombre (y nombre oficial del equipo cuando coincide completo, sin acentos)
let usuarios = null;
const llave = s => E.sinAcentos(s).toLowerCase().replace(/\s+/g, ' ').trim();
function leerUsuarios() {
  return usuarios = usuarios || query('SELECT id,first_name,last_name,user_name FROM Users').then(r => Object.fromEntries(r.map(u => {
    const nombre = `${u.first_name} ${u.last_name}`.trim();
    return [u.id, { id: u.id, nombre, usuario: u.user_name, equipo: E.EQUIPO.find(e => llave(e) === llave(nombre)) || null }];
  })));
}
async function idUsuario(nombre) {
  const of = E.colaborador(nombre), us = Object.values(await leerUsuarios());
  const n = E.sinAcentos(nombre).toLowerCase();
  const u = (of && us.find(x => x.equipo === of)) || us.find(x => E.sinAcentos(x.nombre).toLowerCase() === n || x.usuario === nombre);
  if (!u) throw new Error(`No encontré en VTiger al usuario "${nombre}".`);
  return u;
}

// Caso con nombres legibles; acepta TT##### o id 17x...
async function caso(tt) {
  const r = /^\d+x\d+$/.test(tt) ? [await retrieve(tt)] : await query(`SELECT ${LISTA} FROM HelpDesk WHERE ticket_no=${q(tt.toUpperCase())}`);
  if (!r.length || !r[0]) throw new Error(`No existe el caso ${tt}.`);
  return legible(r[0]);
}
async function legible(t) {
  const us = await leerUsuarios(), o = {};
  for (const k of Object.keys(CAMPOS)) if (t[k] !== undefined) o[k] = t[k];
  const u = us[t.assigned_user_id];
  o.asignado = u ? (u.equipo || u.nombre) : t.assigned_user_id;
  o.estatus = estatus(t);
  return o;
}
const resumen = t => ({ ticket_no: t.ticket_no, titulo: t.ticket_title, tipo: t.cf_867, estatus: t.estatus, ticketstatus: t.ticketstatus, asignado: t.asignado });
const FECHAS = ['cf_1066', 'cf_1068', 'cf_1072', 'cf_895', 'cf_897', 'cf_899', 'cf_1104', 'cf_901', 'cf_903', 'cf_1229', 'cf_1076', 'cf_1078', 'cf_1082'];
// Resumen + soporte, versión y fechas con valor ("Entrega (cf_1104)")
const ficha = t => ({ ...resumen(t), soporte: (t.cf_1275 || '').trim() || null, version: (t.cf_1191 || '').trim() || null,
  fechas: Object.fromEntries(FECHAS.filter(k => t[k]).map(k => [`${CAMPOS[k]} (${k})`, t[k]])) });
async function comentarios(id) {
  const us = await leerUsuarios();
  return (await query(`SELECT commentcontent,assigned_user_id,createdtime FROM ModComments WHERE related_to=${q(id)} ORDER BY createdtime DESC`))
    .map(c => ({ fecha: c.createdtime, autor: (us[c.assigned_user_id] || {}).nombre || c.assigned_user_id, texto: c.commentcontent }));
}
async function detalle(tt) {
  const t = await caso(tt);
  const soporte = t.cf_1275 && t.cf_1275.trim() ? await buscar(t.cf_1275.trim()) : [];
  const definitivos = (await query(`SELECT ${LISTA} FROM HelpDesk WHERE cf_1275=${q(t.ticket_no)}`)).map(x => x.ticket_no);
  // Solo campos con valor, con su nombre: "Entrega (cf_1104)"
  const campos = Object.fromEntries(Object.entries(t).filter(([, v]) => v && String(v).trim()).map(([k, v]) => [CAMPOS[k] ? `${CAMPOS[k]} (${k})` : k, v]));
  return { caso: campos, soporte: soporte.filter(x => x.ticket_no !== t.ticket_no).map(resumen), definitivos, comentarios: await comentarios(t.id) };
}
// Por número, por ticket de soporte o por título
async function buscar(texto) {
  const t = texto.trim();
  const r = /^TT\d+$/i.test(t)
    ? [...await query(`SELECT ${LISTA} FROM HelpDesk WHERE ticket_no=${q(t.toUpperCase())}`), ...await query(`SELECT ${LISTA} FROM HelpDesk WHERE cf_1275=${q(t.toUpperCase())}`)]
    : await query(`SELECT ${LISTA} FROM HelpDesk WHERE ticket_title LIKE ${q(`%${t}%`)} ORDER BY createdtime DESC`);
  return Promise.all(r.map(legible));
}
// Varios casos de una vez: { TT: ficha + definitivos[] }; los que no existen van en faltan
async function casos(lista) {
  const tts = [...new Set(lista.map(x => x.trim().toUpperCase()).filter(x => /^TT\d+$/.test(x)))], out = {};
  for (let i = 0; i < tts.length; i += 50) {
    const en = tts.slice(i, i + 50).map(q).join(',');
    for (const t of await Promise.all((await query(`SELECT ${LISTA} FROM HelpDesk WHERE ticket_no IN(${en})`)).map(legible)))
      out[t.ticket_no] = { ...ficha(t), definitivos: [] };
    for (const t of await query(`SELECT ticket_no,cf_1275 FROM HelpDesk WHERE cf_1275 IN(${en})`))
      if (out[t.cf_1275.trim()]) out[t.cf_1275.trim()].definitivos.push(t.ticket_no);
  }
  return { casos: out, faltan: tts.filter(x => !out[x]) };
}
// Tablero de fallos: PROCESO = Revisión (promesa de entrega), ENTREGADO = Entregado (promesa de respuesta)
async function promesas(nombre) {
  const us = Object.values(await leerUsuarios()).filter(u => u.equipo && (!nombre || u.equipo === E.colaborador(nombre)));
  if (!us.length) throw new Error(`"${nombre}" no es del equipo.`);
  const r = await query(`SELECT ${LISTA} FROM HelpDesk WHERE cf_751='Proyectos' AND cf_1084 IN('Revisión','Entregado') AND ticketstatus!='Closed' AND assigned_user_id IN(${us.map(u => q(u.id)).join(',')}) ORDER BY createdtime ASC`);
  return (await Promise.all(r.map(legible))).filter(t => t.cf_867 !== 'Cambio').map(t => ({
    columna: t.estatus === 'Revisión' ? 'PROCESO' : 'ENTREGADO', caso: t.ticket_no, soporte: (t.cf_1275 || '').trim() || null,
    titulo: t.ticket_title, tipo: t.cf_867, responsable: t.asignado,
    fecha: (t.estatus === 'Revisión' ? t.cf_1229 : t.cf_1078) || null, entrega: t.cf_1076 || null,
    accion: t.estatus === 'Revisión' ? 'promesa-entrega' : 'promesa-respuesta' }));
}
// Relación de fallos atendidos (Proyectos, I-Gas, Fallo/Apoyo a soporte/Piloto, respuesta real en el mes), columnas del reporte de VTiger
async function fallosAtendidos(clave) {
  if (!/^\d{6}$/.test(clave || '')) throw new Error(`Clave inválida "${clave}". Formato: YYYYMM.`);
  const a = +clave.slice(0, 4), m = +clave.slice(4), fin = new Date(a, m, 0).getDate();
  const r = await query(`SELECT ${LISTA},parent_id FROM HelpDesk WHERE cf_751='Proyectos' AND cf_871='I-Gas' AND cf_867 IN('Fallo','Apoyo a soporte','Piloto') AND cf_1082>='${a}-${pad(m)}-01' AND cf_1082<='${a}-${pad(m)}-${fin}' ORDER BY ticket_no ASC`);
  const ids = [...new Set(r.map(t => t.parent_id).filter(Boolean))], cuentas = {};
  for (let i = 0; i < ids.length; i += 50)
    for (const c of await query(`SELECT id,accountname FROM Accounts WHERE id IN(${ids.slice(i, i + 50).map(q).join(',')})`)) cuentas[c.id] = c.accountname;
  const us = await leerUsuarios(), dma = f => f ? f.slice(0, 10).split('-').reverse().join('-') : null;
  return r.map(t => ({
    'Id Caso': t.ticket_no, 'Ticket Soporte': (t.cf_1275 || '').trim(), 'Título': t.ticket_title, 'Cuenta': cuentas[t.parent_id] || '',
    'Tipo': t.cf_867, 'Estado': t.ticketstatus, 'Estatus fallo': t.cf_1084, 'Asignado a': (us[t.assigned_user_id] || {}).nombre || t.assigned_user_id,
    'Fecha de creación': dma(t.createdtime), 'Asignación de caso': dma(t.cf_1066), 'Fecha real de respuesta': dma(t.cf_1082) }));
}
// Casos abiertos de Proyectos asignados al equipo, agrupados por colaborador y estatus
async function tablero(nombre) {
  const us = Object.values(await leerUsuarios()).filter(u => u.equipo && (!nombre || u.equipo === E.colaborador(nombre)));
  if (!us.length) throw new Error(`"${nombre}" no es del equipo.`);
  const r = await query(`SELECT ${LISTA} FROM HelpDesk WHERE cf_751='Proyectos' AND ticketstatus!='Closed' AND assigned_user_id IN(${us.map(u => q(u.id)).join(',')}) ORDER BY createdtime ASC`);
  const out = {};
  for (const t of await Promise.all(r.map(legible))) {
    const p = out[t.asignado] = out[t.asignado] || {};
    (p[`${t.cf_867} - ${t.estatus || 'Sin estatus'}`] = p[`${t.cf_867} - ${t.estatus || 'Sin estatus'}`] || []).push(t);
  }
  return out;
}

// --- Escrituras (API MelissaVirtual) ---
async function tokenApi() {
  const c = cfg();
  let r;
  try { r = await fetch(`${c.api}/Autenticacion?${new URLSearchParams({ usuario: c.usuario, password: c.password })}`); }
  catch { throw new Error(`La API no responde en ${c.api}. Levántala (ver la skill /vtiger).`); }
  const x = await r.text();
  if (r.status !== 200) throw new Error(`Autenticación API ${r.status}: ${x.slice(0, 200)}`);
  const j = JSON.parse(x);
  return typeof j === 'string' ? j : (j.token || j.Token);
}
// Arma la llamada; con confirmar la ejecuta, vuelve a leer el caso y deja registro en LOG
async function mover(tt, accion, opciones = {}, confirmar = false) {
  const t = await caso(tt), ctl = controlador(t), def = ACCIONES[ctl][accion];
  if (!def) throw new Error(`Acción "${accion}" no existe para ${ctl}. Disponibles: ${Object.keys(ACCIONES[ctl]).join(', ')}.`);
  const [ruta, mapa] = def, params = { id: t.id };
  for (const [k, p] of Object.entries(mapa)) {
    let v = opciones[k];
    if (k === 'fecha' && !v) { if (p.startsWith('promesa')) throw new Error(`Falta fecha=AAAA-MM-DD (${p}).`); v = hoy(); }
    if (k === 'usuario') { if (!v) throw new Error('Falta usuario=<colaborador>.'); v = (await idUsuario(v)).id; }
    if (k === 'notificar' && v) v = /^(si|sí|true|1)$/i.test(v) ? 'true' : 'false';
    if (v) params[p] = v;
  }
  const plan = { caso: t.ticket_no, id: t.id, tipo: t.cf_867, antes: { estatus: t.estatus, ticketstatus: t.ticketstatus, asignado: t.asignado },
    llamada: `PUT ${ctl}/${ruta}`, params };
  if (!confirmar) return { ...plan, ejecutado: false };
  const { api } = cfg();
  const r = await fetch(`${api}/${ctl}/${ruta}?${new URLSearchParams(params)}`, { method: 'PUT', headers: { Authorization: await tokenApi() } });
  const txt = (await r.text()).slice(0, 300);
  const d = await caso(t.id);
  const despues = { estatus: d.estatus, ticketstatus: d.ticketstatus, asignado: d.asignado };
  const res = { ...plan, ejecutado: true, http: r.status, respuesta: txt || null, despues };
  try {
    fs.mkdirSync(path.dirname(LOG), { recursive: true });
    fs.appendFileSync(LOG, JSON.stringify({ fecha: new Date().toISOString(), ...res }) + '\n');
  } catch (e) { res.avisoLog = e.message; }
  if (r.status !== 200) throw Object.assign(new Error(`API ${r.status}: ${txt}`), { res });
  return res;
}

module.exports = { CAMPOS, ACCIONES, LOG, query, retrieve, caso, detalle, buscar, casos, promesas, fallosAtendidos, tablero, vista, comentarios, leerUsuarios, idUsuario, mover };

// Encabezado del caso como lo muestra VTiger (Id Caso…Estado | Cuenta…Dias); [etiqueta, valor, liga]
const TRADUCE = { Open: 'Abierto', 'In Progress': 'En progreso', 'Wait For Response': 'Esperando respuesta', Closed: 'Cerrado',
  Minor: 'Menor', Major: 'Mayor', Critical: 'Crítica', Feature: 'Característica', Low: 'Baja', High: 'Alta', Urgent: 'Urgente' };
async function vista(tt) {
  const [t] = await query(`SELECT * FROM HelpDesk WHERE ticket_no=${q(tt.toUpperCase())}`);
  if (!t) throw new Error(`No existe el caso ${tt}.`);
  const nombre = async (id, f) => id ? f(await retrieve(id)) : '';
  const u = (await leerUsuarios())[t.assigned_user_id];
  // VTiger guarda en UTC-7 y muestra en la zona de Jorge (America/Chihuahua)
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/Chihuahua', year: 'numeric', month: '2-digit', day: '2-digit', hour: 'numeric', minute: '2-digit', hour12: true })
    .formatToParts(new Date(t.createdtime.replace(' ', 'T') + '-07:00')).map(x => [x.type, x.value]));
  const tr = v => TRADUCE[v] || v;
  return {
    izquierda: [['Id Caso', t.ticket_no], ['Clase', t.cf_751], ['Titulo', t.ticket_title],
      ['Contacto', await nombre(t.contact_id, c => `${c.firstname} ${c.lastname}`.trim()), true],
      ['Producto', await nombre(t.product_id, x => x.productname)], ['Estado', tr(t.ticketstatus)]],
    derecha: [['Cuenta', await nombre(t.parent_id, a => a.accountname), true], ['Asignado a', u ? u.nombre : t.assigned_user_id, true],
      ['Prioridad', tr(t.ticketpriorities)], ['Severidad', tr(t.ticketseverities)],
      ['Fecha de creación', `${p.day}-${p.month}-${p.year} ${p.hour}:${p.minute} ${p.dayPeriod}`], ['Dias', String(parseInt(t.days) || 0)]],
  };
}

if (require.main === module) {
  (async () => {
    const [cmd, ...a] = process.argv.slice(2);
    const ver = x => console.log(JSON.stringify(x, null, 1));
    if (cmd === 'caso' && a[0]) return ver(await detalle(a[0]));
    if (cmd === 'buscar' && a[0]) return ver(await buscar(a.join(' ')));
    if (cmd === 'casos' && a[0]) return ver(await casos(a.join(' ').split(/[\s,]+/)));
    if (cmd === 'vista' && a[0]) return ver(await vista(a[0]));
    if (cmd === 'promesas') return ver(await promesas(a.join(' ') || null));
    if (cmd === 'fallos' && a[0]) return ver(await fallosAtendidos(a[0]));
    if (cmd === 'tablero') return ver(await tablero(a.join(' ') || null));
    if (cmd === 'query' && a[0]) return ver(await query(a.join(' ')));
    if (cmd === 'mover' && a[1]) {
      const op = Object.fromEntries(a.slice(2).filter(x => x.includes('=')).map(x => [x.slice(0, x.indexOf('=')), x.slice(x.indexOf('=') + 1)]));
      return ver(await mover(a[0], a[1].toLowerCase(), op, a.includes('--confirmar')));
    }
    throw new Error('Uso: node vtiger.js caso|buscar|casos|vista|promesas|fallos|tablero|query|mover ... (ver encabezado de vtiger.js)');
  })().catch(e => { console.error('ERROR:', e.message); if (e.res) console.log(JSON.stringify(e.res, null, 1)); process.exit(1); });
}
