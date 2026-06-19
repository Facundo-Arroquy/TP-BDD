-- Benchmark de lectura CQRS vs CRUD (EXPLAIN ANALYZE)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

-- CQRS: lectura desnormalizada, sin JOINs
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM lectura.obtener_pedidos_por_cliente(42);

-- CRUD: misma respuesta con JOINs + GROUP BY en tiempo de lectura
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM escritura.crud_pedidos_por_cliente(42);

\timing on
-- escritura CQRS: el comando crea el pedido Y sincroniza el resumen
SELECT escritura.create_pedido(42);
-- escritura CRUD pura: solo el INSERT normalizado, sin sincronización
INSERT INTO escritura.Pedido (ID_Cliente) VALUES (42);
