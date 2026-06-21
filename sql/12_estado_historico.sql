-- Historial de cambios de estado de pedidos
-- TP Base de Datos - CQRS

CREATE TABLE escritura.EstadoHistorico (
    ID          SERIAL PRIMARY KEY,
    ID_Pedido   INT NOT NULL REFERENCES escritura.Pedido(ID_Pedido) ON DELETE CASCADE,
    Estado      VARCHAR(20) NOT NULL,
    Cambio_por  VARCHAR(100) NOT NULL DEFAULT current_user,
    Fecha       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_historico_pedido ON escritura.EstadoHistorico (ID_Pedido);
CREATE INDEX idx_historico_fecha  ON escritura.EstadoHistorico (Fecha);

-- función para registrar cambio de estado
CREATE OR REPLACE FUNCTION escritura.registrar_cambio_estado()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.Estado IS DISTINCT FROM NEW.Estado THEN
        INSERT INTO escritura.EstadoHistorico (ID_Pedido, Estado)
        VALUES (NEW.ID_Pedido, NEW.Estado);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger sobre Pedido
CREATE TRIGGER trg_estado_historico
    AFTER UPDATE OF Estado ON escritura.Pedido
    FOR EACH ROW
    EXECUTE FUNCTION escritura.registrar_cambio_estado();

-- función de consulta del historial
CREATE OR REPLACE FUNCTION lectura.obtener_historial_estado(p_id_pedido INT)
RETURNS TABLE (Estado VARCHAR, Fecha TIMESTAMP) AS $$
    SELECT eh.Estado, eh.Fecha
    FROM escritura.EstadoHistorico eh
    WHERE eh.ID_Pedido = p_id_pedido
    ORDER BY eh.Fecha ASC;
$$ LANGUAGE sql;
