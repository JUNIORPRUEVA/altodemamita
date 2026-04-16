# Guía de Prueba - Recibo de Pago Dinámico

## Checklist de Validación Técnica

### Fase 1: Compilación y Ejecución

- [ ] Ejecutar `flutter pub get` sin errores
- [ ] Ejecutar `flutter analyze` sin errores fatales
- [ ] Ejecutar aplicación: `flutter run -d windows`
- [ ] Navegar a módulo de "Pagos" sin crashes

### Fase 2: Verificación de Datos

#### 2.1 Datos de Empresa Dinámicos
- [ ] Ir a **Configuración > Información de Empresa**
- [ ] Configurar/verificar:
  - [ ] Nombre de empresa (ej. "Sistema Solares RD")
  - [ ] Teléfono (ej. "(829) 531-9442")
  - [ ] Dirección
  - [ ] Logo (si aplica)
- [ ] Volver a Pagos y registrar un pago
- [ ] Verificar que el recibo muestre los datos correctos

#### 2.2 Datos de Cliente
- [ ] En Pagos, seleccionar una venta activa
- [ ] En el recibo, verificar:
  - [ ] Nombre del cliente coincide con la BD
  - [ ] Cédula del cliente es correcta
  - [ ] No hay datos hardcodeados

#### 2.3 Datos de Solar
- [ ] Verificar código del solar (Manzana-Solar)
- [ ] Verificar saldo pendiente actualizado
- [ ] El código debe ser dinámico según la venta

---

### Fase 3: Registro de Pago y Apertura de Recibo

#### Paso 1: Registrar un nuevo pago
1. [ ] Ir a **Pagos**
2. [ ] Seleccionar una venta con saldo pendiente
3. [ ] Click en botón **"Registrar pago"**
4. [ ] Llenar formulario:
   - [ ] Monto (ej. RD$5,000)
   - [ ] Método (ej. "Efectivo")
   - [ ] Fecha (hoy)
5. [ ] Click en **"Guardar pago"**
6. [ ] Verificar mensaje de éxito con opción "Ver recibo"

#### Paso 2: Ver recibo inmediatamente
1. [ ] Click en **"Ver recibo"** del SnackBar
2. [ ] Debe abrirse el ReceiptDialog
3. [ ] Titulo: "Recibo N°YYYYMMDD-{ID}"

#### Paso 3: Contenido del Recibo
Verificar cada sección:

**Encabezado:**
- [ ] Logo de empresa (o placeholder si no existe)
- [ ] Título "RECIBO DE PAGO" centrado
- [ ] Número de recibo único

**Información de Empresa y Fecha:**
- [ ] Nombre de empresa
- [ ] Teléfono y dirección (si existen)
- [ ] Fecha en español completo (ej. "26 de marzo de 2026")
- [ ] Hora exacta del pago

**Información de Cliente:**
- [ ] Nombre del cliente
- [ ] Número de cédula (mostrando También al lado derecho)

**Información de Solar:**
- [ ] Código del solar (Manzana-Solar)
- [ ] Saldo pendiente actualizado en RD$

**Detalles del Pago:**
- [ ] Concepto (si fue cuota: "Cuota #X", si fue capital: "Abono a Capital")
- [ ] Monto pagado en RD$ con formato correcto
- [ ] Método de pago en MAYÚSCULAS

**Estado de Cuotas:**
- [ ] Número de cuotas pagadas (en verde)
- [ ] Número de cuotas restantes (en naranja)

**Footer:**
- [ ] Mensaje de agradecimiento
- [ ] Nota de conservación

---

### Fase 4: Acceso a Recibos Históricos

1. [ ] Permanecer en Pagos (misma venta)
2. [ ] Desplazarse al **Historial**
3. [ ] Verificar que el pago registrado aparece en el historial
4. [ ] Verificar que aparece un **icono de recibo** (📋) al lado de cada pago
5. [ ] Click en el icono de recibo del pago más reciente
6. [ ] Debe abrirse el mismo recibo visto anterior

---

### Fase 5: Verificación Visual y de Diseño

#### 5.1 Distribución / Layout
- [ ] Recibo ocupa máximo 800px de ancho
- [ ] Márgenes: 40px a cada lado
- [ ] Cabe completamente en 1 página A4/Carta vertical
- [ ] Scrolleable si es demasiado largo (pero no debería serlo)

#### 5.2 Alineación de Texto
- [ ] Todos los datos están properlamente alineados
- [ ] No hay texto cortado
- [ ] No hay solapamiento de elementos
- [ ] Los números en RD$ están bien alineados a la derecha

#### 5.3 Colores y Tipografía
- [ ] Bordes azules a la izquierda en secciones del cliente y solar
- [ ] Fondos gris claro en secciones destacadas
- [ ] Títulos en negrita y mayúsculas
- [ ] Datos en tamaño legible

#### 5.4 Elementos Destacados
- [ ] "Cuotas Pagadas" en color verde
- [ ] "Cuotas Restantes" en color naranja
- [ ] Líneas separadoras grises simples
- [ ] Línea gruesa antes de footer

---

### Fase 6: Prueba de Impresión Simulada

#### 6.1 Verificar que PDF/Print están listos
1. [ ] Click en botón **"Exportar PDF"** (debe mostrar placeholder o mensaje)
2. [ ] Click en botón **"Imprimir"** (debe mostrar placeholder o mensaje)
3. [ ] Estos botones no deben causar crashes

