# Mejoras Propuestas — Proyecto Blockchain Inmobiliario
### Presentado en respuesta a las observaciones de la Prof. Elisa Galdame

---

## Mejora 1 — Protocolo para Aceptar el Contrato en Blockchain como Contrato Digital

> **El puente legal: de la pantalla al juzgado**

Para que un contrato digital no sea solo "un PDF lindo" y tenga peso jurídico real en Argentina, el sistema implementa el siguiente circuito de cinco pasos:

---

### Paso 1 — Validación de Identidad · *¿Quién sos?*

Antes de redactar el contrato, el sistema verifica la identidad de cada parte cruzando sus datos con el **RENAPER**. Esto ata a la persona física al usuario digital, dejando constancia de que quien firma es efectivamente quien dice ser.

---

### Paso 2 — Generación del Documento · *La foto final*

Las condiciones del acuerdo (precio, plazos, inmueble) se consolidan en un **PDF inmutable**. Una vez generado, el documento no puede ser modificado sin invalidar el proceso completo.

---

### Paso 3 — Firma Segura · *La prueba de intención*

Las partes firman el documento. Para garantizar que nadie pueda alegar "yo no fui", el sistema registra:

- **Timestamp** — fecha y hora exacta de la firma
- **IP del firmante** — ubicación de red en el momento del acto
- **Doble factor (2FA por SMS)** — confirmación activa de la intención de firmar

---

### Paso 4 — Hash Criptográfico · *La huella digital*

Al PDF final firmado se le calcula su **huella SHA-256**: una cadena única de caracteres que representa ese documento exacto. Si se modifica un solo carácter del PDF, el hash cambia por completo.

---

### Paso 5 — Registro en Blockchain · *El escribano ciego*

La huella SHA-256 se publica en la red **Polygon**. La blockchain no lee el contenido del contrato ni emite opinión legal; actúa como un **notario inmutable** que certifica que ese documento exacto existía en ese segundo exacto. La prueba es pública, permanente y no puede ser alterada.

---

## Mejora 2 — Las 5 Características del Contrato antes de Ingresar a la Base de Datos

> Antes de persistir un contrato en la base de datos, el sistema aplica cinco controles obligatorios. Si alguno falla, el documento es rechazado.

---

### Característica 1 — Completitud Legal · *Que no falte nada*

El sistema actúa como un corrector automático. Verifica que el contrato contenga todos los campos exigidos por la **Ley de Alquileres** vigente en Argentina: domicilio del inmueble, precio pactado, plazos de vigencia y demás cláusulas obligatorias. Un contrato incompleto es rebotado antes de llegar a la base de datos.

---

### Característica 2 — Seguridad Informática · *Que esté limpio*

El archivo pasa por un filtro que garantiza que se trata de un **PDF puro**, sin scripts maliciosos, macros ocultos ni vectores de ataque embebidos. Esto protege tanto al sistema como a los usuarios de amenazas del tipo PDF exploit.

---

### Característica 3 — Trazabilidad · *Que deje rastro*

Se genera un conjunto de **metadatos de auditoría** adjuntos al documento:

| Campo | Valor registrado |
|---|---|
| Usuario creador | Legajo del agente inmobiliario |
| Dispositivo | Identificador del equipo utilizado |
| Timestamp de creación | Fecha y hora del borrador |

Esta información es interna y no viaja a la blockchain.

---

### Característica 4 — Privacidad de Datos · *Que cuide los datos personales*

El sistema aplica **separación de datos** en cumplimiento de la Ley 25.326 de Protección de Datos Personales:

- **Datos sensibles** (nombres, DNI, domicilio real): permanecen **encriptados** en el servidor privado de la inmobiliaria.
- **Datos transaccionales** (hash del contrato, timestamps de firma): son los únicos que viajan a la blockchain pública.

Así, la red pública nunca contiene información personal identificable.

---

### Característica 5 — Aceptación Explícita · *Que den el "Sí"*

El sistema bloquea la activación del contrato hasta que **cada una de las partes** haya registrado un clic en el botón **"Acepto los términos y condiciones"**. Este evento queda logueado con usuario, timestamp e IP. Sin el "Sí" explícito de todos los involucrados, el contrato no se activa ni persiste en la base de datos.

---

*Documento generado para exposición académica — Block Prop*

## Cómo hacer la demo

1. Andá a la pestaña **Inmobiliaria**
2. Tocá **"Generar contrato nuevo"**
3. Se abre el modal con las dos mejoras secuenciadas

## Qué hace cada una

**Mejora 1** — muestra el protocolo de 5 pasos de forma interactiva: cada paso se desbloquea solo cuando el anterior se completó, y el registro on-chain en vivo muestra qué evento se está certificando en cada momento (RENAPER, PDF, 2FA, hash, Polygon).

**Mejora 2** — tiene un botón "Ejecutar validación" que dispara los 5 controles en cascada con animación de estado (pendiente → verificando → OK), mostrando visualmente que el documento pasa cada filtro antes de tocar la base de datos.