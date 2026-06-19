-- Setup: esquemas escritura (command) y lectura (query)
-- TP Base de Datos - CQRS. Generado desde resolucion.md

DROP SCHEMA IF EXISTS escritura CASCADE;
DROP SCHEMA IF EXISTS lectura  CASCADE;
CREATE SCHEMA escritura;  -- command model (normalizado)
CREATE SCHEMA lectura;    -- query model (desnormalizado)
