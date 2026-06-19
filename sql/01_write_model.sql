-- Modelo de escritura (normalizado)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

CREATE TABLE escritura.Cliente (
    ID_Cliente   SERIAL PRIMARY KEY,
    Nombre       VARCHAR(100) NOT NULL,
    Email        VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE escritura.Producto (
    ID_Producto  SERIAL PRIMARY KEY,
    Nombre       VARCHAR(100) NOT NULL,
    Precio       DECIMAL(10,2) NOT NULL CHECK (Precio >= 0),
    Stock        INT NOT NULL CHECK (Stock >= 0)
);

CREATE TABLE escritura.Pedido (
    ID_Pedido      SERIAL PRIMARY KEY,
    ID_Cliente     INT NOT NULL REFERENCES escritura.Cliente(ID_Cliente),
    Fecha_Creacion TIMESTAMP NOT NULL DEFAULT now(),
    Estado         VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                   CHECK (Estado IN ('Pendiente','Confirmado','Enviado','Entregado','Cancelado')),
    Total          DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (Total >= 0)
);

CREATE TABLE escritura.ItemPedido (
    ID_Item         SERIAL PRIMARY KEY,
    ID_Pedido       INT NOT NULL REFERENCES escritura.Pedido(ID_Pedido) ON DELETE CASCADE,
    ID_Producto     INT NOT NULL REFERENCES escritura.Producto(ID_Producto),
    Cantidad        INT NOT NULL CHECK (Cantidad > 0),
    Precio_Unitario DECIMAL(10,2) NOT NULL CHECK (Precio_Unitario >= 0)
);
