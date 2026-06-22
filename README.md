# TP Base de Datos — CQRS en un sistema de gestión de pedidos

Implementación del patrón **CQRS** (Command Query Responsibility Segregation) sobre PostgreSQL: un modelo de escritura normalizado y un modelo de lectura desnormalizado, con sincronización síncrona.

## Archivos

- `enunciado.md` — consigna del TP.
- `task.md` — plan de trabajo por partes (checklist).
- `resolucion.md` — resolución completa y comentada (Partes 1 a 4).
- `sql/` — el mismo SQL partido en archivos, listos para ejecutar en orden.

## Cómo correrlo

Requiere PostgreSQL 13+ (probado en 16).

### Rápido (scripts automatizados)

```bash
# Con Docker (recomendado)
./scripts/run_all.sh docker

# Con Postgres local
./scripts/run_all.sh local "postgresql://postgres:postgres@localhost:5432/cqrs_tp"
```

En Windows PowerShell:
```powershell
.\scripts\run_all.ps1 -Mode docker
```

`run_all.sh` hace todo en una sola corrida (9 pasos): levanta Postgres, carga el esquema y las funciones, corre el **smoke test (`08`)**, carga el dataset grande, mide el benchmark CQRS vs CRUD (con una pasada de *warm-up* de cache para que los tiempos sean estables) imprimiendo el resumen de tiempos con ratios, y finalmente corre las **pruebas negativas (`15`)** —como gate de validación— y la **demo de consistencia eventual (`16`)**.

> El smoke test inserta unos pocos datos de demo **legibles** (clientes Ana/Luis, productos Teclado/Mouse/Monitor y un pedido de ejemplo), pensados para **probar el flujo desde el frontend** —a diferencia de los `Cliente 1` / `Producto 1` que genera el seed. Son ~5 filas y **no afectan las mediciones**: las consultas del benchmark apuntan a otros IDs (cliente 42, pedido 25000).

### Manual

Con Docker:

```bash
docker run --name tp-cqrs -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
```

Ejecutar los scripts **en orden de dependencias** (no por nombre): `10_seed_benchmark.sql`
llama a `lectura.sync_ventas()`, que se define en `13_resumen_ventas.sql`, así que el seed
tiene que correr *después* del 13. Por eso usamos una lista explícita y no un glob
(`sql/1*.sql` correría 10 antes que 12/13/14 y fallaría):

```bash
for f in 00_setup 01_write_model 02_read_model 03_audit 04_sync \
         05_commands 06_indexes 07_queries 09_crud_reference \
         12_estado_historico 13_resumen_ventas 14_async_sync \
         10_seed_benchmark; do
  echo ">>> $f"
  psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f "sql/$f.sql"
done

# Benchmark CQRS vs CRUD (se corre aparte para leer los tiempos):
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/11_benchmark.sql
```

> Esto es exactamente lo que automatiza `./scripts/run_all.sh` (la vía recomendada).

Orden y propósito:

| Archivo | Qué hace |
|---|---|
| `00_setup.sql` | Crea los esquemas `escritura` y `lectura` |
| `01_write_model.sql` | Tablas normalizadas (Cliente, Producto, Pedido, ItemPedido) |
| `02_read_model.sql` | Tabla desnormalizada `PedidoResumen` |
| `03_audit.sql` | Tabla de auditoría de comandos |
| `04_sync.sql` | Función de sincronización write → read |
| `05_commands.sql` | Comandos (create, agregar item, confirmar, actualizar estado) |
| `06_indexes.sql` | Índices del modelo de lectura |
| `07_queries.sql` | Funciones de consulta |
| `08_smoke_test.sql` | Prueba rápida del flujo completo |
| `09_crud_reference.sql` | Consulta CRUD de referencia (con JOINs) para comparar |
| `10_seed_benchmark.sql` | Carga un dataset grande con `generate_series` (con semilla fija) |
| `11_benchmark.sql` | `EXPLAIN` + `\timing`: CQRS vs CRUD |
| `12_estado_historico.sql` | Historial de cambios de estado con trigger automático |
| `13_resumen_ventas.sql` | Modelo de lectura para top productos (desnormalizado) |
| `14_async_sync.sql` | Sincronización asíncrona con cola de eventos y LISTEN/NOTIFY |
| `15_pruebas_negativas.sql` | Prueba que los comandos rechazan operaciones inválidas (validaciones) |
| `16_demo_consistencia_eventual.sql` | Demo síncrono vs asíncrono (ventana de inconsistencia) |

