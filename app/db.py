import os
import psycopg
from psycopg.rows import dict_row

DATABASE_URL = os.environ["DATABASE_URL"]

def get_conn():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)

def call(sql: str, params: tuple = ()):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            try:
                return cur.fetchall()
            except psycopg.ProgrammingError:
                return []
