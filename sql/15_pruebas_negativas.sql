-- Pruebas negativas: demuestran que los comandos RECHAZAN operaciones inválidas.
-- TP Base de Datos - CQRS (Parte 2: validaciones de negocio).
--
-- Cada prueba ejecuta una operación inválida y verifica que el comando lanza error.
-- Si una operación inválida NO falla, el script aborta con FALLO (usar ON_ERROR_STOP=1).
-- Todo corre en una transacción que se revierte: no deja datos en la base.

BEGIN;

-- Helper: pasa si p_sql lanza error; falla (aborta) si NO lo lanza.
-- El EXECUTE va en una subtransacción propia, así un error esperado se revierte
-- solo y no aborta la transacción del script.
CREATE FUNCTION pg_temp.assert_error(p_sql TEXT, p_label TEXT) RETURNS VOID AS $fn$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK    % | rechazado: %', p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO % | la operación no lanzó error (debería haberlo hecho)', p_label;
END;
$fn$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_cli       INT;
    v_prod_a    INT;   -- stock = 1  -> para "stock insuficiente al agregar"
    v_prod_b    INT;   -- stock = 20 -> para construir pedidos válidos
    v_ped_pend  INT;   -- Pendiente con 1 ítem
    v_ped_conf  INT;   -- Confirmado
    v_ped_empty INT;   -- Pendiente sin ítems
    v_ped_dep   INT;   -- Pendiente; se le agota el stock antes de confirmar
BEGIN
    -- ---------- Fixture aislado ----------
    INSERT INTO escritura.Cliente (Nombre, Email)
        VALUES ('Cliente NegTest', 'negtest@cqrs.local') RETURNING ID_Cliente INTO v_cli;
    INSERT INTO escritura.Producto (Nombre, Precio, Stock)
        VALUES ('Prod A (stock 1)', 100, 1)  RETURNING ID_Producto INTO v_prod_a;
    INSERT INTO escritura.Producto (Nombre, Precio, Stock)
        VALUES ('Prod B (stock 20)', 100, 20) RETURNING ID_Producto INTO v_prod_b;

    v_ped_pend := escritura.create_pedido(v_cli);
    PERFORM escritura.agregar_item(v_ped_pend, v_prod_b, 1);

    v_ped_conf := escritura.create_pedido(v_cli);
    PERFORM escritura.agregar_item(v_ped_conf, v_prod_b, 1);
    PERFORM escritura.confirmar_pedido(v_ped_conf);

    v_ped_empty := escritura.create_pedido(v_cli);

    v_ped_dep := escritura.create_pedido(v_cli);
    PERFORM escritura.agregar_item(v_ped_dep, v_prod_b, 5);

    -- ---------- Pruebas ----------
    RAISE NOTICE '--- create_pedido ---';
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.create_pedido(%s)', 2147483647),
        'create_pedido: cliente inexistente');

    RAISE NOTICE '--- agregar_item ---';
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.agregar_item(%s, %s, 1)', 2147483647, v_prod_b),
        'agregar_item: pedido inexistente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.agregar_item(%s, %s, 1)', v_ped_conf, v_prod_b),
        'agregar_item: pedido no Pendiente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.agregar_item(%s, %s, 1)', v_ped_pend, 2147483647),
        'agregar_item: producto inexistente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.agregar_item(%s, %s, 5)', v_ped_pend, v_prod_a),
        'agregar_item: stock insuficiente (stock=1, pide 5)');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.agregar_item(%s, %s, 0)', v_ped_pend, v_prod_b),
        'agregar_item: cantidad <= 0 (CHECK Cantidad > 0)');

    RAISE NOTICE '--- confirmar_pedido ---';
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.confirmar_pedido(%s)', 2147483647),
        'confirmar_pedido: pedido inexistente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.confirmar_pedido(%s)', v_ped_conf),
        'confirmar_pedido: pedido no Pendiente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.confirmar_pedido(%s)', v_ped_empty),
        'confirmar_pedido: pedido sin items');
    -- simulamos que el stock se agotó entre agregar y confirmar (carrera):
    UPDATE escritura.Producto SET Stock = 0 WHERE ID_Producto = v_prod_b;
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.confirmar_pedido(%s)', v_ped_dep),
        'confirmar_pedido: stock insuficiente al confirmar');

    RAISE NOTICE '--- actualizar_estado ---';
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.actualizar_estado(%s, %L)', 2147483647, 'Enviado'),
        'actualizar_estado: pedido inexistente');
    PERFORM pg_temp.assert_error(
        format('SELECT escritura.actualizar_estado(%s, %L)', v_ped_pend, 'Entregado'),
        'actualizar_estado: transicion invalida Pendiente->Entregado');

    RAISE NOTICE '====================================================';
    RAISE NOTICE 'OK: las 12 validaciones rechazaron correctamente.';
    RAISE NOTICE '====================================================';
END $$;

ROLLBACK;
