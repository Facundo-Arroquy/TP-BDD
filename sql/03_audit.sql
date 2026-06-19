-- Tabla de auditoria de comandos
-- TP Base de Datos - CQRS. Generado desde resolucion.md

CREATE TABLE escritura.AuditoriaComando (
    ID         SERIAL PRIMARY KEY,
    Comando    VARCHAR(50) NOT NULL,
    Payload    JSONB,
    Usuario    VARCHAR(100) NOT NULL DEFAULT current_user,
    Fecha      TIMESTAMP NOT NULL DEFAULT now()
);
