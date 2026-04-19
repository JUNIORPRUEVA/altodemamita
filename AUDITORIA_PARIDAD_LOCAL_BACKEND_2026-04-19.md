# Auditoria De Paridad Local Vs Backend

Fecha: 2026-04-19

## Resultado Ejecutivo

La consistencia entre la app local y el backend no es completa.

Estado general:

| Area | Estado | Observacion |
| --- | --- | --- |
| Clientes | Parcial | Hay CRUD y sync en ambos lados, pero el esquema no es equivalente. |
| Solares / Productos | Parcial | La nube guarda solares como `products` adaptados, no como tabla nativa equivalente. |
| Vendedores | Parcial | La sync existe, pero el backend administrativo solo expone lectura. |
| Ventas | Parcial | La sync conserva datos, pero varias columnas locales viven en `syncPayload`. |
| Cuotas | Parcial | La sync recompone datos, pero no todos viven como columnas nativas en Prisma. |
| Pagos | Parcial | La sync funciona, pero algunos campos locales no son nativos en backend. |
| Usuarios / Seguridad | Inconsistente | Local y backend usan modelos distintos y no hay paridad 1:1. |
| Empresa / Configuracion | Inconsistente | Hay equivalencias parciales, sin sync ni CRUD unificado completo. |
| Backup / Impresoras / Preferencias | Solo local | No existe modelo equivalente en backend. |
| Infraestructura de sync | Inconsistente | SQLite marca tablas como sincronizables que realmente no tienen repositorio registrado. |

Conclusión:

1. El nucleo comercial local si tiene presencia backend, pero no con paridad estricta de tablas.
2. La consistencia actual es funcional para una parte del negocio, no estructuralmente completa.
3. Si el objetivo es que "todo lo que se presenta en local exista en backend" entonces todavia faltan varias tablas, campos y endpoints.

## Evidencia Base

### Tablas principales en SQLite local

Definidas en `lib/core/database/database_schema.dart`:

- `clientes`
- `usuarios`
- `vendedores`
- `solares`
- `ventas`
- `cuotas`
- `pagos`
- `configuracion`
- `informacion_empresa`
- `permisos`
- `configuracion_impresoras`
- `parametros_financieros`
- `informacion_backups`
- `preferencias_backup`
- `sesiones_auth`
- `sync_queue`
- `conflict_logs`

### Modelos principales en Prisma backend

Definidos en `backend/prisma/schema.prisma`:

- `User`
- `Role`
- `Permission`
- `UserRole`
- `RolePermission`
- `CompanyProfile`
- `Client`
- `Product`
- `Seller`
- `Sale`
- `Installment`
- `Payment`

### Modulos REST backend encontrados

En `backend/src/modules` existen:

- `auth`
- `clients`
- `installments`
- `payments`
- `products`
- `reports`
- `sales`
- `sellers`
- `sync`
- `system`

### Modulos funcionales locales encontrados

En `lib/features` existen:

- `auth`
- `backup`
- `clients`
- `dashboard`
- `global_search`
- `installments`
- `lots`
- `payments`
- `sales`
- `settings`

## Matriz De Paridad Por Tabla

### 1. Clientes

Estado: Parcial.

Local:

- Tabla `clientes` con `nombre`, `cedula`, `telefono`, `direccion`, fechas.
- Repositorio con CRUD y sync real.

Backend:

- Modelo `Client` con `firstName`, `lastName`, `documentId`, `email`, `phone`, `address`, `notes`, `code`.
- CRUD REST completo en `/clients`.
- Persistencia por sync en `SyncService`.

Brechas:

1. Local usa un solo campo `nombre`, backend separa `firstName` y `lastName`.
2. Backend tiene `email`, `notes` y `code`; local no los maneja como columnas principales.
3. No hay paridad estricta de esquema, solo compatibilidad operativa.

Veredicto: compatible para operar, no consistente 1:1.

### 2. Solares / Productos

Estado: Parcial.

Local:

- Tabla `solares` con `manzana_numero`, `solar_numero`, `metros_cuadrados`, `precio_por_metro`, `estado`.
- CRUD local completo en `LotRepository`.

Backend:

- Modelo `Product` generico con `code`, `name`, `description`, `price`, `financingPrice`, `stock`, `isActive`.
- CRUD REST completo en `/products`.
- La sync convierte un solar local en un `product` y guarda el detalle real en `syncPayload`.

Brechas:

1. No existe tabla backend nativa `lots` o `solares`.
2. La semantica del dominio esta adaptada, no alineada.
3. Parte del esquema real vive en `syncPayload`, no en columnas propias.

Veredicto: no hay paridad de tabla; hay adaptacion de dominio.

### 3. Vendedores

Estado: Parcial.

Local:

- Tabla `vendedores` con CRUD local y sync real.

Backend:

- Modelo `Seller` con `name`, `documentId`, `phone`.
- El modulo REST `/sellers` solo expone `GET` y `GET :id`.
- La escritura entra por sync, no por CRUD administrativo completo.

