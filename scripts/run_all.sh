#!/usr/bin/env bash
# run_all.sh — Ejecuta todo el TP CQRS en orden
# Uso:
#   Con Docker:     ./scripts/run_all.sh docker
#   Con Postgres local: ./scripts/run_all.sh local "postgres://user:pass@host:5432/db"
set -euo pipefail

MODE="${1:-docker}"
URL="${2:-postgresql://postgres:postgres@localhost:5432/cqrs_tp}"

echo "=== TP CQRS — Setup completo ==="

if [ "$MODE" = "docker" ]; then
    echo "[1/6] Levantando contenedores..."
    docker compose up -d
    echo "[2/6] Esperando a que Postgres esté listo..."
    until docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
    echo "      Postgres listo."

    RUN="docker compose exec -T db psql -U postgres -d cqrs_tp -f /sql"
else
    echo "[1/6] Usando Postgres local..."
    RUN="psql $URL -f"
fi

echo "[3/6] Ejecutando scripts 00 a 14..."
for f in sql/00_setup.sql sql/01_write_model.sql sql/02_read_model.sql \
          sql/03_audit.sql sql/04_sync.sql sql/05_commands.sql \
          sql/06_indexes.sql sql/07_queries.sql \
          sql/12_estado_historico.sql sql/13_resumen_ventas.sql; do
    echo "      >> $f"
    $RUN "$f"
done

echo "[4/6] Smoke test (flujo básico)..."
$RUN sql/08_smoke_test.sql

echo "[5/6] Sync asíncrona (opcional)..."
$RUN sql/14_async_sync.sql

echo "[6/6] Cargando dataset de benchmark..."
$RUN sql/10_seed_benchmark.sql

echo ""
echo "=== Listo ==="
echo "Benchmark CQRS vs CRUD:"
echo "docker compose exec -T db psql -U postgres -d cqrs_tp -f /sql/11_benchmark.sql"
echo ""
echo "App: http://localhost:8000"
