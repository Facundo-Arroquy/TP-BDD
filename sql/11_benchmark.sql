-- Benchmark de lectura CQRS vs CRUD
-- TP Base de Datos - CQRS. Parte 4.
--
-- Mide las 4 consultas del enunciado en sus dos variantes:
--   CQRS  -> lee el modelo de lectura desnormalizado (sin JOINs)
--   CRUD  -> resuelve la misma respuesta con JOINs/agregación sobre el modelo normalizado
--
-- Medimos los SELECT directos (no las funciones envoltorio): las funciones son
-- LANGUAGE sql VOLATILE, no se inlinean y aparecen como "Function Scan" opaco,
-- ocultando el plan real. El SELECT de abajo es el cuerpo de cada función.
--
-- Para evitar que el overhead de instrumentacion por fila de EXPLAIN ANALYZE
-- infle los tiempos en Docker, usamos:
--   EXPLAIN  -> estructura del plan
--   \timing  -> wall-clock de la consulta real
--
-- Tip: correr el archivo dos veces y quedarse con la 2da pasada (cache caliente)
-- para que los tiempos no incluyan el costo de leer de disco la primera vez.

\echo '==================== Q1: Pedidos por cliente ===================='
\echo '--- CQRS (modelo de lectura, sin JOINs) ---'
EXPLAIN
SELECT * FROM lectura.PedidoResumen
WHERE ID_Cliente = 42
ORDER BY Fecha_Creacion DESC;
\timing on
SELECT * FROM lectura.PedidoResumen
WHERE ID_Cliente = 42
ORDER BY Fecha_Creacion DESC;
\timing off

\echo '--- CRUD (JOINs + GROUP BY en tiempo de lectura) ---'
EXPLAIN
SELECT p.ID_Pedido, c.Nombre, p.Estado, p.Total,
       COUNT(i.ID_Item),
       STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
WHERE p.ID_Cliente = 42
GROUP BY p.ID_Pedido, c.Nombre, p.Estado, p.Total
ORDER BY p.ID_Pedido DESC;
\timing on
SELECT p.ID_Pedido, c.Nombre, p.Estado, p.Total,
       COUNT(i.ID_Item),
       STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
WHERE p.ID_Cliente = 42
GROUP BY p.ID_Pedido, c.Nombre, p.Estado, p.Total
ORDER BY p.ID_Pedido DESC;
\timing off

\echo '==================== Q2: Resumen de un pedido ===================='
\echo '--- CQRS (PK sobre PedidoResumen) ---'
EXPLAIN
SELECT * FROM lectura.PedidoResumen WHERE ID_Pedido = 25000;
\timing on
SELECT * FROM lectura.PedidoResumen WHERE ID_Pedido = 25000;
\timing off

\echo '--- CRUD (JOINs + GROUP BY) ---'
EXPLAIN
SELECT p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total,
       COUNT(i.ID_Item),
       STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
WHERE p.ID_Pedido = 25000
GROUP BY p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total;
\timing on
SELECT p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total,
       COUNT(i.ID_Item),
       STRING_AGG(pr.Nombre || ' x' || i.Cantidad, ', ')
FROM escritura.Pedido p
JOIN escritura.Cliente c         ON c.ID_Cliente = p.ID_Cliente
LEFT JOIN escritura.ItemPedido i ON i.ID_Pedido = p.ID_Pedido
LEFT JOIN escritura.Producto pr  ON pr.ID_Producto = i.ID_Producto
WHERE p.ID_Pedido = 25000
GROUP BY p.ID_Pedido, c.Nombre, c.Email, p.Fecha_Creacion, p.Estado, p.Total;
\timing off

\echo '==================== Q3: Estado de envio ===================='
\echo '--- CQRS (proyeccion minima sobre PedidoResumen) ---'
EXPLAIN
SELECT Estado FROM lectura.PedidoResumen WHERE ID_Pedido = 25000;
\timing on
SELECT Estado FROM lectura.PedidoResumen WHERE ID_Pedido = 25000;
\timing off

\echo '--- CRUD (el estado vive en Pedido, tambien es PK lookup) ---'
EXPLAIN
SELECT Estado FROM escritura.Pedido WHERE ID_Pedido = 25000;
\timing on
SELECT Estado FROM escritura.Pedido WHERE ID_Pedido = 25000;
\timing off

\echo '==================== Q4: Top productos ===================='
\echo '--- CQRS (modelo de lectura ResumenVentas, ya agregado) ---'
EXPLAIN
SELECT ID_Producto, Nombre_Producto, Unidades_Vendidas
FROM lectura.ResumenVentas
ORDER BY Unidades_Vendidas DESC
LIMIT 10;
\timing on
SELECT ID_Producto, Nombre_Producto, Unidades_Vendidas
FROM lectura.ResumenVentas
ORDER BY Unidades_Vendidas DESC
LIMIT 10;
\timing off

\echo '--- CRUD (JOINs + SUM + GROUP BY sobre el modelo normalizado) ---'
EXPLAIN
SELECT pr.ID_Producto, pr.Nombre, SUM(i.Cantidad) AS unidades
FROM escritura.ItemPedido i
JOIN escritura.Pedido p    ON p.ID_Pedido = i.ID_Pedido
JOIN escritura.Producto pr ON pr.ID_Producto = i.ID_Producto
WHERE p.Estado IN ('Confirmado','Enviado','Entregado')
GROUP BY pr.ID_Producto, pr.Nombre
ORDER BY unidades DESC
LIMIT 10;
\timing on
SELECT pr.ID_Producto, pr.Nombre, SUM(i.Cantidad) AS unidades
FROM escritura.ItemPedido i
JOIN escritura.Pedido p    ON p.ID_Pedido = i.ID_Pedido
JOIN escritura.Producto pr ON pr.ID_Producto = i.ID_Producto
WHERE p.Estado IN ('Confirmado','Enviado','Entregado')
GROUP BY pr.ID_Producto, pr.Nombre
ORDER BY unidades DESC
LIMIT 10;
\timing off

\echo '==================== Costo de escritura (CQRS vs CRUD) ===================='
-- Se mide dentro de transacciones que se revierten para que el benchmark
-- pueda correrse varias veces sin cambiar el dataset.
-- escritura CQRS: el comando crea el pedido Y sincroniza el resumen
BEGIN;
\timing on
SELECT escritura.create_pedido(42);
\timing off
ROLLBACK;

-- escritura CRUD pura: solo el INSERT normalizado, sin sincronizacion
BEGIN;
\timing on
INSERT INTO escritura.Pedido (ID_Cliente) VALUES (42);
\timing off
ROLLBACK;
