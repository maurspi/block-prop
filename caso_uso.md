markdown_content = """# 📑 Smart Contract de Alquiler vs. Contrato Tradicional
> *Análisis de funcionalidades y guía práctica de despliegue para la modernización de acuerdos locativos on-chain.*

---

## 💡 5 Insights Clave: Funcionalidades Superiores

Un contrato inteligente (*smart contract*) aporta transparencia, inmutabilidad y automatización al proceso de alquiler. A continuación, se detallan cinco ventajas concretas frente a un contrato tradicional:

### 1. 🔒 Depósito de Garantía en Escrow Automático
* **El problema tradicional:** El propietario retiene el dinero y suele demorar o poner excusas para devolverlo al finalizar el contrato.
* **La solución on-chain:** El depósito no lo custodia ninguna de las partes; queda bloqueado de forma segura en el código del contrato. 
* **Mecanismo:** Al concluir el período de alquiler, si no se registran reclamos en un plazo de **X días**, los fondos se liberan de manera automática hacia la wallet del inquilino. En caso de disputa, un árbitro designado (vía oráculo descentralizado o un esquema *multisig*) resolverá el destino de los fondos según las pruebas presentadas.

### 2. 💸 Pago de Alquiler con Ejecución y Penalidad Automática
* **El problema tradicional:** Los retrasos en los pagos exigen reclamos recurrentes, cálculos manuales de intereses y gestiones informales de cobro.
* **La solución on-chain:** El inquilino aprueba un débito mensual recurrente desde su wallet autorizando al contrato.
* **Mecanismo:** Si el pago no se procesa a la fecha de vencimiento, el contrato aplica el interés punitorio pactado de forma inmediata y automática. Al acumular **N meses de mora**, el sistema dispara una notificación formal e inmutable en la blockchain, sirviendo como evidencia válida y auditable para procesos legales ulteriores.

### 3. 📈 Actualización de Precio Indexada a un Oráculo
* **El problema tradicional:** En contextos de alta inflación (como el mercado argentino), las actualizaciones requieren anexos firmados, renegociaciones tensas o proyecciones arbitrarias.
* **La solución on-chain:** El contrato se conecta de forma directa a una fuente externa de datos confiable.
* **Mecanismo:** Mediante un oráculo descentralizado, el contrato consulta el **ICL (Índice de Contratos de Locación)**, el **Índice Casa Propia** o el **IPC del INDEC**, recalculando el canon locativo de forma exacta, transparente y automática en cada período configurado, eliminando la fricción de la negociación manual.

### 4. 🛠️ Registro de Incidencias y Mantenimiento On-Chain
* **El problema tradicional:** El clásico *"yo nunca recibí la notificación de la rotura"* o discusiones sobre los plazos de reparación de vicios redhibitorios (humedad, cañerías, etc.).
* **La solución on-chain:** Trazabilidad absoluta de la gestión operativa de la propiedad.
* **Mecanismo:** El inquilino registra formalmente el reclamo en el contrato adjuntando un identificador criptográfico. Esto genera un *timestamp* (marca de tiempo) inmutable. Si el propietario no responde o soluciona el problema dentro del plazo legal acordado, el contrato habilita automáticamente al inquilino a contratar la reparación por su cuenta y descontar dicho costo del pago del alquiler del mes siguiente.

### 5. 🚪 Cláusula de Salida Anticipada Programable
* **El problema tradicional:** Liquidaciones manuales complejas, demoras en la rescisión, firmas ante escribano y disputas por el preaviso.
* **La solución on-chain:** Parámetros de rescisión 100% codificados desde el día uno.
* **Mecanismo:** Las penalidades (multas de *X* meses), plazos de preaviso mínimo y la devolución proporcional del depósito se ejecutan de manera algorítmica. Cumplidas las condiciones, el contrato finaliza el vínculo jurídico, distribuye los saldos correspondientes y emite un **NFT de "Contrato Finalizado"** que opera como recibo definitivo de finiquito para ambas partes.

---

## 📊 Estructura del Canvas Operativo

El modelo de negocio y control del smart contract se agrupa estratégicamente en dos ejes funcionales bien definidos:
