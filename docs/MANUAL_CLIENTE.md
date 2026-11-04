# Manual del Usuario — Sistema Solares

**Guía rápida de uso diario**
Versión del sistema: 1.0.0 · Instalador `SistemaSolares_Setup_1.0.0_19`

Este manual explica paso a paso cómo hacer cada operación del sistema. Está escrito para
usarse en el día a día: busque la tarea que necesita y siga los pasos.

---

## 1. Antes de empezar

### 1.1 Iniciar sesión
1. Abra el sistema con el acceso directo **Sistema Solares** del escritorio o menú de inicio.
2. Escriba su **usuario** y **contraseña**.
3. Pulse **Entrar**.

Si aparece un mensaje de **sesión vencida**, vuelva a iniciar sesión. Es normal cuando pasan
varias horas sin usar el sistema.

### 1.2 Tipos de usuario
- **Administrador**: puede hacer todo, incluido **eliminar la mora** de las cuotas.
- **Vendedor**: solo las acciones que le haya habilitado el administrador.

Si un botón que necesita no aparece, casi siempre es porque su usuario no tiene el permiso.
Pida al administrador que lo habilite en **Configuración → Usuarios y permisos**.

### 1.3 Menú principal
Arriba o a la izquierda encontrará los módulos:

- **Resumen**: indicadores del negocio.
- **Ventas**: crear, buscar, editar, cancelar e imprimir.
- **Buscador**: búsqueda global de clientes, solares, ventas y pagos.
- **Clientes**
- **Solares**
- **Pagos**: registro de pagos, recibos, historial y mora.
- **Cuotas**: seguimiento de amortización.
- **Vendedores**
- **Configuración**

---

## 2. Clientes

### 2.1 Registrar un cliente
1. Entre a **Clientes**.
2. Pulse **Nuevo cliente**.
3. Complete nombre, cédula, teléfono y dirección.
4. Pulse **Guardar**.

> También puede crear un cliente sin salir de una venta: en el formulario de venta, junto al
> campo **Seleccionar cliente**, use el botón de agregar (**+**).

### 2.2 Buscar un cliente
Use la barra de búsqueda del módulo. Puede escribir **nombre, teléfono o cédula**.

### 2.3 Editar un cliente
1. Localice el cliente en la lista.
2. Pulse el botón **Editar** de la fila (o el menú **⋮ → Editar**).
3. Corrija los datos y pulse **Guardar**.
4. Verá el mensaje **"Cliente actualizado correctamente."**

---

## 3. Solares

### 3.1 Crear un solar
1. Entre a **Solares**.
2. Pulse **Nuevo solar**.
3. Complete el código, la manzana, las medidas y el precio.
4. Pulse **Guardar**.

### 3.2 Editar un solar
1. Localice el solar.
2. Pulse **Editar** en la fila.
3. Cambie lo necesario y guarde.
4. Verá **"Solar actualizado correctamente."**

### 3.3 Ver el detalle de un solar
Pulse sobre el solar para ver su ficha (**Detalles del Solar**). Desde ahí puede **Editar** o
**Cerrar**.

> El estado del solar se actualiza según la venta asociada. No lo cambie a mano para
> "liberar" un solar: si necesita liberarlo, cancele o edite la venta correspondiente.

---

## 4. Ventas

### 4.1 Crear una venta
1. Entre a **Ventas** y pulse **Crear venta**.
2. Complete, en este orden:
   - **Seleccionar cliente**
   - **Seleccionar vendedor**
   - **Seleccionar solar**
   - **Fecha de venta**
   - **Precio total**
   - **Inicial %** (porcentaje de inicial)
   - **Interés %** (interés mensual)
   - **Método del primer pago**
   - **Fecha límite**
   - **Número de cuotas**
3. Revise el resumen (**Financiada** o **Al contado**).
4. Pulse **Guardar**.

Si el botón de guardar no responde, el sistema le pedirá **seleccionar el cliente y el solar**:
falta uno de esos dos datos obligatorios.

