-- Sincronizacion sincrona write -> read
-- TP Base de Datos - CQRS. Generado desde resolucion.md

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
