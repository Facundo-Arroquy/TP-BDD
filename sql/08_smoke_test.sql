-- Smoke test: flujo de comandos y consultas
-- TP Base de Datos - CQRS. Generado desde resolucion.md

-- datos base
INSERT INTO escritura.Cliente (Nombre, Email) VALUES
    ('Ana Gomez', 'ana@mail.com'), ('Luis Paz', 'luis@mail.com');
INSERT INTO escritura.Producto (Nombre, Precio, Stock) VALUES
    ('Teclado', 15000.00, 10), ('Mouse', 8000.00, 5), ('Monitor', 90000.00, 3);

-- flujo de comandos
SELECT escritura.create_pedido(1);          -- -> pedido 1
SELECT escritura.agregar_item(1, 1, 2);     -- 2 teclados
SELECT escritura.agregar_item(1, 2, 1);     -- 1 mouse
SELECT escritura.confirmar_pedido(1);       -- descuenta stock
SELECT escritura.actualizar_estado(1, 'Enviado');

-- consultas sobre el modelo de lectura
SELECT * FROM lectura.obtener_resumen_pedido(1);
SELECT * FROM lectura.obtener_pedidos_por_cliente(1);
SELECT lectura.obtener_estado_envio(1);
SELECT * FROM lectura.obtener_top_productos(
    (now() - interval '1 day')::timestamp,
    (now() + interval '1 day')::timestamp
);
