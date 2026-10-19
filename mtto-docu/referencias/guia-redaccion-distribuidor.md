# Guía de redacción: documento para distribuidores

El Informe de Correcciones / Informe de Cambios lo leen **soporte y distribuidores**. Deben
entender qué falló o qué se mejoró, qué se entrega y cómo comprobarlo, sin leer código.

## Campo por campo

| Campo | Cómo llenarlo |
|---|---|
| Cliente (encabezado) | Nombre del cliente o estación que reportó (sale del título del commit/rama: `TT##### -CLIENTE-PRODUCTO-TÍTULO`). Si el cambio es interno, `IMAGENSOFT`. Confirma el nombre completo con el desarrollador si solo tienes una abreviatura. |
| Versión | Versión del sistema en la que se entrega (`FileVersion` del `.dof` del módulo principal al final de la rama). Si la rama no subió la versión, pregunta cuál va a llevar. |
| Fecha | Fecha del documento, `dd/mm/aaaa` (hoy, salvo que el desarrollador indique otra). |
| Antecedente | **Qué reportó el cliente**, en sus términos: síntoma, pantalla, mensaje de error literal y cómo se reproduce. Sale del ticket VTiger (pídelo si no te lo dan). No es la solución. 1 a 3 oraciones. |
| Descripción General | Causa encontrada (en lenguaje funcional) y **qué se hizo** para resolverla o qué hace ahora el sistema. **1 párrafo** (2 como máximo en cambios de complejidad Alta, 4 a 6 oraciones cada uno). Di qué cambia para el usuario, no cómo lo hace internamente: sin reglas de búsqueda, campos de enlace ni nombres de tablas, salvo que soporte los necesite para configurar. Los casos especiales (qué pasa si falta una configuración) van en Configuraciones Especiales, no aquí. |
| Complejidad | Baja / Media / Alta (criterio abajo). |
| Módulos Afectados | Ejecutables/proyectos que se deben actualizar donde el cliente: PGASMENU, PIVAMENU, PKIOMENU, EstacionFacCts, Tablet Android... Incluye **todos** los que recompilan una unidad compartida modificada, no solo el principal. Máximo 7 renglones; si hay más, el 7.º los agrupa. |
| Bases de Datos Afectadas | Solo las que requieren script o cuya estructura/datos cambian (ver `mapa-bases-datos.md`). |
| ID VTiger | `TT#####`. |
| Autor | Desarrollador(es) según los commits (nombre con acentos correctos). |
| Configuraciones Especiales | Lo que soporte debe hacer al instalar, como **pasos cortos en orden**, un párrafo por paso: scripts SQL (se adjuntan como icono; di en qué BD y en una frase qué hacen), variables/config nuevas con su valor, reinicio de servicios, reemplazo de librerías/NuGet, licencias, orden de actualización. Sentencias SQL literales solo si no van en un script adjunto. Si no hay nada, déjalo vacío. |
| Detalle | Una sección por **opción de menú** afectada: ruta `Sistema >> Menú >> Opción` y pasos en primera persona del plural ("Seleccionamos…", "Presionamos…"), cada uno con su `[CAPTURA: qué debe verse]`. **2 a 4 pasos por opción** (hasta 5 en un proceso nuevo), una o dos oraciones cada uno. Una captura por paso. Termina con el resultado esperado que demuestra la corrección. Solo las opciones donde el usuario ve el cambio; si dos opciones abren la misma pantalla, documenta una y menciona la otra en una línea. |

## Criterio de complejidad

- **Baja**: 1 a 3 unidades, sin cambio de BD, lógica acotada a una pantalla o reporte.
- **Media**: varias unidades o varios módulos, o unidad compartida (DataModule/Libs), o cambio de BD simple (un campo).
- **Alta**: cambio de BD con migración de datos, cálculos fiscales/contables/volumétricos, cambio en servicios/comunicación con dispensarios o impacto en varios repos y productos.

## Reglas

- Español formal, claro, sin jerga de código (no pegues fragmentos de Pascal ni nombres de variables internas).
- No culpes a personas ni hables de "error del programador". Describe el comportamiento.
- **No incluyas datos personales o fiscales** de clientes finales (RFC, correos, teléfonos, nombres de personas). Los números de cliente o de ticket de venta solo si son necesarios para reproducir.
- No inventes: si algo no está en el código ni en el ticket, pregunta o déjalo fuera.
- No prometas comportamiento que el código no hace.
- Concreto: cada oración debe decir algo que soporte o el distribuidor usará. Evita repetir en el Detalle lo que ya dice la Descripción General.
- Ortografía cuidada (acentos, mayúsculas de nombres de sistema: iGas Administrador, iGas Facturación, Kiosco, Tablet).
