-- Indices del modelo de lectura
-- TP Base de Datos - CQRS. Generado desde resolucion.md

CREATE INDEX idx_resumen_cliente ON lectura.PedidoResumen (ID_Cliente);
CREATE INDEX idx_resumen_estado  ON lectura.PedidoResumen (Estado);
CREATE INDEX idx_resumen_fecha   ON lectura.PedidoResumen (Fecha_Creacion);
-- para ObtenerTopProductos, índice sobre el modelo de escritura:
CREATE INDEX idx_item_producto   ON escritura.ItemPedido (ID_Producto);
