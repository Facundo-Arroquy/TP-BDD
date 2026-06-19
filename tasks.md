# Tasks: app sencilla sobre el TP CQRS

Objetivo: una app web **mínima** que use lo ya hecho en `sql/` para demostrar el patrón CQRS de punta a punta. La app es una capa fina: **no reimplementa lógica de negocio**, solo invoca los comandos y consultas que ya viven como funciones en PostgreSQL.

> Contexto para quien ejecute: leer `CLAUDE.md`, `enunciado.md`, `resolucion.md` y `README.md` antes de empezar. Ante cualquier duda, preguntar. La base ya está implementada en `sql/00..11`.

## Stack (mantener simple)

- **Backend**: Python + FastAPI + `psycopg` (v3).
- **DB**: PostgreSQL ya existente (scripts `sql/`). La app NO crea tablas ni lógica; solo llama funciones.
- **Frontend**: un único `index.html` con HTML + JS vanilla (fetch). Sin frameworks ni build.
- **Config**: connection string por variable de entorno `DATABASE_URL`.

Justificación: el TP es de Base de Datos. La app debe ser delgada para que el peso siga en el modelado CQRS, no en el código de aplicación.

## Estructura esperada

```
tp/
├── sql/                # ya existe
└── app/
    ├── requirements.txt # fastapi, uvicorn, psycopg[binary]
    ├── db.py            # conexión a Postgres (pool simple)
    ├── main.py          # endpoints FastAPI
    ├── static/
    │   └── index.html   # UI mínima
    └── README.md        # cómo correr la app
```

## Tareas

### 1. Setup del proyecto
- [ ] Crear carpeta `app/` con la estructura de arriba.
- [ ] `requirements.txt` con `fastapi`, `uvicorn[standard]`, `psycopg[binary]`.
- [ ] `db.py`: leer `DATABASE_URL`, abrir conexión/pool, helper `call(sql, params)` que ejecuta y devuelve filas como dicts.

### 2. Backend — lado COMANDOS (escritura)
Cada endpoint llama a la función SQL correspondiente (ya existe en `sql/05_commands.sql`). Mapear los errores `RAISE EXCEPTION` de Postgres a respuestas HTTP 400 con el mensaje.
- [ ] `POST /pedidos` → `escritura.create_pedido(id_cliente)`. Devuelve `id_pedido`.
- [ ] `POST /pedidos/{id}/items` → `escritura.agregar_item(id, id_producto, cantidad)`.
- [ ] `POST /pedidos/{id}/confirmar` → `escritura.confirmar_pedido(id)`.
- [ ] `POST /pedidos/{id}/estado` → `escritura.actualizar_estado(id, nuevo_estado)`.

### 3. Backend — lado CONSULTAS (lectura)
Cada endpoint llama a las funciones de `sql/07_queries.sql` (modelo de lectura desnormalizado).
- [ ] `GET /clientes/{id}/pedidos` → `lectura.obtener_pedidos_por_cliente(id)`.
- [ ] `GET /pedidos/{id}` → `lectura.obtener_resumen_pedido(id)`.
- [ ] `GET /pedidos/{id}/estado` → `lectura.obtener_estado_envio(id)`.
- [ ] `GET /reportes/top-productos?desde=&hasta=` → `lectura.obtener_top_productos(desde, hasta)`.
- [ ] Endpoints auxiliares de solo lectura para poblar los selects de la UI: `GET /clientes`, `GET /productos` (SELECT directo a `escritura.Cliente` / `escritura.Producto`).

### 4. Frontend — `index.html`
UI mínima que haga visible la separación lectura/escritura. Una sola página con dos columnas:
- [ ] **Comandos** (izquierda): formularios para crear pedido (elegir cliente), agregar ítems (producto + cantidad), confirmar, cambiar estado.
- [ ] **Consultas** (derecha): ver resumen de un pedido, listar pedidos por cliente, ver top productos. Botón "refrescar".
- [ ] Mostrar los mensajes de error que devuelve el backend (ej. "Stock insuficiente").
- [ ] Dejar visible que tras un comando, la vista de lectura ya refleja el cambio (demuestra la sincronización síncrona).

### 5. Documentación y prueba
- [ ] `app/README.md`: cómo instalar deps, setear `DATABASE_URL`, levantar con `uvicorn main:app --reload`, y correr antes los `sql/`.
- [ ] Probar el flujo completo: crear pedido → agregar ítems → confirmar (ver stock descontado) → cambiar estado → consultarlo. Verificar que un error de negocio (confirmar sin stock) devuelve 400 con mensaje claro.

## Criterios de aceptación
- La app **no** contiene lógica de negocio (validaciones de stock, estados, totales): todo eso lo resuelve la base. La app solo invoca funciones y muestra resultados.
- Se ve claramente la separación CQRS: endpoints/columna de comandos vs endpoints/columna de consultas.
- El flujo de demo corre de punta a punta contra la base del TP.

## Fuera de alcance (no hacer)
- Autenticación, usuarios, sesiones.
- ORM o migraciones (la base ya está en `sql/`).
- Tests automatizados, CI, deploy.
- Reescribir o duplicar lógica que ya está en los procedimientos almacenados.
