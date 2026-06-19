-- Comandos (procedimientos almacenados)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

-- CreatePedidoCommand: crea un pedido en estado Pendiente
CREATE OR REPLACE FUNCTION escritura.create_pedido(p_id_cliente INT)
RETURNS INT AS $$
DECLARE v_id_pedido INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM escritura.Cliente WHERE ID_Cliente = p_id_cliente) THEN
        RAISE EXCEPTION 'Cliente % inexistente', p_id_cliente;
    END IF;

    INSERT INTO escritura.Pedido (ID_Cliente) VALUES (p_id_cliente)
    RETURNING ID_Pedido INTO v_id_pedido;

    PERFORM escritura.sync_resumen(v_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('CreatePedido', jsonb_build_object('id_cliente', p_id_cliente, 'id_pedido', v_id_pedido));
    RETURN v_id_pedido;
END;
$$ LANGUAGE plpgsql;

-- AgregarItemCommand: agrega un ítem validando stock disponible
CREATE OR REPLACE FUNCTION escritura.agregar_item(p_id_pedido INT, p_id_producto INT, p_cantidad INT)
RETURNS VOID AS $$
DECLARE v_precio DECIMAL(10,2); v_stock INT; v_estado VARCHAR(20);
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;
    IF v_estado <> 'Pendiente' THEN
        RAISE EXCEPTION 'Solo se pueden agregar items a un pedido Pendiente (estado actual: %)', v_estado;
    END IF;

    SELECT Precio, Stock INTO v_precio, v_stock
    FROM escritura.Producto WHERE ID_Producto = p_id_producto;
    IF v_precio IS NULL THEN
        RAISE EXCEPTION 'Producto % inexistente', p_id_producto;
    END IF;
    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para producto % (disponible %, pedido %)', p_id_producto, v_stock, p_cantidad;
    END IF;

    INSERT INTO escritura.ItemPedido (ID_Pedido, ID_Producto, Cantidad, Precio_Unitario)
        VALUES (p_id_pedido, p_id_producto, p_cantidad, v_precio);

    -- recalcular total
    UPDATE escritura.Pedido SET Total = (
        SELECT COALESCE(SUM(Cantidad * Precio_Unitario), 0)
        FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido
    ) WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('AgregarItem', jsonb_build_object('id_pedido', p_id_pedido, 'id_producto', p_id_producto, 'cantidad', p_cantidad));
END;
$$ LANGUAGE plpgsql;

-- ConfirmarPedidoCommand: confirma y descuenta stock (atómico)
CREATE OR REPLACE FUNCTION escritura.confirmar_pedido(p_id_pedido INT)
RETURNS VOID AS $$
DECLARE v_estado VARCHAR(20); r RECORD;
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido FOR UPDATE;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;
    IF v_estado <> 'Pendiente' THEN
        RAISE EXCEPTION 'Solo se confirma un pedido Pendiente (estado actual: %)', v_estado;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido) THEN
        RAISE EXCEPTION 'No se puede confirmar un pedido sin items';
    END IF;

    -- validar stock de todos los items antes de descontar
    FOR r IN SELECT ID_Producto, SUM(Cantidad) AS cant
             FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido GROUP BY ID_Producto LOOP
        IF (SELECT Stock FROM escritura.Producto WHERE ID_Producto = r.ID_Producto) < r.cant THEN
            RAISE EXCEPTION 'Stock insuficiente al confirmar (producto %)', r.ID_Producto;
        END IF;
    END LOOP;

    -- descontar stock
    UPDATE escritura.Producto pr SET Stock = Stock - sub.cant
    FROM (SELECT ID_Producto, SUM(Cantidad) AS cant
          FROM escritura.ItemPedido WHERE ID_Pedido = p_id_pedido GROUP BY ID_Producto) sub
    WHERE pr.ID_Producto = sub.ID_Producto;

    UPDATE escritura.Pedido SET Estado = 'Confirmado' WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('ConfirmarPedido', jsonb_build_object('id_pedido', p_id_pedido));
END;
$$ LANGUAGE plpgsql;

-- ActualizarEstadoCommand: valida la transición de estado
CREATE OR REPLACE FUNCTION escritura.actualizar_estado(p_id_pedido INT, p_nuevo_estado VARCHAR)
RETURNS VOID AS $$
DECLARE v_estado VARCHAR(20);
BEGIN
    SELECT Estado INTO v_estado FROM escritura.Pedido WHERE ID_Pedido = p_id_pedido;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'Pedido % inexistente', p_id_pedido;
    END IF;

    -- transiciones válidas
    IF NOT (
        (v_estado = 'Confirmado' AND p_nuevo_estado = 'Enviado')   OR
        (v_estado = 'Enviado'    AND p_nuevo_estado = 'Entregado')  OR
        (v_estado IN ('Pendiente','Confirmado') AND p_nuevo_estado = 'Cancelado')
    ) THEN
        RAISE EXCEPTION 'Transición inválida: % -> %', v_estado, p_nuevo_estado;
    END IF;

    UPDATE escritura.Pedido SET Estado = p_nuevo_estado WHERE ID_Pedido = p_id_pedido;

    PERFORM escritura.sync_resumen(p_id_pedido);
    INSERT INTO escritura.AuditoriaComando (Comando, Payload)
        VALUES ('ActualizarEstado', jsonb_build_object('id_pedido', p_id_pedido, 'nuevo_estado', p_nuevo_estado));
END;
$$ LANGUAGE plpgsql;
