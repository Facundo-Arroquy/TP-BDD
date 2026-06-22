-- Demo de consistencia eventual (Parte 4.2).
-- TP Base de Datos - CQRS.
--
-- Contrasta la sincronización SÍNCRONA (consistencia fuerte, sin ventana) contra
-- una ASÍNCRONA simulada (consistencia eventual, con ventana de inconsistencia),
-- usando la cola de eventos de 14_async_sync.sql.
-- Requiere haber cargado 14_async_sync.sql. Corre en una transacción que se revierte.

BEGIN;

-- ---------- Fixture: un pedido Confirmado, con su PedidoResumen ya coherente ----------
INSERT INTO escritura.Cliente (Nombre, Email)
    VALUES ('Demo EvCons', 'demo-evcons@cqrs.local') RETURNING ID_Cliente AS cli \gset
INSERT INTO escritura.Producto (Nombre, Precio, Stock)
    VALUES ('Prod EvCons', 100, 10) RETURNING ID_Producto AS prod \gset
SELECT escritura.create_pedido(:cli) AS ped \gset
SELECT escritura.agregar_item(:ped, :prod, 1);
SELECT escritura.confirmar_pedido(:ped);

\echo ''
\echo '======== A) SINCRONO: el comando sincroniza en la misma transaccion ========'
SELECT escritura.actualizar_estado(:ped, 'Enviado');
\echo 'Inmediatamente despues del comando, ambos modelos COINCIDEN (no hay ventana):'
SELECT 'escritura' AS modelo, Estado FROM escritura.Pedido    WHERE ID_Pedido = :ped
UNION ALL
SELECT 'lectura'  AS modelo, Estado FROM lectura.PedidoResumen WHERE ID_Pedido = :ped;

\echo ''
\echo '======== B) ASINCRONO (simulado): escribir y ENCOLAR el sync ========'
-- Simulamos un comando async: cambia el modelo de escritura pero NO sincroniza;
-- en su lugar encola el evento (como haria una variante de consistencia eventual).
UPDATE escritura.Pedido SET Estado = 'Entregado' WHERE ID_Pedido = :ped;
SELECT escritura.encolar_sync(:ped);
\echo 'VENTANA DE INCONSISTENCIA: la lectura todavia muestra el estado viejo:'
SELECT 'escritura' AS modelo, Estado FROM escritura.Pedido    WHERE ID_Pedido = :ped
UNION ALL
SELECT 'lectura'  AS modelo, Estado FROM lectura.PedidoResumen WHERE ID_Pedido = :ped;

\echo ''
\echo 'El worker procesa la cola (lo que dispararia LISTEN/NOTIFY o un job periodico):'
SELECT escritura.procesar_cola_sync() AS eventos_procesados;
\echo 'Ahora los modelos vuelven a COINCIDIR (consistencia eventual alcanzada):'
SELECT 'escritura' AS modelo, Estado FROM escritura.Pedido    WHERE ID_Pedido = :ped
UNION ALL
SELECT 'lectura'  AS modelo, Estado FROM lectura.PedidoResumen WHERE ID_Pedido = :ped;

ROLLBACK;
