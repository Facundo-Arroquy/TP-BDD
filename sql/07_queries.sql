-- Consultas sobre el modelo de lectura
-- TP Base de Datos - CQRS. Generado desde resolucion.md

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
