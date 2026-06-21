# Diagrama de Arquitectura CQRS

```mermaid
flowchart TB
    subgraph Cliente["Cliente (Browser)"]
        UI["index.html<br/>Vanilla JS"]
    end

    subgraph API["FastAPI (main.py)"]
        CMD["Comandos POST<br/>/pedidos, /items, /confirmar, /estado"]
        QRY["Consultas GET<br/>/clientes/{id}/pedidos, /pedidos/{id}, /top-productos"]
        AUX["Auxiliares GET<br/>/clientes, /productos"]
    end

    subgraph PG["PostgreSQL"]
        direction TB
        subgraph WM["Schema: escritura<br/>Command Model"]
            W_TABLES["Cliente<br/>Producto<br/>Pedido<br/>ItemPedido"]
            FUNCS["create_pedido()<br/>agregar_item()<br/>confirmar_pedido()<br/>actualizar_estado()"]
            AUDIT["AuditoriaComando"]
        end
        subgraph RM["Schema: lectura<br/>Query Model"]
            R_TABLES["PedidoResumen<br/>(desnormalizado)"]
            R_FUNCS["obtener_pedidos_por_cliente()<br/>obtener_resumen_pedido()<br/>obtener_estado_envio()"]
        end
        SYNC["sync_resumen()<br/>Sincronización síncrona"]
    end

    UI -->|"fetch()"| API
    CMD -->|"SELECT funciones"| WM
    CMD -->|"INSERT auditoría"| AUDIT
    FUNCS -->|"Llaman a"| SYNC
    SYNC -->|"INSERT / UPDATE"| R_TABLES
    QRY -->|"SELECT funciones"| R_TABLES
    AUX -->|"SELECT directo"| WM

    style WM fill:#fef2f2,stroke:#dc2626,stroke-width:2px
    style RM fill:#eff6ff,stroke:#2563eb,stroke-width:2px
    style SYNC fill:#f0fdf4,stroke:#16a34a,stroke-width:2px
    style CMD fill:#fef2f2,stroke:#dc2626
    style QRY fill:#eff6ff,stroke:#2563eb
```

## Flujo

1. **Comandos** (rojo): el usuario envía un POST desde la UI → FastAPI llama a una función del schema `escritura` → valida reglas de negocio → modifica tablas normalizadas → sincroniza el modelo de lectura → registra auditoría. Todo en una misma transacción (consistencia fuerte).

2. **Consultas** (azul): el usuario hace un GET → FastAPI llama a una función del schema `lectura` → lee de `PedidoResumen` sin JOINs ni agregaciones en tiempo de lectura.

3. **Sincronización** (verde): `sync_resumen()` reconstruye la fila desnormalizada de `PedidoResumen` a partir del estado actual del modelo de escritura. Se ejecuta dentro de cada comando (síncrona).
