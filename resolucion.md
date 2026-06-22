# Resolución del TP: CQRS en PostgreSQL

Este archivo resuelve las **Partes 1, 2 y 3** del enunciado (diseño de modelos, comandos y consultas), es decir, el 80 % del trabajo práctico. Todo el SQL fue probado en PostgreSQL 16.

La Parte 4 (benchmarks CQRS vs CRUD y conclusiones) queda pendiente porque requiere medir sobre un dataset propio; al final se deja la guía para encararla.

> Cómo correr todo: ejecutar los bloques en orden (1 → 8). Cada bloque también está pensado para vivir en su propio archivo dentro de `sql/` (ver `task.md`).
>
> **Mejoras posteriores:** este TP fue extendido con reposición de stock al cancelar, historial de estados vía trigger, modelo de lectura para top productos (`ResumenVentas`), sincronización asíncrona con cola de eventos, dashboard de métricas, vista de auditoría y diagrama de arquitectura. Ver `README.md`.

---

## Parte 1 — Diseño del modelo

### 1. Setup

Usamos dos esquemas para que la separación lectura/escritura sea explícita.

```sql
DROP SCHEMA IF EXISTS escritura CASCADE;
DROP SCHEMA IF EXISTS lectura  CASCADE;
CREATE SCHEMA escritura;  -- command model (normalizado)
CREATE SCHEMA lectura;    -- query model (desnormalizado)
```

### 2. Modelo de escritura (Command Model)

Tablas normalizadas, orientadas a la integridad transaccional.
`Cliente` y `Producto` no aparecen en el cuadro del enunciado, pero son necesarias: `Pedido` referencia a `Cliente`, e `ItemPedido` referencia a `Producto`; además `Producto` guarda el stock que validan los comandos.

```sql
CREATE TABLE escritura.Cliente (
    ID_Cliente   SERIAL PRIMARY KEY,
    Nombre       VARCHAR(100) NOT NULL,
    Email        VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE escritura.Producto (
    ID_Producto  SERIAL PRIMARY KEY,
    Nombre       VARCHAR(100) NOT NULL,
    Precio       DECIMAL(10,2) NOT NULL CHECK (Precio >= 0),
    Stock        INT NOT NULL CHECK (Stock >= 0)
);

CREATE TABLE escritura.Pedido (
    ID_Pedido      SERIAL PRIMARY KEY,
    ID_Cliente     INT NOT NULL REFERENCES escritura.Cliente(ID_Cliente),
    Fecha_Creacion TIMESTAMP NOT NULL DEFAULT now(),
    Estado         VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                   CHECK (Estado IN ('Pendiente','Confirmado','Enviado','Entregado','Cancelado')),
    Total          DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (Total >= 0)
);

CREATE TABLE escritura.ItemPedido (
    ID_Item         SERIAL PRIMARY KEY,
    ID_Pedido       INT NOT NULL REFERENCES escritura.Pedido(ID_Pedido) ON DELETE CASCADE,
    ID_Producto     INT NOT NULL REFERENCES escritura.Producto(ID_Producto),
    Cantidad        INT NOT NULL CHECK (Cantidad > 0),
    Precio_Unitario DECIMAL(10,2) NOT NULL CHECK (Precio_Unitario >= 0)
);
```

### 3. Modelo de lectura (Query Model)

Tabla desnormalizada: resuelve cada consulta sin JOINs. Los datos del cliente y la lista de productos se guardan embebidos.

```sql
CREATE TABLE lectura.PedidoResumen (
    ID_Pedido       INT PRIMARY KEY,
    Nombre_Cliente  VARCHAR(100) NOT NULL,   -- desnormalizado desde Cliente
    Email_Cliente   VARCHAR(100) NOT NULL,   -- desnormalizado desde Cliente
    Fecha_Creacion  TIMESTAMP NOT NULL,
    Estado          VARCHAR(20) NOT NULL,
    Total           DECIMAL(10,2) NOT NULL,
    Cantidad_Items  INT NOT NULL,            -- desnormalizado (COUNT de items)
    Productos       TEXT,                    -- desnormalizado (lista concatenada)
    ID_Cliente      INT NOT NULL             -- se mantiene para filtrar por cliente
);
```

