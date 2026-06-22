#!/usr/bin/env bash
# run_all.sh — Ejecuta todo el TP CQRS en orden
# Uso:
#   Con Docker:     ./scripts/run_all.sh docker
#   Con Postgres local: ./scripts/run_all.sh local "postgres://user:pass@host:5432/db"
set -euo pipefail

MODE="${1:-docker}"
URL="${2:-postgresql://postgres:postgres@localhost:5432/cqrs_tp}"

# Ejecuta un script SQL (path relativo al repo, ej. sql/00_setup.sql).
# En docker, el dir ./sql se monta en /sql dentro del contenedor.
run_sql() {
    local f="$1"
    echo "      >> $f"
    if [ "$MODE" = "docker" ]; then
        docker compose exec -T db psql -U postgres -d cqrs_tp -v ON_ERROR_STOP=1 -f "/$f"
    else
        psql "$URL" -v ON_ERROR_STOP=1 -f "$f"
    fi
}

echo "=== TP CQRS — Setup completo ==="

if [ "$MODE" = "docker" ]; then
    echo "[1/9] Levantando contenedores..."
    docker compose up -d
    echo "[2/9] Esperando a que Postgres esté listo..."
    until docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
    echo "      Postgres listo."
else
    echo "[1/9] Usando Postgres local..."
fi

echo "[3/9] Ejecutando scripts 00 a 14..."
for f in sql/00_setup.sql sql/01_write_model.sql sql/02_read_model.sql \
          sql/03_audit.sql sql/04_sync.sql sql/05_commands.sql \
          sql/06_indexes.sql sql/07_queries.sql sql/09_crud_reference.sql \
          sql/12_estado_historico.sql sql/13_resumen_ventas.sql; do
    run_sql "$f"
done

echo "[4/9] Smoke test (flujo básico)..."
run_sql sql/08_smoke_test.sql

echo "[5/9] Sync asíncrona (opcional)..."
run_sql sql/14_async_sync.sql

echo "[6/9] Cargando dataset de benchmark..."
run_sql sql/10_seed_benchmark.sql

echo "[7/9] Benchmark CQRS vs CRUD (warm-up + medición)..."
# El benchmark se corre dos veces en la misma corrida: la 1ra pasada calienta
# el cache (se descarta) y la 2da es la que medimos. Así los tiempos no incluyen
# el costo de leer de disco la primera vez.
run_sql sql/11_benchmark.sql > /dev/null 2>&1
BENCH="$(run_sql sql/11_benchmark.sql 2>&1)"
# Cada sección del benchmark imprime 2 líneas "Time:" en orden (CQRS y luego CRUD).
# Parseamos esos pares en una tabla de ratios; se guarda para reusar en el RESUMEN FINAL.
BENCH_SUMMARY="$(echo "$BENCH" | awk '
  /^====/ {
    title = $0; gsub(/=/, "", title); gsub(/^[ \t]+|[ \t]+$/, "", title); n = 0; next
  }
  /^Time:/ {
    n++
    if (n == 1) { cqrs = $2 }
    else if (n == 2) {
      crud = $2
      if (title ~ /scritura/) {
        nota = sprintf("CQRS ~%.1fx mas lenta (mantiene el modelo de lectura)", cqrs / crud)
      } else if (crud / cqrs < 1.25) {
        nota = "~empate (CQRS no aporta aca)"
      } else {
        nota = sprintf("CQRS ~%.1fx mas rapida", crud / cqrs)
      }
      printf "  %-34s CQRS %8.3f ms | CRUD %8.3f ms  ->  %s\n", title, cqrs, crud, nota
    }
  }
')"
echo ""
echo "=== Resumen CQRS vs CRUD (2da pasada, cache caliente) ==="
echo "$BENCH_SUMMARY"

echo ""
echo "[8/9] Pruebas negativas (validaciones de negocio)..."
# Gate: si alguna validación no se dispara, abortamos. Capturamos la salida para resumir.
set +e
NEG="$(run_sql sql/15_pruebas_negativas.sql 2>&1)"
NEG_RC=$?
set -e
echo "$NEG"
if [ "$NEG_RC" -ne 0 ]; then
    echo "!! FALLO: alguna validación de negocio no se disparó. Abortando." >&2
    exit 1
fi
NEG_OK=$(echo "$NEG" | grep -c 'rechazado:' || true)

echo ""
echo "[9/9] Demo de consistencia eventual (sincrono vs asincrono)..."
set +e
DEMO="$(run_sql sql/16_demo_consistencia_eventual.sql 2>&1)"
DEMO_RC=$?
set -e
echo "$DEMO"
if [ "$DEMO_RC" -eq 0 ] && echo "$DEMO" | grep -q 'VENTANA DE INCONSISTENCIA' && echo "$DEMO" | grep -q 'COINCIDIR'; then
    DEMO_STATUS="OK (ventana demostrada; consistencia recuperada al procesar la cola)"
else
    DEMO_STATUS="(ver salida arriba)"
fi

echo ""
echo "################### RESUMEN FINAL ###################"
echo ""
echo "Mediciones de lectura/escritura (CQRS vs CRUD, cache caliente):"
echo "$BENCH_SUMMARY"
echo ""
printf "  %-34s %s\n" "Pruebas negativas (Parte 2):"      "${NEG_OK}/12 validaciones rechazadas OK"
printf "  %-34s %s\n" "Consistencia eventual (Parte 4.2):" "${DEMO_STATUS}"
echo ""
echo "#####################################################"
echo "Planes completos (EXPLAIN): docker compose exec -T db psql -U postgres -d cqrs_tp -f /sql/11_benchmark.sql"
echo "App: http://localhost:8000"