#### 6.2 Verificación Visual para Impresión
- [ ] Abrir recibo en navegador (Print Preview):
  - [ ] Copiar y pegar toda la secuencia HTML podría verse bien
  - [ ] Se vería bien impreso en A4 vertical
  - [ ] Los márgenes son adecuados para impresora
  - [ ] Nada importante se cortaría

---

### Fase 7: Casos Especiales

#### 7.1 Pago de Cuota
1. [ ] Registrar pago que cubra una cuota completa
2. [ ] Verificar recibo: concepto muestre "Cuota #X"
3. [ ] Cuotas restantes disminuyó

#### 7.2 Abono a Capital
1. [ ] Registrar pago sin cuota vencida (puro capital)
2. [ ] Verificar recibo: concepto es "Abono a Capital"
3. [ ] Aparecer como "abono_capital" en tipo

#### 7.3 Múltiples Pagos
1. [ ] Registrar 3 pagos diferentes a la misma venta
2. [ ] Historial debe mostrar todos los 3 pagos
3. [ ] Cada uno con su icono de recibo funcional
4. [ ] Cada recibo debe ser único (números distintos)

#### 7.4 Varias Ventas
1. [ ] Cambiar de venta en el dropdown
2. [ ] Registrar pago en nueva venta
3. [ ] Historial debe cambiar
4. [ ] Recibos deben mostrar datos correctos de la nueva venta

---

### Fase 8: Validación de Conexión de Datos

#### 8.1 Verificar que NO hay datos hardcodeados
Buscar en recibo_view.dart y receipt.dart:
- [ ] No hay strings fijos como "Cliente ejemplo" o "Solar 001"
- [ ] Todos los datos vienen de propiedades de `receipt`
- [ ] Todos provenientes de base de datos

#### 8.2 Verificar que los datos son consistentes
1. [ ] Abrir recibo de un pago
2. [ ] Ir a **Ventas** > ver detalles de esa venta
3. [ ] Verificar que cliente, solar, saldo coinciden
4. [ ] Ir a **Pagos** > historial
5. [ ] Verificar que el monto y fecha coinciden

---

### Fase 9: Performance y Estabilidad

- [ ] Abrir y cerrar recibos múltiples veces sin crashes
- [ ] Cambiar de venta rápidamente sin problemas
- [ ] Historial responde rápido (no lentitud)
- [ ] Memoria se libera al cerrar diálogos (sin memory leaks)
- [ ] No hay logs ERROR en consola

---

## Reporte de Pruebas

Crear un documento con:

| Item | Status | Notas |
|------|--------|-------|
| Compilación | ✅/❌ | Detalles si hay error |
| Empresa dinámica | ✅/❌ | Ejemplo: datos mostrados |
| Cliente correcto | ✅/❌ | Nombre y cédula verificados |
| Solar correcto | ✅/❌ | Código y saldo verificados |
| Registro de pago | ✅/❌ | Monto y método |
| Apertura de recibo | ✅/❌ | Desde SnackBar action |
| Acceso histórico | ✅/❌ | Icono funcional |
| Diseño visual | ✅/❌ | Elegante y profesional |
| Impresión (simulada) | ✅/❌ | Cabe en A4 vertical |
| PDF/Print botones | ✅/❌ | Visibles sin crashes |
| Sin hardcodeados | ✅/❌ | Todo dinámico |
| Consistencia datos | ✅/❌ | Coincide con BD |
| Performance | ✅/❌ | Sin lentitud o crashes |

---

## Solución de Problemas

### "La empresa no se muestra en el recibo"
→ Verificar en **Configuración > Información de Empresa** que está guardada
→ Asegurar que CompanyRepository está inicializado correctamente

### "El recibo aparece vacío"
→ Verificar que PaymentHistoryItem tiene `id`
→ Revisar consola para errores del ReceiptRepository

### "El botón de recibo no aparece en el historial"
→ Asegurar que `paymentId` está siendo pasado correctamente
→ Verificar que PaymentHistoryItem.id no es null

### "Crash al abrir recibo"
→ Revisar logs de Flutter
→ Verificar que ReceiptDialog.show() está siendo llamado correctamente
→ Asegurar que ReceiptRepository está inicializado en AppShell

### "Fecha incorrecta en el recibo"
→ Verificar que `paymentDate` está en UTC o zona horaria correcta
→ Revisar formato en `formattedDate`

---

## Próximos Pasos (Post-Validación)

1. **Implementar Exportación a PDF**
   - Usar package `pdf` + `printing`
   - Renderizar ReceiptView a PDF
   - Guardar con nombre: `Recibo_{receiptNumber}.pdf`

2. **Implementar Impresión**
   - Usar `printing.Printing.layoutPdf()`
   - Obtener impresora de Settings
   - Permitir seleccionar impresora antes de imprimir

3. **Historial de Exportaciones**
   - Nueva tabla `exported_receipts`
   - Registrar cuando se exporta/imprime
   - Mostrar historial de exportaciones en UI

4. **Mejoras Opcionales**
   - Watermark "COPIA" para PDF exportados
   - Firma digital (si aplica regulación)
   - Múltiples idiomas (ES/EN)
   - Template configurable en Settings