**Justificación de la desnormalización:** cada consulta del query model toca una sola fila o un rango de `PedidoResumen` sin unir tablas. Guardar `Nombre_Cliente`/`Email_Cliente` evita el JOIN con `Cliente`; `Cantidad_Items` y `Productos` evitan agregar sobre `ItemPedido` en cada lectura. El costo es duplicación de datos y la necesidad de mantenerlos sincronizados (lo resolvemos en la Parte 2).

---

## Parte 2 — Comandos, sincronización y auditoría

### 4. Auditoría

```sql
CREATE TABLE escritura.AuditoriaComando (
    ID         SERIAL PRIMARY KEY,
    Comando    VARCHAR(50) NOT NULL,
    Payload    JSONB,
    Usuario    VARCHAR(100) NOT NULL DEFAULT current_user,
    Fecha      TIMESTAMP NOT NULL DEFAULT now()
);
```

### 5. Sincronización (síncrona)

Función única que reconstruye la fila de `PedidoResumen` a partir del estado actual del modelo de escritura. Se llama dentro de cada comando, en la misma transacción → **consistencia fuerte**.

```sql
CREATE OR REPLACE FUNCTION escritura.sync_resumen(p_id_pedido INT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO lectura.PedidoResumen AS r (
        ID_Pedido, Nombre_Cliente, Email_Cliente, Fecha_Creacion,
        Estado, Total, Cantidad_Items, Productos, ID_Cliente
    )
    SELECT
        p.ID_Pedido,
        c.Nombre,
        c.Email,
        p.Fecha_Creacion,
        p.Estado,
        p.Total,
        COALESCE(COUNT(i.ID_Item), 0),
        COALESCE(STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', '), ''),
        c.ID_Cliente
    FROM escritura.Pedido p
    JOIN escritura.Cliente c            ON c.ID_Cliente = p.ID_Cliente
    LEFT JOIN escritura.ItemPedido i    ON i.ID_Pedido = p.ID_Pedido
    LEFT JOIN escritura.Producto pr     ON pr.ID_Producto = i.ID_Producto
    WHERE p.ID_Pedido = p_id_pedido
    GROUP BY p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total, c.ID_Cliente
    ON CONFLICT (ID_Pedido) DO UPDATE SET
        Nombre_Cliente = EXCLUDED.Nombre_Cliente,
        Email_Cliente  = EXCLUDED.Email_Cliente,
        Fecha_Creacion = EXCLUDED.Fecha_Creacion,
        Estado         = EXCLUDED.Estado,
        Total          = EXCLUDED.Total,
        Cantidad_Items = EXCLUDED.Cantidad_Items,
        Productos      = EXCLUDED.Productos;
END;
$$ LANGUAGE plpgsql;
```

### 6. Comandos

Cada comando valida reglas de negocio, modifica el modelo de escritura, sincroniza el de lectura y registra auditoría — todo atómico.

