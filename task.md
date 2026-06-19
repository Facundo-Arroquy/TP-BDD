# Plan de resolución del TP: CQRS en PostgreSQL

Guía paso a paso para resolver el trabajo práctico completo. Cada parte se corresponde con un entregable del enunciado y su porcentaje.

> Convención de estado: `[ ]` pendiente · `[~]` en progreso · `[x]` hecho.

## Decisiones previas (acordar con el grupo)

- [ ] **Motor**: PostgreSQL (lo pide el enunciado en la Parte 2 y 3).
- [ ] **Estrategia de sincronización**: implementar al menos la **síncrona** (obligatoria). Si hay tiempo, agregar la **asíncrona** con triggers para el análisis comparativo.
- [ ] **Entorno reproducible**: usar Docker (`docker run postgres:16`) o instalación local. Definir un único `docker-compose.yml` para que todos trabajen igual.
- [ ] **Datos de prueba**: definir un volumen de datos suficiente para medir rendimiento (ej. 10k clientes, 100k pedidos, 500k ítems).

## Estructura de archivos sugerida

```
tp/
├── enunciado.md
├── task.md
├── sql/
│   ├── 00_setup.sql            # creación de la base / esquemas
│   ├── 01_write_model.sql      # tablas normalizadas (command model)
│   ├── 02_read_model.sql       # tablas desnormalizadas (query model)
│   ├── 03_commands.sql         # procedimientos almacenados (comandos)
│   ├── 04_sync.sql             # sincronización write -> read
│   ├── 05_queries.sql          # funciones/vistas de consulta
│   ├── 06_indexes.sql          # índices del modelo de lectura
│   ├── 07_audit.sql            # tabla y lógica de auditoría
│   └── 08_seed.sql             # datos de prueba
├── benchmarks/
│   └── compare_cqrs_vs_crud.sql
├── docs/
│   ├── diagrama_arquitectura.png
│   └── informe.md              # informe final con análisis y conclusiones
└── README.md
```

---

## Parte 1 — Diseño del modelo (30 %)

- [ ] **Modelo de escritura (normalizado)**
  - [ ] Tabla `Cliente` (necesaria como FK de `Pedido`; el enunciado la asume).
  - [ ] Tabla `Producto` (necesaria como FK de `ItemPedido` y para stock).
  - [ ] Tabla `Pedido` con PK, FK a `Cliente`, `Estado`, `Total`, `Fecha_Creacion`.
  - [ ] Tabla `ItemPedido` con PK, FK a `Pedido` y `Producto`, `Cantidad`, `Precio_Unitario`.
  - [ ] Definir restricciones: `NOT NULL`, `CHECK` en `Estado`, `CHECK (Cantidad > 0)`, FKs con `ON DELETE`.
- [ ] **Modelo de lectura (desnormalizado)**
  - [ ] Tabla `PedidoResumen` con datos del cliente y de los ítems embebidos (`Nombre_Cliente`, `Productos`, `Cantidad_Items`).
  - [ ] Evaluar vista materializada vs tabla mantenida por comandos. Para este TP conviene **tabla** (se actualiza desde los comandos y permite medir la sincronización).
  - [ ] Definir índices candidatos (ver Parte 3).
- [ ] **Diagrama de arquitectura CQRS**
  - [ ] Mostrar el flujo: Cliente → Comando → Modelo de escritura → Sincronización → Modelo de lectura → Consultas.
  - [ ] Herramienta sugerida: dbdiagram.io, draw.io o Mermaid.
- [ ] **Justificación de la desnormalización**
  - [ ] Redactar por qué cada campo desnormalizado evita JOINs en lectura (trade-off espacio/duplicación vs latencia).

**Entregable:** scripts `01_write_model.sql`, `02_read_model.sql`, diagrama y justificación escrita.

## Parte 2 — Implementación de comandos (30 %)

- [ ] **Procedimientos almacenados (un comando = un procedure/función)**
  - [ ] `CreatePedido(id_cliente)` → inserta pedido en estado `Pendiente`.
  - [ ] `AgregarItem(id_pedido, id_producto, cantidad)` → valida stock disponible.
  - [ ] `ConfirmarPedido(id_pedido)` → cambia estado y **descuenta stock** (transacción atómica).
  - [ ] `ActualizarEstado(id_pedido, nuevo_estado)` → valida transición de estado.
