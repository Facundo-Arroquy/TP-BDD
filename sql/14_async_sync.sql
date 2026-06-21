-- Sincronización asíncrona con LISTEN/NOTIFY
-- TP Base de Datos - CQRS
-- Variante de consistencia eventual para la Parte 4

-- 1. Tabla de eventos pendientes de sincronización
CREATE TABLE escritura.ColaSync (
    ID           SERIAL PRIMARY KEY,
    ID_Pedido    INT NOT NULL,
    Creado_en    TIMESTAMP NOT NULL DEFAULT now(),
    Procesado_en TIMESTAMP
);

CREATE INDEX idx_cola_no_procesado ON escritura.ColaSync (Procesado_en) WHERE Procesado_en IS NULL;

-- 2. En lugar de llamar sync_resumen() directo, insertamos un evento y notificamos
CREATE OR REPLACE FUNCTION escritura.encolar_sync(p_id_pedido INT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO escritura.ColaSync (ID_Pedido) VALUES (p_id_pedido);
    PERFORM pg_notify('canal_sync', p_id_pedido::TEXT);
END;
$$ LANGUAGE plpgsql;

-- 3. Procesador de la cola (se llama desde el worker o a demanda)
CREATE OR REPLACE FUNCTION escritura.procesar_cola_sync(p_limite INT DEFAULT 10)
RETURNS INT AS $$
DECLARE v_count INT := 0; r RECORD;
BEGIN
    FOR r IN SELECT ID, ID_Pedido
             FROM escritura.ColaSync
             WHERE Procesado_en IS NULL
             ORDER BY ID ASC
             LIMIT p_limite
             FOR UPDATE SKIP LOCKED
    LOOP
        PERFORM escritura.sync_resumen(r.ID_Pedido);
        UPDATE escritura.ColaSync SET Procesado_en = now() WHERE ID = r.ID;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 4. Función para usar en comandos (versión async):
--    reemplazar PERFORM escritura.sync_resumen(id) por
--    PERFORM escritura.encolar_sync(id)  para tener consistencia eventual.

-- 5. Función NOTIFY que escucha (para usar con `LISTEN`)
--    En un worker Python/psycopg:
--      conn.execute("LISTEN canal_sync")
--      while True:
--          conn.wait()
--          conn.execute("SELECT escritura.procesar_cola_sync()")

-- Nota: para cambiar un comando a async, editar 05_commands.sql:
--   PERFORM escritura.sync_resumen(v_id_pedido)  →  PERFORM escritura.encolar_sync(v_id_pedido)