```sql
-- CreatePedidoCommand: crea un pedido en estado Pendiente
CREATE OR REPLACE FUNCTION escritura.create_pedido(p_id_cliente INT)
RETURNS INT AS $$
DECLARE v_id_pedido INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM escritura.Cliente WHERE ID_Cliente = p_id_cliente) THEN
        RAISE EXCEPTION 'Cliente % inexistente', p_id_cliente;
    END IF;

    INSERT INTO escritura.Pedido (ID_Cliente) VALUES (p_id_cliente)
    RETURNING ID_Pedido INTO v_id_pedido;

    PERFORM escritura.sync_resumen(v_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('CreatePedido', jsonb_build_object('id_cliente', p_id_cliente, 'id_pedido', v_id_pedido));
    RETURN v_id_pedido;
END;
$$ LANGUAGE plpgsql;

-- AgregarItemCommand: agrega un ítem validando stock disponible
CREATE OR REPLACE FUNCTION escritura.agregar_item(p_id_pedido INT, p_id_producto INT, p_cantidad INT)
RETURNS VOID AS $$
DECLARE v_precio DECIMAL(10,2); v_stock INT; v_estado VARCHAR(20);
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;
    IF v_estado <> 'Pendiente' THEN
        RAISE EXCEPTION 'Solo se pueden agregar items a un pedido Pendiente (estado actual: %)', v_estado;
    END IF;

    SELECT Precio, Stock INTO v_precio, v_stock
    FROM escritura.Producto WHERE ID_Producto = p_id_producto;
    IF v_precio IS NULL THEN
        RAISE EXCEPTION 'Producto % inexistente', p_id_producto;
    END IF;
    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para producto % (disponible %, pedido %)', p_id_producto, v_stock, p_cantidad;
    END IF;

    INSERT INTO escritura.ItemPedido (ID_Pedido, ID_Producto, Cantidad, Precio_Unitario)
        VALUES (p_id_pedido, p_id_producto, p_cantidad, v_precio);

    -- recalcular total
    UPDATE escritura.Pedido SET Total = (
        SELECT COALESCE(SUM(Cantidad * Precio_Unitario), 0)
        FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido
    ) WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('AgregarItem', jsonb_build_object('id_pedido', p_id_pedido, 'id_producto', p_id_producto, 'cantidad', p_cantidad));
END;
$$ LANGUAGE plpgsql;

-- ConfirmarPedidoCommand: confirma y descuenta stock (atómico)
CREATE OR REPLACE FUNCTION escritura.confirmar_pedido(p_id_pedido INT)
RETURNS VOID AS $$
DECLARE v_estado VARCHAR(20); r RECORD;
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido FOR UPDATE;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;
    IF v_estado <> 'Pendiente' THEN
        RAISE EXCEPTION 'Solo se confirma un pedido Pendiente (estado actual: %)', v_estado;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido) THEN
        RAISE EXCEPTION 'No se puede confirmar un pedido sin items';
    END IF;

    -- validar stock de todos los items antes de descontar
    FOR r IN SELECT ID_Producto, SUM(Cantidad) AS cant
             FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido GROUP BY ID_Producto LOOP
        IF (SELECT Stock FROM escritura.Producto WHERE ID_Producto = r.ID_Producto) < r.cant THEN
            RAISE EXCEPTION 'Stock insuficiente al confirmar (producto %)', r.ID_Producto;
        END IF;
    END LOOP;

    -- descontar stock
    UPDATE escritura.Producto pr SET Stock = Stock - sub.cant
    FROM (SELECT ID_Producto, SUM(Cantidad) AS cant
          FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido GROUP BY ID_Producto) sub
    WHERE pr.ID_Producto = sub.ID_Producto;

    UPDATE escritura.Pedido SET Estado = 'Confirmado' WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('ConfirmarPedido', jsonb_build_object('id_pedido', p_id_pedido));
END;
$$ LANGUAGE plpgsql;

-- ActualizarEstadoCommand: valida la transición de estado
CREATE OR REPLACE FUNCTION escritura.actualizar_estado(p_id_pedido INT, p_nuevo_estado VARCHAR)
RETURNS VOID AS $$
DECLARE v_estado VARCHAR(20);
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;

    -- transiciones válidas
    IF NOT (
        (v_estado = 'Confirmado' AND p_nuevo_estado = 'Enviado')   OR
        (v_estado = 'Enviado'    AND p_nuevo_estado = 'Entregado')  OR
        (v_estado IN ('Pendiente','Confirmado') AND p_nuevo_estado = 'Cancelado')
    ) THEN
        RAISE EXCEPTION 'Transición inválida: % -> %', v_estado, p_nuevo_estado;
    END IF;

    UPDATE escritura.Pedido SET Estado = p_nuevo_estado WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('ActualizarEstado', jsonb_build_object('id_pedido', p_id_pedido, 'nuevo_estado', p_nuevo_estado));
END;
$$ LANGUAGE plpgsql;
```

> **Nota sobre la variante asíncrona:** en vez de llamar a `sync_resumen` dentro del comando, se puede insertar un evento en una cola y procesarlo con un job externo (`LISTEN/NOTIFY`). Eso da menor latencia de escritura a costa de consistencia eventual. La maquinaria está implementada en `sql/14_async_sync.sql` y se demuestra en la sección 13.

**Pruebas de las validaciones.** El camino feliz está en `sql/08_smoke_test.sql`. Para demostrar que los comandos **rechazan** las operaciones inválidas (lo que pide la Parte 2), `sql/15_pruebas_negativas.sql` ejecuta cada caso inválido y verifica que se dispare el error: cliente/producto/pedido inexistente, pedido no Pendiente, stock insuficiente (al agregar y al confirmar), pedido sin ítems, cantidad ≤ 0 y transición de estado inválida. Si alguna validación no salta, el script falla (sirve como gate).

---

## Parte 3 — Consultas e índices

### 7. Índices del modelo de lectura

```sql
CREATE INDEX idx_resumen_cliente ON lectura.PedidoResumen (ID_Cliente);
CREATE INDEX idx_resumen_estado  ON lectura.PedidoResumen (Estado);
CREATE INDEX idx_resumen_fecha   ON lectura.PedidoResumen (Fecha_Creacion);
-- para ObtenerTopProductos, índice sobre el modelo de escritura:
CREATE INDEX idx_item_producto   ON escritura.ItemPedido (ID_Producto);
```

### 8. Consultas

```sql
-- ObtenerPedidosPorCliente: todos los pedidos de un cliente (sin JOINs)
CREATE OR REPLACE FUNCTION lectura.obtener_pedidos_por_cliente(p_id_cliente INT)
RETURNS SETOF lectura.PedidoResumen AS $$
    SELECT * FROM lectura.PedidoResumen
    WHERE ID_Cliente = p_id_cliente
    ORDER BY Fecha_Creacion DESC;
$$ LANGUAGE sql;

-- ObtenerResumenPedido: detalle completo en una sola consulta
CREATE OR REPLACE FUNCTION lectura.obtener_resumen_pedido(p_id_pedido INT)
RETURNS lectura.PedidoResumen AS $$
    SELECT * FROM lectura.PedidoResumen WHERE ID_Pedido = p_id_pedido;
$$ LANGUAGE sql;

-- ObtenerEstadoEnvio: proyección mínima (solo el estado)
CREATE OR REPLACE FUNCTION lectura.obtener_estado_envio(p_id_pedido INT)
RETURNS VARCHAR AS $$
    SELECT Estado FROM lectura.PedidoResumen WHERE ID_Pedido = p_id_pedido;
$$ LANGUAGE sql;

-- ObtenerTopProductos: productos más vendidos en un período
CREATE OR REPLACE FUNCTION lectura.obtener_top_productos(p_desde TIMESTAMP, p_hasta TIMESTAMP, p_limite INT DEFAULT 10)
RETURNS TABLE (ID_Producto INT, Nombre VARCHAR, Unidades BIGINT) AS $$
    SELECT pr.ID_Producto, pr.Nombre, SUM(i.Cantidad) AS unidades
    FROM escritura.ItemPedido i
    JOIN escritura.Pedido p   ON p.ID_Pedido = i.ID_Pedido
    JOIN escritura.Producto pr ON pr.ID_Producto = i.ID_Producto
    WHERE p.Fecha_Creacion BETWEEN p_desde AND p_hasta
      AND p.Estado IN ('Confirmado','Enviado','Entregado')
    GROUP BY pr.ID_Producto, pr.Nombre
    ORDER BY unidades DESC
    LIMIT p_limite;
$$ LANGUAGE sql;
```

---

## Ejemplo de uso (smoke test)

```sql
-- datos base
INSERT INTO escritura.Cliente (Nombre, Email) VALUES
    ('Ana Gomez', 'ana@mail.com'), ('Luis Paz', 'luis@mail.com');
INSERT INTO escritura.Producto (Nombre, Precio, Stock) VALUES
    ('Teclado', 15000.00, 10), ('Mouse', 8000.00, 5), ('Monitor', 90000.00, 3);

-- flujo de comandos
SELECT escritura.create_pedido(1);          -- -> pedido 1
SELECT escritura.agregar_item(1, 1, 2);     -- 2 teclados
SELECT escritura.agregar_item(1, 2, 1);     -- 1 mouse
SELECT escritura.confirmar_pedido(1);       -- descuenta stock
SELECT escritura.actualizar_estado(1, 'Enviado');

-- consultas sobre el modelo de lectura
SELECT * FROM lectura.obtener_resumen_pedido(1);
SELECT * FROM lectura.obtener_pedidos_por_cliente(1);
SELECT lectura.obtener_estado_envio(1);
SELECT * FROM lectura.obtener_top_productos(
    (now() - interval '1 day')::timestamp,
    (now() + interval '1 day')::timestamp
);
```

