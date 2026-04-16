# Modificaciones de Validación y Formato de Cliente - República Dominicana

## Resumen
Se implementaron validaciones y formatos específicos para República Dominicana en los campos del formulario de clientes.

## Cambios Implementados

### 1. **Nombre Completo**
- ✅ **Formato**: Solo letras (A-Z, a-z, acentos) y espacios
- ✅ **Validación**: 
  - Mínimo 3 caracteres
  - Sin números ni caracteres especiales
  - InputFormatter automático que filtra caracteres no permitidos
- ✅ **Ejemplos válidos**:
  - Juan Pérez García
  - María José de los Santos
  - Francisco Óscar Núñez

### 2. **Cédula de Identidad**
- ✅ **Formato dominicano**: XXX-XXXXXXX-X (11 dígitos)
  - Primer grupo: 3 dígitos
  - Segundo grupo: 7 dígitos
  - Tercer grupo: 1 dígito verificador
- ✅ **Validación**:
  - Exactamente 11 dígitos
  - Dígito verificador validado con algoritmo dominicano
  - Acepta entrada sin formato y auto-formatea
  - Rechaza si el checksum es inválido
- ✅ **InputFormatter**: Formatea automáticamente mientras se escribe
- ✅ **Ejemplos**:
  - 402-1234567-8 ✓
  - 00012345678 ✓ (se formatea a 000-1234567-8)

### 3. **Teléfono**
- ✅ **Formato dominicano**: +1-XXX-XXXX-XXXX
- ✅ **Códigos de área válidos**:
  - 809 (Codetel Original)
  - 829 (Codetel)
  - 849 (Orange/Trilogy)
- ✅ **Validación**:
  - Mínimo 10 dígitos, máximo 12
  - Código de área válido para República Dominicana
  - Acepta números sin formato
  - Valida que el área corresponda a RD
- ✅ **InputFormatter**: Formatea automáticamente (ej: 8091234567 → +1-809-1234-5678)
- ✅ **Campo opcional**: Puede estar vacío
- ✅ **Ejemplos válidos**:
  - 809-1234-5678
  - 8291234567
  - +1-849-1234-5678

### 4. **Dirección**
- ✅ **Validación**:
  - Mínimo 5 caracteres
  - Máximo 200 caracteres
  - Soporta múltiples líneas
- ✅ **Normalización**: Capitaliza la primera letra de cada palabra
- ✅ **Campo opcional**: Puede estar vacío
- ✅ **Ejemplos**:
  - Calle Principal 123, Apto 4B, Santo Domingo
  - Av. Independencia 456, Zona Colonial

## Archivos Creados

### `lib/core/utils/dominican_validators.dart`
Contiene las funciones de validación:
- `validateName()` - Valida nombre completo
- `validateDominicanId()` - Valida cédula con checksum
- `validateDominicanPhone()` - Valida teléfono dominicano
- `validateAddress()` - Valida dirección
- `formatDominicanId()` - Formatea cédula
- `formatDominicanPhone()` - Formatea teléfono
- `normalizeAddress()` - Normaliza dirección

### `lib/core/utils/dominican_formatters.dart`
InputFormatters para formateo en tiempo real:
- `NameFormatter` - Filtra solo letras y espacios
- `DominicanIdFormatter` - Formatea según patrón XXX-XXXXXXX-X
- `DominicanPhoneFormatter` - Formatea según patrón (XXX) XXX-XXXX

## Archivos Modificados

### `lib/features/clients/presentation/client_form_dialog.dart`
- Importados validadores y formateadores
- Agregados InputFormatters a cada campo
- Mejoraron textos de ayuda (labelText, hintText, helperText)
- Actualizada lógica de guardado con normalización
- Campo de dirección ahora acepta múltiples líneas (maxLines: 2)
- Teléfono con keyboardType: TextInputType.phone

## Comportamiento en Tiempo Real

### Mientras se escribe:
1. **Nombre**: Se filtran automáticamente números y caracteres especiales
2. **Cédula**: Se formatea automáticamente con guiones (ej: 402-1234567-8)
3. **Teléfono**: Se formatea automáticamente (ej: (829) 531-9442)
4. **Dirección**: Se acepta como está, pero se normaliza al guardar

### Al guardar:
1. Se valida que todos los campos obligatorios sean correctos
2. Se aplican formatos finales
3. Se normaliza la dirección (capitalize)
4. Se muestra error si hay validación fallida

## Validaciones Aplicadas

| Campo | Obligatorio | Validación |
|-------|------------|-----------|
| Nombre | ✓ | 3+ caracteres, solo letras |
| Cédula | ✓ | 11 dígitos, checksum válido |
| Teléfono | ✗ | Código 809/829/849, 10 dígitos |
| Dirección | ✗ | 5-200 caracteres |

## Testing Manual

Para probar los cambios:

1. **Crear nuevo cliente**:
   - Ingresar: "juan perez"
   - Ingresar cédula: "80212345671" (debe validar checksum)
   - Ingresar teléfono: "8091234567"
   - Ingresar dirección: "calle principal 123"

2. **Validaciones que deben fallar**:
   - Nombre: "123abc" (rechaza números)
   - Cédula: "123" (muy corta)
   - Cédula: "12345678901" (checksum inválido)
   - Teléfono: "7001234567" (código 700 no válido)

## Notas Importantes

- Los formatos se aplican automáticamente sin que el usuario escriba manualmente los guiones/símbolos
- El validador de cédula usa el algoritmo oficial dominicano de dígito verificador
- El teléfono es opcional, pero si se ingresa debe ser válido
- Todos los campos obligatorios deben validar antes de guardar
