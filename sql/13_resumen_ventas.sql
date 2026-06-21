-- Modelo de lectura para top productos (ResumenVentas)
-- TP Base de Datos - CQRS
-- Resuelve ObtenerTopProductos sin JOINs sobre el modelo de escritura

CREATE TABLE lectura.ResumenVentas (
    ID_Producto     INT PRIMARY KEY,
    Nombre_Producto VARCHAR(100) NOT NULL,
    Unidades_Vendidas BIGINT NOT NULL DEFAULT 0,
    Ultima_Actualizacion TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_ventas_unidades ON lectura.ResumenVentas (Unidades_Vendidas DESC);

-- función de sincronización: recalcula ventas de todos los productos
CREATE OR REPLACE FUNCTION lectura.sync_ventas()
RETURNS VOID AS $$
BEGIN
    INSERT INTO lectura.ResumenVentas (ID_Producto, Nombre_Producto, Unidades_Vendidas, Ultima_Actualizacion)
    SELECT pr.ID_Producto, pr.Nombre, COALESCE(SUM(i.Cantidad), 0), now()
    FROM escritura.Producto pr
    LEFT JOIN escritura.ItemPedido i ON i.ID_Producto = pr.ID_Producto
    LEFT JOIN escritura.Pedido p ON p.ID_Pedido = i.ID_Pedido
        AND p.Estado IN ('Confirmado', 'Enviado', 'Entregado')
    GROUP BY pr.ID_Producto, pr.Nombre
    ON CONFLICT (ID_Producto) DO UPDATE SET
        Nombre_Producto     = EXCLUDED.Nombre_Producto,
        Unidades_Vendidas   = EXCLUDED.Unidades_Vendidas,
        Ultima_Actualizacion = now();
END;
$$ LANGUAGE plpgsql;

-- opcional: sync automática cada vez que se confirma un pedido (trigger)
CREATE OR REPLACE FUNCTION escritura.trigger_sync_ventas()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Estado = 'Confirmado' AND (OLD.Estado IS NULL OR OLD.Estado = 'Pendiente') THEN
        PERFORM lectura.sync_ventas();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_ventas
    AFTER UPDATE OF Estado ON escritura.Pedido
    FOR EACH ROW
    EXECUTE FUNCTION escritura.trigger_sync_ventas();

-- consulta de top productos sobre el modelo de lectura (sin JOINs en tiempo real)
CREATE OR REPLACE FUNCTION lectura.obtener_top_productos(p_desde TIMESTAMP, p_hasta TIMESTAMP, p_limite INT DEFAULT 10)
RETURNS TABLE (ID_Producto INT, Nombre VARCHAR, Unidades BIGINT) AS $$
    SELECT rv.ID_Producto, rv.Nombre_Producto, rv.Unidades_Vendidas
    FROM lectura.ResumenVentas rv
    ORDER BY rv.Unidades_Vendidas DESC
    LIMIT p_limite;
$$ LANGUAGE sql;