### 4.2 Ver el detalle de una venta
Pulse sobre la venta en la lista. La ficha muestra:

- **Valor de la venta**
- **Cuota mensual estimada**
- **Balance pendiente**
- **Tiempo por cobrar**
- **Detalle de cuotas** (botón)
- **Historial de pagos** (botón)
- Métricas de **Capital**, **Interés** y **Total** (proyectado y pagado a la fecha)

### 4.3 Editar una venta
**Es la operación para corregir cualquier dato de una venta ya registrada.**

1. Abra la venta (desde la lista o desde su detalle).
2. Pulse **Editar**:
   - En el detalle: botón **Editar** en la barra inferior.
   - En la lista: menú **⋮ → Editar** de la fila.
3. Se abre el mismo formulario de la venta, ya cargado con los datos actuales.
4. Cambie lo que necesite: **cliente, vendedor, solar, fechas, precio, inicial, interés o
   número de cuotas**.
5. Pulse **Guardar cambios**.

**Qué hace el sistema al guardar:**

- Recalcula el **balance pendiente** restando lo que el cliente ya pagó.
- **No borra ni modifica los pagos** ya registrados.
- Genera de nuevo la agenda de **cuotas pendientes** con el nuevo saldo.
- Guarda el cambio en la **Auditoría** de la venta.

> Regla de oro: aunque la venta tenga pagos, **se puede editar**. El dinero cobrado se respeta
> siempre; solo se recalcula lo que falta por cobrar.

### 4.4 Cambiar el solar de una venta
Se hace en la misma edición:

1. Abra la venta y pulse **Editar**.
2. En **Seleccionar solar**, escoja el nuevo solar.
3. Pulse **Guardar cambios**.

El solar anterior queda libre y el nuevo queda asociado a la venta. No existe un botón aparte
de "Cambiar solar": todo se hace desde **Editar**.

### 4.5 Cambiar el cliente de una venta
Igual que el solar: **Editar → Seleccionar cliente → Guardar cambios**.

### 4.6 Cancelar una venta
1. Abra el detalle de la venta.
2. Pulse **Cancelar venta**.
3. Escriba el **Motivo de la corrección** (mínimo 5 caracteres).
4. Confirme con el botón **Cancelar venta**.

La venta **no se borra**: queda marcada como cancelada y conserva todo su historial. El motivo
queda registrado en la auditoría.

### 4.7 Restaurar una venta cancelada
1. Abra el detalle de la venta cancelada.
2. Pulse **Restaurar**.
3. Escriba el motivo y confirme con **Restaurar venta**.

### 4.8 Ver la auditoría de una venta
1. Abra el detalle de la venta.
2. Pulse **Auditoría**.
3. Verá cada cambio con su **fecha**, la **acción** realizada y el **motivo** escrito.

### 4.9 Imprimir documentos de la venta
1. Abra el detalle de la venta.
2. Pulse el botón de **imprimir**.
3. Elija el documento en **Imprimir documento**.
4. Pulse **Imprimir** o **Ver PDF**.

### 4.10 Eliminar una venta (solo casos excepcionales)
Menú **⋮ → Eliminar** en la lista de ventas.

> **Advertencia:** eliminar borra del sistema la venta **y todo lo relacionado**: cuotas, pagos
> e iniciales asociados. **No se puede deshacer.** Si solo quiere anular la venta, use
> **Cancelar venta**, que conserva el historial.

---

## 5. Cuotas

### 5.1 Ver las cuotas de una venta
Dentro del detalle de la venta pulse **Detalle de cuotas**. Verá número, vencimiento, capital,
interés, total y estado.

También puede verlas en el módulo **Cuotas**, que muestra el seguimiento de amortización y la
interpretación de cada estado.

### 5.2 Estados de una cuota
- **Pendiente futura**: todavía no vence.
- **Vencida**: pasó la fecha límite sin pago completo.
- **Parcial**: se pagó una parte.
- **Pagada**: saldada.

