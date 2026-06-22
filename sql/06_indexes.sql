-- Indices del modelo de lectura
-- TP Base de Datos - CQRS. Generado desde resolucion.md

CREATE INDEX idx_resumen_cliente ON lectura.PedidoResumen (ID_Cliente);
CREATE INDEX idx_resumen_estado  ON lectura.PedidoResumen (Estado);
CREATE INDEX idx_resumen_fecha   ON lectura.PedidoResumen (Fecha_Creacion);
-- para ObtenerTopProductos, índice sobre el modelo de escritura:
CREATE INDEX idx_item_producto   ON escritura.ItemPedido (ID_Producto);
-- índice sobre la FK ItemPedido(ID_Pedido): lo usan los comandos (recalcular total,
-- confirmar, sync_resumen) y el CRUD de referencia al unir Pedido <-> ItemPedido.
CREATE INDEX idx_item_pedido     ON escritura.ItemPedido (ID_Pedido);
