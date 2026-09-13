# MINI INFORME — TELÉFONOS PARA NOTIFICACIONES

- Fecha: 2026-09-09
- Fuente: PostgreSQL producción (`altomamita`, servidor `31.97.99.70`) — SOLO LECTURA
- Alcance: clientes con venta activa que tiene cuotas vencidas impagas (mismo criterio del recordatorio de cuotas vencidas)
- No se modificó producción, no se corrigió ningún teléfono y no se envió ningún mensaje.

Total evaluados (ventas vencidas): 72
Teléfonos válidos: 53
Teléfonos inválidos/sin número: 19
Porcentaje listo: 74% (53/72)

Aclaración a nivel de clientes distintos (un cliente puede tener más de una venta vencida):

- Clientes evaluados: 56
- Con teléfono válido: 43
- Sin teléfono o inválido: 13
- Porcentaje listo: 77% (43/56)

## CLIENTES QUE HAY QUE CORREGIR

### Sin teléfono (VACÍO)

| Cliente | Cédula | Teléfono actual | Problema | Acción |
|---------|--------|-----------------|----------|--------|
| JUANA NUÑEZ CARABALLO | 028-0058828-3 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| LARRY JOSEPH STERINA JR Y ELIZABETH DE LA CRUZ DE STERINA JR | 587971108 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| LARRY JOSEPH STERINA III | 548231755 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| ANA MARIA MARCOS DIODOR | 125420157 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| PABLO MELO ARIAS | 001-1092864-5 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| WILIAN SIERRA GUILLEN | 140-0004361-3 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| VICTOR MANUEL BREA SOTO | 002-0109429-9 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| WILLYS RAMÓN AYALA LUCIANO | 047-0183239-8 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |
| SANTIAGO GUERRERO DE LOS SANTOS | 028-0043636-8 | _(vacío)_ | VACÍO | Solicitar número correcto al cliente |

### Con número pero no válido para WhatsApp dominicano (PREFIJO/FORMATO INVÁLIDO)

| Cliente | Cédula | Teléfono actual | Problema | Acción |
|---------|--------|-----------------|----------|--------|
| DOMINGO MIGUEL NUÑEZ HERNANDEZ | 0314711340 | 3472903214 | PREFIJO/FORMATO INVÁLIDO | Verificar con el cliente; solicitar número dominicano correcto (809/829/849) |
| MILTON URIBER NUÑEZ | 40243542244 | 4417030841 | PREFIJO/FORMATO INVÁLIDO | Verificar con el cliente; solicitar número dominicano correcto (809/829/849) |
| HECTOR RANDAL MEJIA RODRIGUEZ | 40229029927 | 2647729069 | PREFIJO/FORMATO INVÁLIDO | Verificar con el cliente; solicitar número dominicano correcto (809/829/849) |
| LUIS DAVID CASTRO MOTA | 40213567379 | 7812409878 | PREFIJO/FORMATO INVÁLIDO | Verificar con el cliente; solicitar número dominicano correcto (809/829/849) |

Nota: los 4 casos anteriores tienen 10 dígitos, pero el prefijo (347, 441, 264, 781) no es un código dominicano 809/829/849, por lo que no son válidos como WhatsApp dominicano. No se asume cuál es el número real.

## DUPLICADOS A REVISAR

TELÉFONOS DUPLICADOS: 2 (4 clientes involucrados)

| Teléfono | Clientes involucrados | Observación |
|----------|------------------------|-------------|
| 809-753-2829 | ONEIDA MOTA (085-0000291-3) · RAYSA MORAYMA MERCEDES (085-0008235-2) | Mismo número en 2 clientes con ventas vencidas |
| 829-361-5276 | CESAR MAYOBONEX CASTAING SOSA (40236019473) · JULIO ANIBAL CASTAING SOSA (00116477464) | Mismo número y mismo apellido (posible misma persona/familia) |

No se asume que un duplicado sea un error; solo se marca para revisión.

## OBSERVACIONES

- Posible cliente duplicado por cédula: **VICTOR MANUEL BREA SOTO** aparece con la misma cédula `002-0109429-9` en dos fichas: una sin teléfono (1 venta vencida) y otra con teléfono válido `829-321-6910` (1 venta vencida). Revisar si corresponde unificar; no se modificó nada.
- La detección de duplicados se limitó a clientes relevantes para notificaciones con teléfono válido y con el mismo número normalizado (se quitan guiones/paréntesis y prefijo 00).
- Los conteos corresponden a la fotografía de producción al momento de la consulta; si se agregan/corrigen datos después, los números cambian.

## CONCLUSIÓN

Listos para recibir WhatsApp:
- 43 clientes (corresponden a 53 ventas vencidas)

Pendientes de corrección:
- 13 clientes (corresponden a 19 ventas vencidas)
  - 9 sin teléfono
  - 4 con número no dominicano

NO enviar mensajes.
NO modificar producción.
