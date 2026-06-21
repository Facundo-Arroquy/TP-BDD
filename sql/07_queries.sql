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

-- Nota: ObtenerTopProductos se movió a 13_resumen_ventas.sql
-- para mantener la separación CQRS (lectura sobre modelo desnormalizado).