---

## Parte 4 — Análisis y comparación

La idea es comparar el enfoque **CQRS** (lectura sobre `lectura.PedidoResumen`, desnormalizado) contra un enfoque **CRUD tradicional** (las mismas consultas resueltas con JOINs sobre el modelo normalizado), usando el mismo conjunto de datos. Todo el SQL de abajo es ejecutable; los números concretos los completás al correrlo en tu Postgres (cada equipo obtendrá tiempos algo distintos según hardware).

### 9. Esquema CRUD de referencia

El CRUD reutiliza las mismas tablas normalizadas de `escritura`, pero **no tiene modelo de lectura**: cada consulta se resuelve con JOINs en el momento. Para no duplicar tablas, definimos las consultas CRUD como funciones que leen directamente del modelo normalizado.

```sql
-- CRUD: pedidos por cliente resueltos con JOINs + agregación en cada lectura
CREATE OR REPLACE FUNCTION escritura.crud_pedidos_por_cliente(p_id_cliente INT)
RETURNS TABLE (ID_Pedido INT, Nombre_Cliente VARCHAR, Estado VARCHAR,
               Total DECIMAL, Cantidad_Items BIGINT, Productos TEXT) AS $$
    SELECT p.ID_Pedido, c.Nombre, p.Estado, p.Total,
           COUNT(i.ID_Item),
           STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
    FROM escritura.Pedido p
    JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
    LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
    LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
    WHERE p.ID_Cliente = p_id_cliente
    GROUP BY p.ID_Pedido, c.Nombre, p.Estado, p.Total
    ORDER BY p.ID_Pedido DESC;
$$ LANGUAGE sql;
```

La consulta CQRS equivalente (`lectura.obtener_pedidos_por_cliente`) hace un simple `SELECT ... WHERE ID_Cliente = ?` sin JOINs ni `GROUP BY`, porque ese trabajo ya se hizo una vez al sincronizar.

### 10. Generación de un dataset grande

`generate_series` para poblar el modelo de escritura y luego sincronizar el de lectura en masa.

```sql
-- 1.000 clientes
INSERT INTO escritura.Cliente (Nombre, Email)
SELECT 'Cliente ' || g, 'cliente' || g || '@mail.com'
FROM generate_series(1, 1000) g;

-- 200 productos con stock alto para no quedarnos sin stock
INSERT INTO escritura.Producto (Nombre, Precio, Stock)
SELECT 'Producto ' || g, (random()*100000)::numeric(10,2), 1000000
FROM generate_series(1, 200) g;

-- 50.000 pedidos repartidos entre los clientes
INSERT INTO escritura.Pedido (ID_Cliente, Fecha_Creacion, Estado, Total)
SELECT (random()*999 + 1)::int,
       now() - (random()*365 || ' days')::interval,
       'Confirmado', 0
FROM generate_series(1, 50000);

-- ~3 items por pedido (150.000 items)
INSERT INTO escritura.ItemPedido (ID_Pedido, ID_Producto, Cantidad, Precio_Unitario)
SELECT p.ID_Pedido,
       (random()*199 + 1)::int,
       (random()*5 + 1)::int,
       (random()*100000)::numeric(10,2)
FROM escritura.Pedido p, generate_series(1, 3);

-- recalcular totales del modelo de escritura
UPDATE escritura.Pedido p SET Total = sub.t
FROM (SELECT ID_Pedido, SUM(Cantidad*Precio_Unitario) t
      FROM escritura.ItemPedido GROUP BY ID_Pedido) sub
WHERE p.ID_Pedido = sub.ID_Pedido;

-- poblar el modelo de lectura en masa (equivale a sincronizar todo)
INSERT INTO lectura.PedidoResumen
SELECT p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total,
       COUNT(i.ID_Item),
       STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', '),
       c.ID_Cliente
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
GROUP BY p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total, c.ID_Cliente
ON CONFLICT (ID_Pedido) DO NOTHING;

-- poblar el resumen de ventas usado por la consulta CQRS de top productos
SELECT lectura.sync_ventas();

ANALYZE;  -- actualizar estadísticas del planner antes de medir
```