En **Pagos** puede filtrar por cada uno de estos estados.

---

## 6. Pagos

### 6.1 Registrar un pago
1. Entre a **Pagos**.
2. Busque la venta por **nombre, teléfono, cédula o número de solar**.
3. Seleccione la venta y pulse **Registrar pago**.
4. En **Registrar pago**, elija la cuota o el tipo de pago:
   - una cuota específica,
   - todas las cuotas vencidas,
   - cuotas adelantadas.
5. Revise el desglose (**Capital**, **Interés**, **Mora**).
6. Elija el **método de pago**.
7. Confirme.

Al terminar se muestra el **recibo**, que puede imprimir.

> Si paga el inicial de una venta en apartado, el formulario se titula **Pagar apartado del
> inicial** o **Pagar completivo del inicial**.

### 6.2 Qué es la mora
Es el cargo adicional por pagar después de la fecha límite de una cuota. En el formulario verá:

- **Mora cobrable**: monto calculado por el servidor (el que se cobra).
- **Mora calculada**: monto estimado cuando todavía no se consultó al servidor.
- Cantidad de **días de mora**.
- **Mora condonada**: monto que ya fue eliminado y por lo tanto **no se cobra**.

### 6.3 Eliminar la mora de UNA cuota (solo Administrador)
**Esta es la forma de quitar la mora de una cuota concreta.**

1. Entre a **Pagos** y seleccione la venta.
2. Pulse **Registrar pago**.
3. En la lista de cuotas vencidas, cada cuota con mora muestra el botón **Eliminar mora**.
4. Pulse **Eliminar mora**.
5. Aparece el mensaje de confirmación:
   **"¿Está seguro de que desea eliminar la mora de la cuota N?"**
6. Pulse **Sí, eliminar mora**.

Resultado: el mensaje **"Mora de la cuota eliminada."** confirma la operación. El total a pagar
de esa cuota baja inmediatamente y la mora no se vuelve a cobrar.

**Cuándo NO aparece el botón:**
- Su usuario no es **Administrador**.
- La cuota no tiene mora pendiente de cobro.
- La cuota ya está pagada.

**Importante:** la mora **ya cobrada** en pagos anteriores no se modifica. Solo se elimina la
mora **pendiente**. La mora que se genere **después** se calcula de nuevo.

### 6.4 Condonar la mora de TODA la venta (solo Administrador)
Útil para un acuerdo comercial que perdona toda la mora acumulada.

1. Entre a **Pagos** y seleccione la venta.
2. En la sección **Historial** pulse **Ver pagos**.
3. Abajo a la derecha pulse **Condonar mora**.
4. Revise el resumen que muestra el sistema:
   - **Mora acumulada (bruta)**
   - **Mora ya cobrada**
   - **Mora condonada vigente**
   - **Mora exigible actual**
5. Elija una de las dos opciones:
   - Dejar todo como está y pulsar **Condonar mora** (perdona toda la mora exigible).
   - Marcar **"Condonar solo una parte de la mora"** y escribir el **Monto a condonar**.
6. Escriba el **Motivo de la condonación** (mínimo 5 caracteres, por ejemplo: *acuerdo
   comercial con el cliente*).
7. Confirme con **Condonar mora**.

El sistema mostrará el **"Exigible después de condonar"** antes de confirmar, para que no haya
sorpresas.

### 6.5 Ver el historial de pagos de una venta
- **Desde el detalle de la venta:** botón **Historial de pagos**.
- **Desde Pagos:** sección **Historial** → **Ver pagos** (abre la pantalla completa con filtros
  y totales de **Total pagado** y **Saldo restante**).

Si una venta no tiene pagos, la pantalla lo indica: **"Esta venta no tiene pagos registrados."**

### 6.6 Anular un pago
Un pago anulado **no se borra**: se conserva como historial y deja de contar en los totales. Si
necesita anular, hágalo desde el historial de pagos de la venta.

---

## 7. Vendedores