Brechas:

1. No hay `POST`, `PATCH` ni `DELETE` en el backend para vendedores.
2. La PWA o cualquier cliente HTTP no tienen paridad de escritura con la app local.

Veredicto: paridad de datos por sync, pero no paridad funcional completa.

### 4. Ventas

Estado: Parcial.

Local:

- Tabla `ventas` rica en campos de negocio:
  - `inicial_porcentaje`
  - `inicial_monto`
  - `monto_inicial_requerido`
  - `monto_inicial_pagado`
  - `monto_inicial_pendiente`
  - `monto_apartado_minimo`
  - `fecha_limite_inicial`
  - `fecha_activacion`
  - `saldo_financiado`
  - `saldo_pendiente`
  - `interes_mensual`
  - `cantidad_cuotas`
  - `estado`

Backend:

- Modelo `Sale` con `principalAmount`, `financedAmount`, `downPayment`, `interestRate`, `totalAmount`, `termMonths`, `paidAmount`, `outstandingBalance`, `status`.
- Varias propiedades del desktop se preservan en `syncPayload` durante upload/download.

Brechas:

1. No existe correspondencia nativa columna por columna.
2. Estados locales y estados backend no son iguales y se traducen.
3. Campos clave del ciclo de inicial/apartado/activacion no viven como columnas backend de primer nivel.

Veredicto: el backend puede transportar la venta local, pero no la modela con el mismo detalle estructural.

### 5. Cuotas

Estado: Parcial.

Local:

- Tabla `cuotas` con `saldo_inicial`, `capital_cuota`, `interes_cuota`, `monto_cuota`, `monto_pagado`, `capital_pagado`, `interes_pagado`, `saldo_final`, `estado`.

Backend:

- Modelo `Installment` con `amount`, `principalAmount`, `interestAmount`, `paidAmount`, `status`.
- Valores como `opening_balance`, `paid_principal_amount`, `paid_interest_amount`, `ending_balance` se reconstruyen desde `syncPayload` al descargar.

Brechas:

1. No todas las columnas locales existen como campos nativos en Prisma.
2. Parte del detalle financiero depende del payload sincronizado, no del esquema principal.

Veredicto: paridad funcional parcial, no paridad estricta de tabla.

### 6. Pagos

Estado: Parcial.

Local:

- Tabla `pagos` con `venta_id`, `cliente_id`, `usuario_id`, `cuota_id`, `fecha_pago`, `monto_pagado`, `metodo_pago`, `tipo_pago`, `referencia`, `ano_a_pagar`.

Backend:

- Modelo `Payment` con `saleId`, `installmentId`, `paymentDate`, `amount`, `principalAmount`, `interestAmount`, `method`, `reference`, `notes`.
- `payment_type`, `year_to_pay` y parte de la semantica local se guardan en `syncPayload`.

Brechas:

1. `cliente_id` y `usuario_id` no existen como columnas directas en `Payment` del backend.
2. `tipo_pago` y `ano_a_pagar` no son columnas nativas backend.

Veredicto: hay compatibilidad de sync, no equivalencia completa.

### 7. Usuarios

Estado: Inconsistente.

Local:

- Tabla `usuarios` simple.
- Usa `rol` limitado a `admin` o `vendedor`.
- La administracion local en settings opera directo sobre SQLite.

Backend:

- `User`, `Role`, `Permission`, `UserRole`, `RolePermission`.
- Auth JWT, usernames, emails, roles multiples, permisos normalizados.
- CRUD REST completo en `/auth/users`, `/auth/roles`, `/auth/permissions`.

Brechas:

1. Son modelos de seguridad distintos.
2. No existe sync real de `usuarios` local hacia backend.
3. La tabla local sigue siendo un modelo legado y simplificado.

Veredicto: no hay paridad estructural ni funcional total.

### 8. Permisos

Estado: Inconsistente.

Local:

- Tabla `permisos` por `usuario_id`, `modulo`, `acciones` JSON.

Backend:

- Permisos normalizados con roles y asociaciones many-to-many.

Brechas:

1. El modelo local es plano por usuario-modulo.
2. El backend usa roles, permisos y pivotes.
3. No existe un traductor oficial entre ambos modelos.

Veredicto: conceptos parecidos, implementacion distinta.

### 9. Informacion De Empresa

Estado: Parcial.

Local:

- Tabla `informacion_empresa` con nombre, telefono, direccion, logo.

Backend:

- Modelo `CompanyProfile` con nombre, telefono, direccion, logo.
- Inicializacion via `/system/setup`.

Brechas:

1. Existe equivalencia conceptual, pero no hay sync desktop equivalente para esta tabla.
2. No hay CRUD unificado entre app local y backend como con clientes o ventas.

Veredicto: esquema parecido, integracion incompleta.

### 10. Parametros Financieros

Estado: Solo local.

Local:

- Tabla `parametros_financieros`.

Backend:

- No existe tabla Prisma equivalente.

Veredicto: falta backend.

### 11. Configuracion De Impresoras

Estado: Solo local.

Local:

- Tabla `configuracion_impresoras`.

Backend:

- No existe tabla equivalente.

Veredicto: falta backend.

### 12. Backup Info / Backup Preferences

Estado: Solo local.

Local:

- `informacion_backups`
- `preferencias_backup`

Backend:

- No existen modelos Prisma equivalentes.

Veredicto: falta backend.

### 13. Sesiones Auth Locales

Estado: Solo local.

Local:

- `sesiones_auth`.

Backend:

- No existe tabla equivalente de sesiones del desktop.

Veredicto: es infraestructura local, no backend.

### 14. Sync Queue / Conflict Logs

Estado: Solo local.

Local:

- `sync_queue`
- `conflict_logs`

Backend:

- No son tablas espejo del negocio; son infraestructura cliente.

Veredicto: no deben contarse como paridad de negocio, pero si como infraestructura local sin equivalente remoto.

## Hallazgos Críticos

### Hallazgo 1. `syncEnabledTables` no implica cobertura real de sync

`DatabaseSchema.syncEnabledTables` incluye:

- `usuarios`
- `informacion_empresa`
- `permisos`
- `configuracion_impresoras`
- `parametros_financieros`
- `informacion_backups`
- `preferencias_backup`
- `sesiones_auth`

Pero los repositorios realmente registrados en `SyncService` son:

- `clients`
- `products`
- `sellers`
- `sales`
- `installments`
- `payments`

Impacto:

1. El esquema local sugiere mas tablas sincronizadas de las que realmente se sincronizan.
2. La consistencia esperada por el negocio puede parecer resuelta cuando no lo esta.

### Hallazgo 2. El backend mantiene varias entidades locales usando `syncPayload`

Esto ocurre en:

- `products`
- `sales`
- `installments`
- `payments`

Impacto:

1. La nube conserva datos del desktop, pero no con normalizacion completa.
2. Es mas fragil para reporting, validaciones, integraciones y PWA avanzada.

### Hallazgo 3. Vendedores no tienen CRUD backend completo

El backend solo expone lectura en `/sellers`.

Impacto:

1. La nube no ofrece la misma capacidad operativa de escritura que la app local.
2. La gestion completa depende del sync o de procesos internos.

### Hallazgo 4. Seguridad local y seguridad cloud no comparten el mismo modelo

Impacto:

1. Usuarios y permisos no son consistentes entre ambos mundos.
2. La administracion local de usuarios no refleja la arquitectura real del backend.

## Qué Si Está Cubierto Hoy

Con cobertura funcional razonable:

1. Clientes
2. Solares, pero adaptados como `products`
3. Vendedores por sync
4. Ventas por sync
5. Cuotas por sync
6. Pagos por sync

Con cobertura incompleta o no equivalente:

1. Usuarios
2. Permisos
3. Empresa / configuracion general
4. Parametros financieros
5. Impresoras
6. Backup
7. Sesiones locales

## Prioridad De Corrección Recomendada

### Prioridad 1. Definir modelo canonico unico de negocio

Decidir si la nube va a modelar nativamente:

- solares
- ventas con inicial/apartado/activacion
- cuotas con descomposicion completa
- pagos con tipo y contexto local

Si la respuesta es si, hay que crear columnas reales en Prisma y dejar de depender de `syncPayload` para el nucleo.

### Prioridad 2. Unificar usuarios y permisos

Opciones:

1. Migrar la administracion local para que consuma el modelo cloud.
2. Crear una capa de traduccion formal entre el modelo local legado y el modelo backend.

Sin esto no hay consistencia total en seguridad.

### Prioridad 3. Dar cobertura backend a configuracion operativa

Crear modelos y endpoints para:

1. parametros financieros
2. informacion de empresa
3. si aplica, configuracion de impresoras y politicas de backup

### Prioridad 4. Completar CRUD backend de vendedores

Agregar:

1. `POST /sellers`
2. `PATCH /sellers/:id`
3. `DELETE /sellers/:id`

### Prioridad 5. Corregir la falsa señal de sync habilitado

Hay que alinear una de estas dos cosas:

1. o registrar repositorios reales para todas las tablas marcadas en `syncEnabledTables`
2. o sacar de `syncEnabledTables` lo que hoy no tiene sync real

## Veredicto Final

No, hoy no se puede afirmar que "todo lo que se presenta en local la app completa se muestra en el backend".

Lo correcto hoy es:

1. El backend ya cubre una parte importante del negocio principal.
2. La cobertura actual es parcial y en varios casos depende de adaptaciones y `syncPayload`.
3. La consistencia completa en todas las tablas todavia no existe.

## Siguiente Paso Sugerido

Si se quiere cerrar esta brecha de verdad, el orden correcto es:

1. definir el esquema canonico final
2. migrar Prisma para reflejar ese esquema
3. exponer CRUD y sync consistentes
4. actualizar la app local para dejar de depender de modelos legacy donde ya no correspondan
