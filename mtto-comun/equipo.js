// Equipo de Mantenimiento y canal de Slack: única fuente para todas las skills (datos en equipo.json).
const fs = require('fs');
const path = require('path');

const DATOS = JSON.parse(fs.readFileSync(path.join(__dirname, 'equipo.json'), 'utf8').replace(/^﻿/, ''));
const EQUIPO = DATOS.equipo.map(p => p.nombre);          // nombres oficiales, en el orden de los reportes
const CANAL = DATOS.canal;                               // { nombre, id }
const JEFE = DATOS.jefe;
const sinAcentos = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');

// "Saulo Lopez", "susana", "Gamez" → nombre oficial (null si no es del equipo)
function colaborador(nombre) {
  const n = sinAcentos(nombre).toLowerCase();
  if (!n.trim()) return null;
  return EQUIPO.find(e => sinAcentos(e).toLowerCase().split(' ').some(p => p.length > 3 && n.includes(p))) || null;
}
// Ficha completa (corto, slack, slackId, correo, colorHoja) a partir de cualquier forma del nombre
const ficha = nombre => DATOS.equipo.find(p => p.nombre === colaborador(nombre)) || null;
// Color de la hoja quincenal por nombre corto (incluye al jefe)
const COLORES_HOJA = Object.fromEntries([...DATOS.equipo, JEFE].map(p => [p.corto, p.colorHoja]));

module.exports = { DATOS, EQUIPO, CANAL, JEFE, COLORES_HOJA, sinAcentos, colaborador, ficha };