> `08_smoke_test.sql` no está en esta lista manual a propósito, para dejar el dataset 100 % del seed. `run_all.sh` en cambio **sí lo corre** (datos de demo legibles para el frontend, ver más arriba); son pocas filas y no afectan las mediciones. Para correrlo a mano sobre una base limpia: `psql ... -f sql/08_smoke_test.sql`.

## Pruebas y demos

`run_all.sh` ya los corre al final (pasos `8` y `9`). Igual quedan como scripts independientes para correrlos por separado sobre la base ya cargada. Cada uno usa su propio fixture dentro de una transacción que se revierte (`BEGIN … ROLLBACK`), así que **no dejan datos** y se pueden correr las veces que quieras.

```bash
# Pruebas negativas: verifica que cada comando rechaza operaciones inválidas.
# Con ON_ERROR_STOP=1, si una validación NO se dispara el script falla (exit != 0).
docker compose exec -T db psql -U postgres -d cqrs_tp -v ON_ERROR_STOP=1 -f /sql/15_pruebas_negativas.sql

# Demo de consistencia eventual: síncrono (sin ventana) vs asíncrono (con ventana).
docker compose exec -T db psql -U postgres -d cqrs_tp -f /sql/16_demo_consistencia_eventual.sql
```

`15` imprime un `OK …` por cada validación; `16` muestra los dos modelos lado a lado antes y después de procesar la cola (`16` requiere haber cargado `14_async_sync.sql`).

## Decisiones de diseño

- **Dos esquemas** (`escritura` / `lectura`) para hacer explícita la separación de modelos.
- `PedidoResumen` es una **tabla mantenida por los comandos**, no una vista materializada: permite implementar y medir la sincronización, que es el corazón del TP.
- Sincronización **síncrona** (misma transacción) → consistencia fuerte. La variante asíncrona se implementa en `14_async_sync.sql`.
- Al cancelar un pedido confirmado se **repone el stock** automáticamente.
- Cada cambio de estado se registra en `EstadoHistorico` vía trigger.
- `ResumenVentas` mantiene un modelo de lectura para top productos, evitando JOINs sobre el modelo de escritura en tiempo de consulta.

## Mejoras implementadas

| Archivo | Mejora |
|---------|--------|
| `sql/05_commands.sql` | Reposición de stock al cancelar pedidos Confirmado/Enviado |
| `sql/06_indexes.sql` | Índice FK `idx_item_pedido` para una comparación CRUD justa |
| `sql/07_queries.sql` | `obtener_top_productos` movido al modelo de lectura (`13_resumen_ventas.sql`) |
| `sql/09_crud_reference.sql` | Índice `idx_pedido_cliente` para benchmark justo |
| `sql/10_seed_benchmark.sql` | Semilla fija (`setseed(0.5)`) + `sync_ventas` para datos reproducibles |
| `sql/11_benchmark.sql` | `EXPLAIN` + `\timing` de las 4 consultas (evita el overhead de instrumentación) |
| `sql/12_estado_historico.sql` | Tabla + trigger de historial de cambios de estado |
| `sql/13_resumen_ventas.sql` | Modelo de lectura desnormalizado para top productos |
| `sql/14_async_sync.sql` | Cola de eventos + LISTEN/NOTIFY para sincronización asíncrona |
| `sql/15_pruebas_negativas.sql` | Pruebas de las validaciones de negocio (gate) |
| `sql/16_demo_consistencia_eventual.sql` | Demo ejecutable síncrono vs asíncrono |
| `scripts/run_all.sh` | Carga + benchmark con ratios + pruebas + RESUMEN FINAL en una corrida |
| `docs/diagrama_arquitectura.md` | Diagrama Mermaid de la arquitectura CQRS |
| `docker-compose.yml` | Entorno reproducible con Postgres 16 + app |
| `app/Dockerfile` | Imagen Docker para la app FastAPI |
| `app/main.py` | Endpoints nuevos: historial, auditoría, dashboard métricas |
| `app/static/index.html` | Dashboard, auditoría, historial de estados, diagrama de arq. |
| `resolucion.md` | Parte 4 con mediciones reales + referencias a pruebas (`15`) y demo (`16`) |
