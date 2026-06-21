from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional
import psycopg
from db import call

app = FastAPI(title="CQRS Demo")
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
def root():
    return FileResponse("static/index.html")


# ── Auxiliares de lectura para poblar los selects ────────────────────────────

@app.get("/clientes")
def listar_clientes():
    return call("SELECT ID_Cliente, Nombre, Email FROM escritura.Cliente ORDER BY Nombre")


@app.get("/productos")
def listar_productos():
    return call("SELECT ID_Producto, Nombre, Precio, Stock FROM escritura.Producto ORDER BY Nombre")


# ── COMANDOS (escritura) ─────────────────────────────────────────────────────

class CrearPedidoBody(BaseModel):
    id_cliente: int

@app.post("/pedidos", status_code=201)
def crear_pedido(body: CrearPedidoBody):
    try:
        rows = call("SELECT escritura.create_pedido(%s) AS id_pedido", (body.id_cliente,))
        return {"id_pedido": rows[0]["id_pedido"]}
    except psycopg.errors.RaiseException as e:
        raise HTTPException(status_code=400, detail=str(e).split("\n")[0])


class AgregarItemBody(BaseModel):
    id_producto: int
    cantidad: int

@app.post("/pedidos/{id_pedido}/items", status_code=201)
def agregar_item(id_pedido: int, body: AgregarItemBody):
    try:
        call("SELECT escritura.agregar_item(%s, %s, %s)", (id_pedido, body.id_producto, body.cantidad))
        return {"ok": True}
    except psycopg.errors.RaiseException as e:
        raise HTTPException(status_code=400, detail=str(e).split("\n")[0])


@app.post("/pedidos/{id_pedido}/confirmar")
def confirmar_pedido(id_pedido: int):
    try:
        call("SELECT escritura.confirmar_pedido(%s)", (id_pedido,))
        return {"ok": True}
    except psycopg.errors.RaiseException as e:
        raise HTTPException(status_code=400, detail=str(e).split("\n")[0])


class ActualizarEstadoBody(BaseModel):
    nuevo_estado: str

@app.post("/pedidos/{id_pedido}/estado")
def actualizar_estado(id_pedido: int, body: ActualizarEstadoBody):
    try:
        call("SELECT escritura.actualizar_estado(%s, %s)", (id_pedido, body.nuevo_estado))
        return {"ok": True}
    except psycopg.errors.RaiseException as e:
        raise HTTPException(status_code=400, detail=str(e).split("\n")[0])


# ── CONSULTAS (lectura) ──────────────────────────────────────────────────────

@app.get("/clientes/{id_cliente}/pedidos")
def pedidos_por_cliente(id_cliente: int):
    rows = call("SELECT * FROM lectura.obtener_pedidos_por_cliente(%s)", (id_cliente,))
    return rows


@app.get("/pedidos/{id_pedido}")
def resumen_pedido(id_pedido: int):
    rows = call("SELECT * FROM lectura.obtener_resumen_pedido(%s)", (id_pedido,))
    if not rows:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    return rows[0]


@app.get("/pedidos/{id_pedido}/estado")
def estado_envio(id_pedido: int):
    rows = call("SELECT lectura.obtener_estado_envio(%s) AS estado", (id_pedido,))
    if not rows or rows[0]["estado"] is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    return {"estado": rows[0]["estado"]}


@app.get("/reportes/top-productos")
def top_productos(desde: str = None, hasta: str = None, limite: int = 10):
    rows = call(
        "SELECT * FROM lectura.obtener_top_productos(%s::timestamp, %s::timestamp, %s)",
        (desde, hasta, limite),
    )
    return rows


# ── NUEVAS CONSULTAS ──────────────────────────────────────────────────────────

@app.get("/pedidos/{id_pedido}/historial")
def historial_estado(id_pedido: int):
    rows = call("SELECT * FROM lectura.obtener_historial_estado(%s)", (id_pedido,))
    return rows


@app.get("/auditoria")
def listar_auditoria(limite: int = 20):
    rows = call(
        "SELECT ID, Comando, Payload, Usuario, Fecha FROM escritura.AuditoriaComando ORDER BY ID DESC LIMIT %s",
        (limite,),
    )
    return rows


@app.get("/dashboard/metricas")
def dashboard_metricas():
    rows = call("""
        SELECT
            (SELECT COUNT(*) FROM escritura.Pedido) AS total_pedidos,
            (SELECT COUNT(*) FROM escritura.Cliente) AS total_clientes,
            (SELECT COUNT(*) FROM escritura.Producto) AS total_productos,
            (SELECT jsonb_object_agg(Estado, cnt) FROM
                (SELECT Estado, COUNT(*) AS cnt FROM escritura.Pedido GROUP BY Estado) t
            ) AS pedidos_por_estado,
            (SELECT COALESCE(SUM(Unidades_Vendidas), 0) FROM lectura.ResumenVentas) AS total_unidades_vendidas
    """)
    return rows[0] if rows else {}
