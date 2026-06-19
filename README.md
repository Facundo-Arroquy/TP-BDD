# TP Base de Datos — CQRS en un sistema de gestión de pedidos

Implementación del patrón **CQRS** (Command Query Responsibility Segregation) sobre PostgreSQL: un modelo de escritura normalizado y un modelo de lectura desnormalizado, con sincronización síncrona.

## Archivos

- `enunciado.md` — consigna del TP.
- `task.md` — plan de trabajo por partes (checklist).
- `resolucion.md` — resolución completa y comentada (Partes 1 a 4).
- `sql/` — el mismo SQL partido en archivos, listos para ejecutar en orden.

## Cómo correrlo

Requiere PostgreSQL 13+ (probado en 16). Con Docker:

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
| `10_seed_benchmark.sql` | Carga un dataset grande con `generate_series` |
| `11_benchmark.sql` | `EXPLAIN ANALYZE`: CQRS vs CRUD |

> `08_smoke_test.sql` inserta datos de ejemplo. Si después vas a correr el benchmark, podés saltearlo o resetear con `00`–`07` para no mezclar datasets.

## Decisiones de diseño

- **Dos esquemas** (`escritura` / `lectura`) para hacer explícita la separación de modelos.
- `PedidoResumen` es una **tabla mantenida por los comandos**, no una vista materializada: permite implementar y medir la sincronización, que es el corazón del TP.
- Sincronización **síncrona** (misma transacción) → consistencia fuerte. La variante asíncrona se discute en `resolucion.md`.
