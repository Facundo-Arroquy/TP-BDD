# Trabajo Práctico: CQRS aplicado a un sistema de gestión de pedidos

## 1. Descripción general

El presente trabajo práctico propone el diseño e implementación del patrón **CQRS** (Command Query Responsibility Segregation) aplicado a un sistema de gestión de pedidos en línea. CQRS propone separar las operaciones de lectura (*queries*) de las operaciones de escritura (*commands*) en modelos distintos, optimizando cada uno para su propósito específico.

A partir de un modelo de datos único, se derivarán dos modelos independientes: un modelo de escritura orientado a comandos y transacciones, y un modelo de lectura optimizado para consultas y proyecciones. Se evaluarán los beneficios en términos de escalabilidad, mantenibilidad y rendimiento, así como los desafíos de consistencia eventual.

## 2. Objetivos

### 2.1. Objetivo general

Diseñar e implementar una arquitectura CQRS para un sistema de gestión de pedidos, separando los modelos de lectura y escritura, y analizando el impacto en el rendimiento, la escalabilidad y la consistencia de los datos.

### 2.2. Objetivos específicos

- Definir un modelo de escritura orientado a transacciones con validaciones de negocio.
- Definir un modelo de lectura basado en proyecciones desnormalizadas para consultas eficientes.
- Implementar comandos para las operaciones de escritura (crear pedido, actualizar estado, etc.).
- Implementar consultas optimizadas para las operaciones de lectura (listar pedidos, resumen por cliente, etc.).
- Analizar el compromiso entre consistencia fuerte y consistencia eventual.
- Comparar la arquitectura CQRS contra un enfoque CRUD tradicional mediante métricas de rendimiento.
- Reflexionar sobre los casos de uso donde CQRS es apropiado y cuándo es sobredimensionado.

## 3. Consigna propuesta

### 3.1. Caso de estudio: Sistema de Gestión de Pedidos en Línea

Se debe modelar un sistema de pedidos donde las operaciones de escritura (crear pedido, agregar ítems, procesar pago) ocurren con baja frecuencia pero requieren alta consistencia, mientras que las operaciones de lectura (listar pedidos de un cliente, ver estado de envío, generar reportes) ocurren con alta frecuencia y requieren baja latencia.

### 3.2. Modelo de escritura (Command Model)

Tablas normalizadas orientadas a la integridad transaccional.

**Cuadro 1: Tabla Pedido (Modelo de escritura)**

| Columna | Tipo | Descripción |
|---|---|---|
| ID_Pedido | INT PK | Identificador único |
| ID_Cliente | INT FK | Cliente asociado |
| Fecha_Creacion | DATETIME | Fecha de creación |
| Estado | VARCHAR(20) | Pendiente, Confirmado, Enviado, Entregado |
| Total | DECIMAL(10,2) | Total calculado del pedido |

**Tabla ItemPedido**

| Columna | Tipo | Descripción |
|---|---|---|
| ID_Item | INT PK | Identificador único |
| ID_Pedido | INT FK | Pedido asociado |
| ID_Producto | INT FK | Producto solicitado |
| Cantidad | INT | Cantidad solicitada |
| Precio_Unitario | DECIMAL(10,2) | Precio al momento del pedido |

#### 3.2.1. Comandos a implementar

- **CreatePedidoCommand**: Crea un nuevo pedido con estado Pendiente.
- **AgregarItemCommand**: Agrega un ítem al pedido validando stock.
- **ConfirmarPedidoCommand**: Confirma el pedido y descuenta stock.
- **ActualizarEstadoCommand**: Actualiza el estado (Enviado, Entregado, Cancelado).

### 3.3. Modelo de lectura (Query Model)

Tablas desnormalizadas optimizadas para consultas rápidas.

**Cuadro 2: Tabla PedidoResumen (Modelo de lectura)**

| Columna | Tipo | Descripción |
|---|---|---|
| ID_Pedido | INT PK | Identificador único |
| Nombre_Cliente | VARCHAR(100) | Nombre del cliente (desnormalizado) |
| Email_Cliente | VARCHAR(100) | Email del cliente (desnormalizado) |
| Fecha_Creacion | DATETIME | Fecha de creación |
| Estado | VARCHAR(20) | Estado actual |
| Total | DECIMAL(10,2) | Total calculado |
| Cantidad_Items | INT | Cantidad de ítems (desnormalizada) |
| Productos | TEXT | Lista de productos (desnormalizada) |

#### 3.3.1. Consultas a implementar

- **ObtenerPedidosPorCliente**: Retorna todos los pedidos de un cliente con datos desnormalizados.
- **ObtenerResumenPedido**: Retorna el detalle completo de un pedido en una sola consulta.
- **ObtenerEstadoEnvio**: Retorna únicamente el estado de envío (proyección mínima).
- **ObtenerTopProductos**: Retorna los productos más vendidos en un período.

### 3.4. Sincronización entre modelos

Después de ejecutar cada comando sobre el modelo de escritura, se debe propagar el cambio al modelo de lectura. Esta sincronización puede ser:

- **Síncrona**: El comando actualiza ambos modelos en la misma transacción. Ofrece consistencia fuerte pero mayor latencia de escritura.
- **Asíncrona (Eventual)**: El comando actualiza solo el modelo de escritura; un mecanismo separado (trigger, evento, job) propaga los cambios al modelo de lectura. Ofrece menor latencia de escritura pero consistencia eventual.

Se debe implementar al menos una variante y analizar las compensaciones.

## 4. Actividades y entregables

### 4.1. Parte 1: Diseño del modelo (30 %)

1. Definir el esquema completo del modelo de escritura (tablas normalizadas, claves, restricciones).
2. Definir el esquema del modelo de lectura (tablas desnormalizadas, índices, vistas materializadas).
3. Diagrama de la arquitectura CQRS mostrando el flujo de comandos y consultas.
4. Justificar las decisiones de desnormalización en el modelo de lectura.

### 4.2. Parte 2: Implementación de comandos (30 %)

1. Implementar procedimientos almacenados para cada comando en PostgreSQL.
2. Incluir validaciones de negocio (stock suficiente, cliente válido, etc.).
3. Implementar sincronización del modelo de lectura (al menos síncrona).
4. Registrar auditoría de cada comando ejecutado.

### 4.3. Parte 3: Implementación de consultas (20 %)

1. Implementar funciones o vistas para cada consulta en PostgreSQL.
2. Optimizar las consultas con índices apropiados en el modelo de lectura.
3. Demostrar la mejora de rendimiento frente a consultas sobre el modelo normalizado.

### 4.4. Parte 4: Análisis y comparación (20 %)

1. Comparar tiempos de respuesta entre CQRS y un enfoque CRUD tradicional sobre el mismo conjunto de datos.
2. Analizar el impacto de la consistencia eventual en la experiencia de usuario.
3. Identificar escenarios donde CQRS agrega complejidad innecesaria.
4. Conclusión grupal sobre la aplicabilidad de CQRS en sistemas reales.