- Para registrar un vendedor: en el formulario de venta, junto a **Seleccionar vendedor**, use
  el botón de agregar (**+**).
- Para editarlo: en la misma ventana, pulse el botón de editar del vendedor y guarde. Verá
  **"Vendedor actualizado correctamente."**

---

## 8. Configuración

Desde **Configuración** el administrador puede ajustar:

- **Información de la empresa** (nombre, logo, datos de contacto).
- **Impresoras**.
- **Usuarios y permisos**.
- **Parámetros financieros** (interés por defecto, porcentaje de inicial).
- **Respaldo** de la información.

### 8.1 Dar permiso a un usuario
1. **Configuración → Usuarios y permisos**.
2. Seleccione el usuario.
3. Marque los permisos por módulo (**Ver**, **Crear**, **Editar**, **Eliminar** según el caso).
4. Guarde.

> El botón **Eliminar mora** y la opción **Condonar mora** son exclusivos del rol
> **Administrador**, aunque el usuario tenga permisos de edición en Pagos.

---

## 9. Preguntas frecuentes

**No veo el botón Editar en la venta.**
Su usuario no tiene permiso para editar ventas. Pida al administrador que se lo habilite.

**No aparece el botón Eliminar mora.**
Solo lo ve el **Administrador**, y solo en cuotas que tengan mora pendiente de cobro.

**Eliminé la mora y quiero cobrarla de nuevo.**
No es posible: la condonación queda registrada. Si fue un error, anótelo y consulte con el
administrador; el sistema guarda el motivo del cambio.

**La venta ya tenía pagos y la edité: ¿se perdieron los pagos?**
No. Los pagos se conservan siempre. El sistema recalcula el saldo restando lo ya pagado.

**Modifiqué el precio de una venta y el saldo cambió mucho.**
Es lo esperado: el nuevo saldo es el nuevo precio **menos** lo que el cliente ya pagó. Revise
el **Balance pendiente** en el detalle antes de continuar.

**Al guardar una venta me dice que seleccione el cliente y el solar.**
Falta uno de los dos. Búsquelo en la lista; si el cliente no existe, créelo con el botón **+**.

**Aparece "La confirmación de la venta no coincide".**
La venta cambió en otro equipo. Cierre la venta, vuelva a abrirla y repita la operación.

**El sistema dice "sesión vencida".**
Vuelva a iniciar sesión. Si persiste, revise la conexión a internet.

**La lista se queda cargando mucho tiempo.**
Espere unos segundos: el sistema está sincronizando con la nube. Si pasa de un minuto, cierre y
vuelva a abrir el sistema una sola vez y avise a soporte indicando la hora exacta.

**No hay internet. ¿Puedo trabajar?**
El sistema sigue mostrando la información guardada y registra las operaciones; cuando vuelva la
conexión se envían al servidor.

---

## 10. Reglas de oro

1. **Nunca registre dos veces el mismo pago.** Si duda, revise el **Historial de pagos** primero.
2. **Para corregir una venta, use Editar.** No borre la venta: perdería cuotas y pagos.
3. **Para anular, use Cancelar venta.** Conserva el historial; Eliminar no.
4. **Siempre escriba el motivo** en cancelaciones y condonaciones: queda en la auditoría.
5. **La mora condonada no se cobra después.** Elimínela solo cuando corresponda.
6. **Todo cambio queda registrado** con usuario, fecha y motivo. Revise la **Auditoría** ante
   cualquier duda.

---

## 11. Soporte

Si algo no funciona como se describe aquí:

1. Anote **qué estaba haciendo** y la **hora exacta**.
2. Tome una **captura de pantalla** del mensaje.
3. **No borre datos ni reinstale** el sistema.
4. Envíe la información al administrador o a soporte técnico.

Los registros técnicos del sistema están en:

```
%LOCALAPPDATA%\SistemaSolares\logs
```

---

*Manual del Usuario — Sistema Solares. Documento de uso interno del cliente.*
