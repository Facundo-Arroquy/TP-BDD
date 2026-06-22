-- Dataset grande para benchmark (generate_series)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

SELECT setseed(0.5);  -- semilla fija para datos reproducibles

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