- [ ] **Validaciones de negocio**
  - [ ] Stock suficiente antes de agregar/confirmar (`RAISE EXCEPTION` si no alcanza).
  - [ ] Cliente y producto existentes.
  - [ ] Transiciones de estado válidas (no pasar de `Entregado` a `Pendiente`).
  - [ ] Recalcular `Total` del pedido al agregar/quitar ítems.
- [ ] **Sincronización del modelo de lectura (al menos síncrona)**
  - [ ] Dentro de cada comando (misma transacción), actualizar `PedidoResumen`.
  - [ ] (Opcional) Variante asíncrona con `TRIGGER` + tabla de eventos o `LISTEN/NOTIFY`.
- [ ] **Auditoría**
  - [ ] Tabla `AuditoriaComando(id, comando, payload, usuario, timestamp)`.
  - [ ] Registrar cada ejecución de comando.

**Entregable:** scripts `03_commands.sql`, `04_sync.sql`, `07_audit.sql` + pruebas que demuestren las validaciones.

## Parte 3 — Implementación de consultas (20 %)

- [ ] **Funciones o vistas de consulta sobre el modelo de lectura**
  - [ ] `ObtenerPedidosPorCliente(id_cliente)`.
  - [ ] `ObtenerResumenPedido(id_pedido)`.
  - [ ] `ObtenerEstadoEnvio(id_pedido)` (proyección mínima, solo el estado).
  - [ ] `ObtenerTopProductos(fecha_desde, fecha_hasta)`.
- [ ] **Índices apropiados**
  - [ ] Índice por `ID_Cliente` (o `Nombre_Cliente`) en `PedidoResumen`.
  - [ ] Índice por `Estado` y por `Fecha_Creacion` según las consultas.
- [ ] **Demostración de mejora de rendimiento**
  - [ ] Comparar `EXPLAIN ANALYZE` de cada consulta sobre el modelo de lectura vs la misma consulta resuelta con JOINs sobre el modelo normalizado.
  - [ ] Documentar tiempos y planes de ejecución.

**Entregable:** scripts `05_queries.sql`, `06_indexes.sql` + tabla comparativa de tiempos.

## Parte 4 — Análisis y comparación (20 %)

- [ ] **CQRS vs CRUD tradicional**
  - [ ] Definir un esquema CRUD de referencia (solo modelo normalizado, consultas con JOINs).
  - [ ] Medir tiempos de lectura y escritura en ambos enfoques con el mismo dataset.
  - [ ] Presentar resultados en tabla/gráfico.
- [ ] **Impacto de la consistencia eventual**
  - [ ] Analizar qué ve el usuario si lee antes de que se propague la escritura (en la variante asíncrona).
- [ ] **Cuándo CQRS agrega complejidad innecesaria**
  - [ ] Identificar escenarios (bajo volumen, equipos chicos, dominios simples).
- [ ] **Conclusión grupal**
  - [ ] Redactar la aplicabilidad de CQRS en sistemas reales.

**Entregable:** `docs/informe.md` con mediciones, gráficos y conclusiones.

---

## Cierre y entrega

- [ ] `README.md` con instrucciones para levantar la base y correr los scripts en orden.
- [ ] Verificar que todos los scripts corren limpios de cero (`00_setup` → `08_seed`).
- [ ] Revisar que cada entregable del enunciado esté cubierto (checklist de porcentajes: 30+30+20+20 = 100 %).
- [ ] Repaso final del informe: redacción, diagramas legibles, conclusiones fundamentadas.

## Orden de trabajo recomendado

1. Setup del entorno (Docker + Postgres) y estructura de carpetas.
2. Parte 1 completa (modelos + diagrama) — es la base de todo.
3. Parte 2 (comandos + sync síncrona + auditoría).
4. `08_seed.sql` con datos de prueba en volumen.
5. Parte 3 (consultas + índices + EXPLAIN ANALYZE).
6. Parte 4 (benchmarks CQRS vs CRUD + informe).
7. README, verificación de corrida limpia y repaso final.
