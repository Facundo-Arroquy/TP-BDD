# run_all.ps1 — Ejecuta todo el TP CQRS en orden (Windows + PowerShell)
# Uso:
#   Con Docker:     .\scripts\run_all.ps1 -Mode docker
#   Con Postgres local: .\scripts\run_all.ps1 -Mode local -Url "postgresql://user:pass@host:5432/db"

param(
    [ValidateSet("docker", "local")]
    [string]$Mode = "docker",
    [string]$Url = "postgresql://postgres:postgres@localhost:5432/cqrs_tp"
)

$ErrorActionPreference = "Stop"
Write-Host "=== TP CQRS — Setup completo ===" -ForegroundColor Cyan

if ($Mode -eq "docker") {
    Write-Host "[1/6] Levantando contenedores..."
    docker compose up -d

    Write-Host "[2/6] Esperando a que Postgres esté listo..."
    do {
        Start-Sleep -Seconds 1
        $ready = docker compose exec -T db pg_isready -U postgres 2>$null
    } while (-not $ready)
    Write-Host "      Postgres listo."

    $RUN = { param($f) docker compose exec -T db psql -U postgres -d cqrs_tp -f "/sql/$((Get-Item $f).Name)" }
} else {
    Write-Host "[1/6] Usando Postgres local..."
    $RUN = { param($f) psql $Url -f $f }
}

$scripts = @(
    "sql/00_setup.sql",
    "sql/01_write_model.sql",
    "sql/02_read_model.sql",
    "sql/03_audit.sql",
    "sql/04_sync.sql",
    "sql/05_commands.sql",
    "sql/06_indexes.sql",
    "sql/07_queries.sql",
    "sql/12_estado_historico.sql",
    "sql/13_resumen_ventas.sql"
)

Write-Host "[3/6] Ejecutando scripts 00 a 13..."
foreach ($f in $scripts) {
    Write-Host "      >> $f"
    & $RUN $f
}

Write-Host "[4/6] Smoke test (flujo básico)..."
& $RUN "sql/08_smoke_test.sql"

Write-Host "[5/6] Sync asíncrona (opcional)..."
& $RUN "sql/14_async_sync.sql"

Write-Host "[6/6] Cargando dataset de benchmark..."
& $RUN "sql/10_seed_benchmark.sql"

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Benchmark CQRS vs CRUD:" -ForegroundColor Yellow
Write-Host "  docker compose exec -T db psql -U postgres -d cqrs_tp -f /sql/11_benchmark.sql"
Write-Host ""
Write-Host "App: http://localhost:8000" -ForegroundColor Cyan
