# App CQRS — TP Base de Datos

App web mínima que demuestra el patrón CQRS invocando las funciones PostgreSQL del TP.

## Requisitos

- Python 3.11+
- PostgreSQL con los scripts `sql/00..07` ya ejecutados

## Paso 1 — Cargar los scripts SQL (una sola vez)

Desde la raíz del repositorio:

```bash
psql -U <usuario> -d <nombre_db> -f sql/00_setup.sql
psql -U <usuario> -d <nombre_db> -f sql/01_write_model.sql
psql -U <usuario> -d <nombre_db> -f sql/02_read_model.sql
psql -U <usuario> -d <nombre_db> -f sql/03_audit.sql
psql -U <usuario> -d <nombre_db> -f sql/04_sync.sql
psql -U <usuario> -d <nombre_db> -f sql/05_commands.sql
psql -U <usuario> -d <nombre_db> -f sql/06_indexes.sql
psql -U <usuario> -d <nombre_db> -f sql/07_queries.sql
```

Opcionalmente, cargar datos de prueba:

```bash
psql -U <usuario> -d <nombre_db> -f sql/08_smoke_test.sql
```

## Paso 2 — Instalar dependencias Python

```bash
cd app
pip install -r requirements.txt
```

## Paso 3 — Configurar la conexión a la base

```bash
export DATABASE_URL="postgresql://usuario:contraseña@localhost:5432/nombre_db"
```

Ejemplo con usuario postgres y base `cqrs_tp`:

```bash
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/cqrs_tp"
```

## Paso 4 — Levantar el servidor

```bash
uvicorn main:app --reload
```

Abrir http://localhost:8000 en el navegador.

## Flujo de demo

1. **Crear pedido** → elegir cliente → botón "Crear pedido" (el ID queda autocompletado)
2. **Agregar ítem** → elegir producto y cantidad → "Agregar ítem" (se valida stock)
3. **Confirmar** → "Confirmar" (descuenta stock atómicamente)
4. **Consultar** → columna derecha muestra el estado actualizado sin recargar la página
5. **Cambiar estado** → Confirmado → Enviado → Entregado
6. **Error de negocio** → intentar confirmar sin ítems o con stock insuficiente → aparece mensaje 400

## Arquitectura

```
Browser → FastAPI (main.py) → psycopg → PostgreSQL
                ↓ comandos: escritura.*
                ↓ consultas: lectura.*
```

La app no contiene lógica de negocio; toda la validación vive en las funciones SQL.