### 11. Benchmark de lectura (CQRS vs CRUD)

Medimos el `SELECT` directo (el cuerpo de cada función) y no la función envoltorio: las
funciones son `LANGUAGE sql` **VOLATILE**, no se *inlinean* y el `EXPLAIN` las muestra como
un `Function Scan` opaco que esconde el plan real (no se vería el índice). El set completo de
las 4 consultas está en `sql/11_benchmark.sql`; acá el ejemplo de *pedidos por cliente*:

```sql
-- CQRS: lectura desnormalizada, sin JOINs (cuerpo de obtener_pedidos_por_cliente)
EXPLAIN SELECT * FROM lectura.PedidoResumen
WHERE ID_Cliente = 42 ORDER BY Fecha_Creacion DESC;

-- CRUD: misma respuesta con JOINs + GROUP BY en tiempo de lectura
EXPLAIN SELECT p.ID_Pedido, c.Nombre, p.Estado, p.Total,
       COUNT(i.ID_Item), STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
WHERE p.ID_Cliente = 42
GROUP BY p.ID_Pedido, c.Nombre, p.Estado, p.Total
ORDER BY p.ID_Pedido DESC;
```

Qué observar en cada plan:

- **CQRS** usa `idx_resumen_cliente` → *Index Scan* sobre `PedidoResumen` y devuelve filas ya armadas. Sin nodos de *Hash Join* ni *Aggregate*.
- **CRUD** necesita un *Index Scan* sobre `Pedido` + dos *Joins* (`Cliente`, `ItemPedido`, `Producto`) + un *GroupAggregate*. Más nodos y más trabajo por lectura; el tiempo real se toma con `\timing`.

El tiempo sale de `\timing` y los nodos del `EXPLAIN` sin `ANALYZE`. Mediciones tomadas en
PostgreSQL 16 (Docker), dataset de 50.000 pedidos / 150.000 ítems, 2da corrida con cache
caliente. Los valores absolutos dependen del hardware; lo importante es la **relación
CQRS/CRUD**, que se mantiene entre corridas.

| Consulta | Enfoque | Tiempo wall-clock (ms) | Nodos del plan |
|---|---|---|---|
| Pedidos por cliente | CQRS  | **2,01** | Bitmap Index Scan (idx_resumen_cliente) + Sort |
| Pedidos por cliente | CRUD  | **5,29** | Index Scan (Pedido) + joins + GroupAggregate |
| Resumen de un pedido | CQRS  | **0,48** | Index Scan (PK PedidoResumen) |
| Resumen de un pedido | CRUD  | **1,29** | Index Scan (PK Pedido) + joins + GroupAggregate |
| Estado de envío | CQRS  | **0,53** | Index Scan (PK PedidoResumen) |
| Estado de envío | CRUD  | **0,64** | Index Scan (PK Pedido) |
| Top productos | CQRS  | **0,44** | Limit + Index Scan (idx_ventas_unidades) sobre ResumenVentas |
| Top productos | CRUD  | **54,24** | Hash Joins + HashAggregate + Sort sobre 150k ítems |

**Lectura de los resultados:**

- En las consultas con **agregación pesada** la diferencia es enorme: *Top productos* es ~**123×** más rápida en CQRS (0,44 vs 54,24 ms), porque el CRUD debe recorrer y agrupar los 150.000 ítems en cada lectura, mientras que CQRS lee una tabla ya agregada (`ResumenVentas`).
- En consultas con **JOINs moderados** (*pedidos por cliente*, *resumen de pedido*) la ventaja es real pero más modesta: ~**2,6×**. Se evita el `GroupAggregate` y los joins, pero el CRUD bien indexado tampoco es lento.
- En la **proyección mínima** (*estado de envío*) prácticamente **empatan** (0,53 vs 0,64 ms): el estado vive directo en `Pedido`, sin joins ni agregación, así que ahí CQRS **no aporta** nada. Es un buen recordatorio de que CQRS rinde donde hay trabajo que pre-calcular, no en todo.

