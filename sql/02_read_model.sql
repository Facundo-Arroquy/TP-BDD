-- Modelo de lectura (desnormalizado)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

CREATE TABLE lectura.PedidoResumen (
    ID_Pedido       INT PRIMARY KEY,
    Nombre_Cliente  VARCHAR(100) NOT NULL,   -- desnormalizado desde Cliente
    Email_Cliente   VARCHAR(100) NOT NULL,   -- desnormalizado desde Cliente
    Fecha_Creacion  TIMESTAMP NOT NULL,
    Estado          VARCHAR(20) NOT NULL,
    Total           DECIMAL(10,2) NOT NULL,
    Cantidad_Items  INT NOT NULL,            -- desnormalizado (COUNT de items)
    Productos       TEXT,                    -- desnormalizado (lista concatenada)
    ID_Cliente      INT NOT NULL             -- se mantiene para filtrar por cliente
);
