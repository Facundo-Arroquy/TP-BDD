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

### Manual

Con Docker:

```bash
docker run --name tp-cqrs -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
```

Ejecutar los scripts en orden:

```bash
for f in sql/0*.sql sql/1*.sql; do
  echo ">>> $f"
  psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f "$f"
done
```

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
| `11_benchmark.sql` | `EXPLAIN ANALYZE`: CQRS vs CRUD |
| `12_estado_historico.sql` | Historial de cambios de estado con trigger automático |
| `13_resumen_ventas.sql` | Modelo de lectura para top productos (desnormalizado) |
| `14_async_sync.sql` | Sincronización asíncrona con cola de eventos y LISTEN/NOTIFY |

> `08_smoke_test.sql` inserta datos de ejemplo. Si después vas a correr el benchmark, podés saltearlo o resetear con `00`–`07` para no mezclar datasets.

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
| `sql/07_queries.sql` | `obtener_top_productos` movido al modelo de lectura (`13_resumen_ventas.sql`) |
| `sql/09_crud_reference.sql` | Índice `idx_pedido_cliente` para benchmark justo |
| `sql/10_seed_benchmark.sql` | Semilla fija (`setseed(0.5)`) para datos reproducibles |
| `sql/12_estado_historico.sql` | Tabla + trigger de historial de cambios de estado |
| `sql/13_resumen_ventas.sql` | Modelo de lectura desnormalizado para top productos |
| `sql/14_async_sync.sql` | Cola de eventos + LISTEN/NOTIFY para sincronización asíncrona |
| `docs/diagrama_arquitectura.md` | Diagrama Mermaid de la arquitectura CQRS |
| `docker-compose.yml` | Entorno reproducible con Postgres 16 + app |
| `app/Dockerfile` | Imagen Docker para la app FastAPI |
| `app/main.py` | Endpoints nuevos: historial, auditoría, dashboard métricas |
| `app/static/index.html` | Dashboard, auditoría, historial de estados, diagrama de arq. |
| `resolucion.md` | Tabla benchmark completa con todas las consultas |