### 12. Costo de escritura

El otro lado del trade-off: cada comando CQRS hace trabajo extra (sincronizar `PedidoResumen`). Para medirlo:

```sql
-- Se mide dentro de transacciones que se revierten para no cambiar el dataset.
-- escritura CQRS: el comando crea el pedido Y sincroniza el resumen
BEGIN;
\timing on
SELECT escritura.create_pedido(42);
\timing off
ROLLBACK;

-- escritura CRUD pura: solo el INSERT normalizado, sin sincronización
BEGIN;
\timing on
INSERT INTO escritura.Pedido (ID_Cliente) VALUES (42);
\timing off
ROLLBACK;
```

Mediciones (mismo entorno que la tabla anterior):

| Escritura | Tiempo (ms) | Qué hace |
|---|---|---|
| CQRS (`create_pedido`) | **5,02** | INSERT del pedido + `sync_resumen` (reconstruye la fila de `PedidoResumen`) + auditoría |
| CRUD (`INSERT` puro) | **0,70** | solo el INSERT normalizado |

La escritura CQRS es ~**7× más lenta** porque mantiene el modelo de lectura al día en la misma transacción. Es el precio de tener lecturas baratas: se traslada el trabajo de las muchas lecturas a las pocas escrituras. El número absoluto es chico (5 ms) y, dado que en este dominio las escrituras son esporádicas, el trade-off conviene.

### 13. Consistencia eventual

En la variante **síncrona** que implementamos, no hay ventana de inconsistencia: el resumen se actualiza en la misma transacción que el comando, así que cualquier lectura posterior ve el dato correcto.

Si se usara la variante **asíncrona** (sincronización por trigger diferido o job), existiría una ventana entre la escritura y la propagación: un usuario podría confirmar un pedido y, por unos milisegundos/segundos, seguir viendo el estado anterior en la vista de lectura. Para gestión de pedidos suele ser aceptable (el cliente tolera ver "Pendiente" un instante más), pero no lo sería para datos donde la lectura inmediata es crítica (ej. saldo disponible antes de un pago).

Esta ventana se puede **ver ejecutándola**: `sql/16_demo_consistencia_eventual.sql` (sobre la cola de `14_async_sync.sql`) hace un cambio en el modelo de escritura, lo **encola** en vez de sincronizar, y muestra los dos modelos lado a lado: la lectura queda atrasada (`escritura=Entregado` / `lectura=Enviado`) hasta que `procesar_cola_sync()` propaga el cambio y vuelven a coincidir. El camino síncrono, en cambio, coincide al instante.

### 14. Cuándo CQRS agrega complejidad innecesaria

CQRS conviene cuando las **lecturas dominan** sobre las escrituras, las consultas son costosas (muchos JOINs/agregaciones) y se tolera latencia o eventualidad en la escritura. Agrega complejidad innecesaria cuando:

- El volumen es bajo y un modelo CRUD con buenos índices ya responde rápido.
- El dominio es simple (pocas tablas, consultas triviales): mantener dos modelos sincronizados es más código y más superficie de bugs sin beneficio medible.
- El equipo es chico o el proyecto es de corta vida: el costo de mantenimiento supera la ganancia de rendimiento.

### 15. Conclusión grupal

CQRS no es "mejor" de forma absoluta: es una **decisión de trade-off**. Mueve trabajo de la lectura (frecuente) a la escritura (infrecuente) y, opcionalmente, cambia consistencia fuerte por menor latencia de escritura. En este caso de estudio —pedidos en línea con muchas lecturas (listados, estados, reportes) y escrituras esporádicas pero críticas— el patrón encaja bien: las consultas se vuelven simples y rápidas, y la integridad transaccional se conserva en el modelo de escritura. En sistemas de bajo volumen o dominios simples, en cambio, la separación de modelos introduce complejidad (sincronización, duplicación, posible inconsistencia) que no se justifica frente a un CRUD bien indexado.
