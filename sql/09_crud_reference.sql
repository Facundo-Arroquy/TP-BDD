-- Esquema CRUD de referencia (lectura con JOINs)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

-- Índice necesario para que la comparación CRUD sea justa
CREATE INDEX IF NOT EXISTS idx_pedido_cliente ON escritura.Pedido (ID_Cliente);

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
