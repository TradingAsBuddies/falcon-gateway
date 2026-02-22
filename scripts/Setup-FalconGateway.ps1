<#
.SYNOPSIS
    Falcon Gateway Stack - Complete Setup Script for Windows/Podman Desktop

.DESCRIPTION
    Sets up: Redis, Consul, Traefik, Prometheus, Grafana, Demo Website

.PARAMETER Action
    start, stop, restart, status, clean

.EXAMPLE
    .\Setup-FalconGateway.ps1 start
#>

param(
    [ValidateSet("start", "stop", "restart", "status", "clean")]
    [string]$Action = "start"
)

$ErrorActionPreference = "Stop"

# Configuration
$FalconRoot = "$env:USERPROFILE\falcon-dev"
$ContainerNames = @("falcon-postgresql", "falcon-postgres-exporter", "falcon-redis", "falcon-consul", "falcon-traefik", "falcon-prometheus", "falcon-grafana", "falcon-website", "falcon-messenger", "falcon-signal-web")
$VolumeNames = @(
    "falcon-redis-data",
    "falcon-consul-data",
    "falcon-traefik-config",
    "falcon-traefik-certs",
    "falcon-prometheus-config",
    "falcon-prometheus-data",
    "falcon-grafana-data",
    "falcon-website-content",
    "falcon-postgresql-data",
    "falcon-postgresql-init",
    "falcon-signal-web-data"
)

function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Show-Banner {
    Write-Host ""
    Write-Host "  FALCON GATEWAY STACK" -ForegroundColor Cyan
    Write-Host "  ====================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Test-Podman {
    Write-Info "Checking Podman..."
    
    if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
        Write-Err "Podman not found. Install Podman Desktop first."
        exit 1
    }
    
    $machineList = podman machine list 2>$null
    if ($machineList -match "Currently running") {
        Write-Success "Podman machine is running"
    } else {
        Write-Warn "Starting Podman machine..."
        podman machine start
        Start-Sleep -Seconds 5
    }
}

function Initialize-Directories {
    Write-Info "Creating directories..."
    
    $dirs = @(
        "$FalconRoot\traefik\dynamic",
        "$FalconRoot\prometheus",
        "$FalconRoot\postgresql\init",
        "$FalconRoot\website"
    )
    
    foreach ($dir in $dirs) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    
    Write-Success "Directories created at $FalconRoot"
}

function Initialize-ConfigFiles {
    Write-Info "Creating configuration files..."
    
    # Traefik static config
    $traefikYml = @"
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  traefik:
    address: ":8080"

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

ping:
  entryPoint: traefik

log:
  level: INFO

accessLog: {}

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
"@
    $traefikYml | Out-File -FilePath "$FalconRoot\traefik\traefik.yml" -Encoding UTF8

    # Traefik dynamic routes
    $routesYml = @"
http:
  routers:
    website:
      rule: Host(``localhost``) || Host(``falcon.localhost``)
      service: website-svc
      entryPoints:
        - web

    traefik-api:
      rule: Host(``traefik.localhost``)
      service: api@internal
      entryPoints:
        - web

    consul:
      rule: Host(``consul.localhost``)
      service: consul-svc
      entryPoints:
        - web

    prometheus:
      rule: Host(``prometheus.localhost``)
      service: prometheus-svc
      entryPoints:
        - web

    grafana:
      rule: Host(``grafana.localhost``)
      service: grafana-svc
      entryPoints:
        - web

  services:
    website-svc:
      loadBalancer:
        servers:
          - url: http://falcon-website:80

    consul-svc:
      loadBalancer:
        servers:
          - url: http://falcon-consul:8500

    prometheus-svc:
      loadBalancer:
        servers:
          - url: http://falcon-prometheus:9090

    grafana-svc:
      loadBalancer:
        servers:
          - url: http://falcon-grafana:3000
"@
    $routesYml | Out-File -FilePath "$FalconRoot\traefik\dynamic\routes.yml" -Encoding UTF8

    # Prometheus config
    $promYml = @"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
        - localhost:9090

  - job_name: traefik
    static_configs:
      - targets:
        - falcon-traefik:8080

  - job_name: consul
    metrics_path: /v1/agent/metrics
    params:
      format:
        - prometheus
    static_configs:
      - targets:
        - falcon-consul:8500
"@
    $promYml | Out-File -FilePath "$FalconRoot\prometheus\prometheus.yml" -Encoding UTF8

    # PostgreSQL init SQL
    $pgInitSql = @"
-- Runs once on first container start (empty data volume)
CREATE DATABASE finviz;
GRANT ALL PRIVILEGES ON DATABASE finviz TO falcon;
ALTER SYSTEM SET shared_buffers = '128MB';
ALTER SYSTEM SET effective_cache_size = '384MB';
ALTER SYSTEM SET max_connections = 100;
"@
    $pgInitSql | Out-File -FilePath "$FalconRoot\postgresql\init\01-create-databases.sql" -Encoding UTF8

    # Demo website - create separately to avoid parsing issues
    Create-WebsiteHtml
    
    Write-Success "Configuration files created"
}

function Create-WebsiteHtml {
    $htmlContent = '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Falcon Gateway</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: Segoe UI, system-ui, sans-serif;
            background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 50%, #16213e 100%);
            color: #e8e8e8;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 40px 20px;
        }
        .container { max-width: 900px; width: 100%; text-align: center; }
        h1 {
            font-size: 3rem;
            background: linear-gradient(90deg, #63b3ed, #b794f6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 10px;
        }
        .subtitle { opacity: 0.6; margin-bottom: 40px; }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .status-card {
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 12px;
            padding: 20px;
            transition: all 0.2s;
        }
        .status-card:hover {
            border-color: #63b3ed;
            transform: translateY(-2px);
        }
        .status-card h3 { color: #63b3ed; margin-bottom: 10px; font-size: 1rem; }
        .indicator {
            width: 10px; height: 10px; border-radius: 50%;
            display: inline-block; margin-right: 8px;
            background: #6bcb77; box-shadow: 0 0 10px #6bcb77;
            animation: pulse 2s infinite;
        }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .links { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; margin-top: 30px; }
        .links a {
            background: rgba(99, 179, 237, 0.1);
            border: 1px solid #63b3ed;
            color: #63b3ed;
            padding: 10px 20px;
            border-radius: 6px;
            text-decoration: none;
            font-size: 0.9rem;
            transition: all 0.2s;
        }
        .links a:hover { background: #63b3ed; color: #0a0a0f; }
        footer { margin-top: auto; padding-top: 40px; opacity: 0.4; font-size: 0.85rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Falcon Gateway</h1>
        <p class="subtitle">Trading Platform Microservices Stack</p>

        <div class="status-grid">
            <div class="status-card">
                <h3>Traefik</h3>
                <p><span class="indicator"></span>Gateway</p>
            </div>
            <div class="status-card">
                <h3>Redis</h3>
                <p><span class="indicator"></span>Queue</p>
            </div>
            <div class="status-card">
                <h3>Consul</h3>
                <p><span class="indicator"></span>Discovery</p>
            </div>
            <div class="status-card">
                <h3>Prometheus</h3>
                <p><span class="indicator"></span>Metrics</p>
            </div>
            <div class="status-card">
                <h3>Grafana</h3>
                <p><span class="indicator"></span>Dashboards</p>
            </div>
            <div class="status-card">
                <h3>PostgreSQL</h3>
                <p><span class="indicator"></span>Database</p>
            </div>
        </div>

        <div class="links">
            <a href="http://localhost:8080" target="_blank">Traefik</a>
            <a href="http://localhost:8500" target="_blank">Consul</a>
            <a href="http://localhost:9090" target="_blank">Prometheus</a>
            <a href="http://localhost:3000" target="_blank">Grafana</a>
        </div>
    </div>
    <footer>Falcon Trading Platform - Powered by Podman</footer>
</body>
</html>'

    $htmlContent | Out-File -FilePath "$FalconRoot\website\index.html" -Encoding UTF8
}

function Initialize-Volumes {
    Write-Info "Creating volumes..."
    
    foreach ($vol in $VolumeNames) {
        $existing = podman volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -eq $vol }
        if (-not $existing) {
            podman volume create $vol 2>$null | Out-Null
        }
    }
    
    Write-Success "Volumes ready"
}

function Copy-ConfigsToVolumes {
    Write-Info "Copying configurations to volumes..."
    
    # Convert Windows path to forward slashes for podman
    $sourcePath = $FalconRoot -replace '\\', '/'
    
    # Traefik config
    podman run --rm -v "falcon-traefik-config:/config" -v "${sourcePath}/traefik:/source:ro" alpine sh -c "cp -r /source/* /config/ 2>/dev/null; exit 0" 2>$null
    
    # Prometheus config  
    podman run --rm -v "falcon-prometheus-config:/config" -v "${sourcePath}/prometheus:/source:ro" alpine sh -c "cp /source/* /config/ 2>/dev/null; exit 0" 2>$null
    
    # Website content
    podman run --rm -v "falcon-website-content:/content" -v "${sourcePath}/website:/source:ro" alpine sh -c "cp /source/* /content/ 2>/dev/null; exit 0" 2>$null
    
    # PostgreSQL init scripts
    podman run --rm -v "falcon-postgresql-init:/config" -v "${sourcePath}/postgresql/init:/source:ro" alpine sh -c "cp /source/* /config/ 2>/dev/null; exit 0" 2>$null

    # Init acme.json
    podman run --rm -v "falcon-traefik-certs:/certs" alpine sh -c "touch /certs/acme.json; chmod 600 /certs/acme.json" 2>$null
    
    Write-Success "Configurations copied"
}

function Initialize-Network {
    Write-Info "Creating network..."
    
    $existing = podman network ls --format "{{.Name}}" 2>$null | Where-Object { $_ -eq "falcon" }
    if (-not $existing) {
        podman network create --subnet 10.89.0.0/24 --gateway 10.89.0.1 falcon 2>$null | Out-Null
    }
    
    Write-Success "Network ready"
}

function Start-FalconContainers {
    Write-Info "Starting containers..."
    
    # PostgreSQL
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-postgresql" }
    if (-not $running) {
        Write-Host "  Starting PostgreSQL..." -ForegroundColor Gray
        podman run -d --name falcon-postgresql --network falcon -p 5432:5432 -v falcon-postgresql-data:/var/lib/postgresql/data -v falcon-postgresql-init:/docker-entrypoint-initdb.d:ro -e POSTGRES_USER=falcon -e POSTGRES_DB=falcon -e POSTGRES_PASSWORD=falcon_secret --restart on-failure docker.io/postgres:16-alpine 2>$null | Out-Null
    }

    # PostgreSQL Exporter
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-postgres-exporter" }
    if (-not $running) {
        Write-Host "  Starting PostgreSQL Exporter..." -ForegroundColor Gray
        podman run -d --name falcon-postgres-exporter --network falcon -p 9187:9187 -e DATA_SOURCE_NAME="postgresql://falcon:falcon_secret@falcon-postgresql:5432/falcon?sslmode=disable" --restart on-failure docker.io/prometheuscommunity/postgres-exporter:v0.15.0 2>$null | Out-Null
    }

    # Redis
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-redis" }
    if (-not $running) {
        Write-Host "  Starting Redis..." -ForegroundColor Gray
        podman run -d --name falcon-redis --network falcon -p 6379:6379 -v falcon-redis-data:/data --restart on-failure docker.io/redis:7-alpine redis-server --appendonly yes --maxmemory 100mb 2>$null | Out-Null
    }
    
    # Consul
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-consul" }
    if (-not $running) {
        Write-Host "  Starting Consul..." -ForegroundColor Gray
        podman run -d --name falcon-consul --network falcon -p 8500:8500 -p 8600:8600/udp -v falcon-consul-data:/consul/data --restart on-failure docker.io/hashicorp/consul:1.18 agent -dev -ui -client=0.0.0.0 -bind=0.0.0.0 2>$null | Out-Null
    }
    
    # Traefik
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-traefik" }
    if (-not $running) {
        Write-Host "  Starting Traefik..." -ForegroundColor Gray
        podman run -d --name falcon-traefik --network falcon -p 80:80 -p 443:443 -p 8080:8080 -v falcon-traefik-config:/etc/traefik:ro -v falcon-traefik-certs:/certs --restart on-failure docker.io/traefik:v3.2 2>$null | Out-Null
    }
    
    # Prometheus
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-prometheus" }
    if (-not $running) {
        Write-Host "  Starting Prometheus..." -ForegroundColor Gray
        podman run -d --name falcon-prometheus --network falcon -p 9090:9090 -v falcon-prometheus-config:/etc/prometheus:ro -v falcon-prometheus-data:/prometheus --restart on-failure docker.io/prom/prometheus:v2.48.0 --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus 2>$null | Out-Null
    }
    
    # Grafana
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-grafana" }
    if (-not $running) {
        Write-Host "  Starting Grafana..." -ForegroundColor Gray
        podman run -d --name falcon-grafana --network falcon -p 3000:3000 -v falcon-grafana-data:/var/lib/grafana -e GF_SECURITY_ADMIN_PASSWORD=falcon123 -e GF_USERS_ALLOW_SIGN_UP=false --restart on-failure docker.io/grafana/grafana:10.2.0 2>$null | Out-Null
    }
    
    # Website
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-website" }
    if (-not $running) {
        Write-Host "  Starting Website..." -ForegroundColor Gray
        podman run -d --name falcon-website --network falcon -p 8081:80 -v falcon-website-content:/usr/share/nginx/html:ro --restart on-failure docker.io/nginx:alpine 2>$null | Out-Null
    }
    
    # Messenger
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-messenger" }
    if (-not $running) {
        Write-Host "  Starting Messenger..." -ForegroundColor Gray
        podman run -d --name falcon-messenger --network falcon -p 8085:8080 --restart on-failure localhost/falcon-messenger:latest falcon-messenger serve 2>$null | Out-Null
    }

    # Signal Web
    $running = podman ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "falcon-signal-web" }
    if (-not $running) {
        Write-Host "  Starting Signal Web..." -ForegroundColor Gray
        podman run -d --name falcon-signal-web --network falcon -p 5001:5000 -v falcon-signal-web-data:/app/data:Z -e FLASK_ENV=production --restart on-failure localhost/falcon-signal-web:latest 2>$null | Out-Null
    }

    Start-Sleep -Seconds 3
    Write-Success "All containers started"
}

function Stop-FalconContainers {
    Write-Info "Stopping containers..."
    
    foreach ($name in $ContainerNames) {
        podman stop $name 2>$null | Out-Null
    }
    
    Write-Success "Containers stopped"
}

function Show-Status {
    Write-Host ""
    Write-Host "Container Status:" -ForegroundColor Cyan
    Write-Host ""
    podman ps -a --filter "name=falcon-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>$null
    
    Write-Host ""
    Write-Host "Health Checks:" -ForegroundColor Cyan
    Write-Host ""
    
    # PostgreSQL
    try {
        $result = podman exec falcon-postgresql pg_isready -U falcon -d falcon 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Success "PostgreSQL: HEALTHY (localhost:5432)" }
        else { Write-Err "PostgreSQL: UNHEALTHY" }
    } catch { Write-Err "PostgreSQL: NOT RUNNING" }

    # PostgreSQL Exporter
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:9187/metrics" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "PG Exporter: HEALTHY (http://localhost:9187)"
    } catch { Write-Err "PG Exporter: NOT RUNNING" }

    # Redis
    try {
        $result = podman exec falcon-redis redis-cli ping 2>$null
        if ($result -eq "PONG") { Write-Success "Redis: HEALTHY (localhost:6379)" }
        else { Write-Err "Redis: UNHEALTHY" }
    } catch { Write-Err "Redis: NOT RUNNING" }
    
    # Consul
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:8500/v1/status/leader" -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Consul: HEALTHY (http://localhost:8500)"
    } catch { Write-Err "Consul: NOT RUNNING" }
    
    # Traefik
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8080/ping" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Traefik: HEALTHY (http://localhost:8080)"
    } catch { Write-Err "Traefik: NOT RUNNING" }
    
    # Prometheus
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:9090/-/healthy" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Prometheus: HEALTHY (http://localhost:9090)"
    } catch { Write-Err "Prometheus: NOT RUNNING" }
    
    # Grafana
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Grafana: HEALTHY (http://localhost:3000)"
    } catch { Write-Warn "Grafana: Starting... (http://localhost:3000)" }
    
    # Website
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Website: HEALTHY (http://localhost:8081)"
    } catch { Write-Err "Website: NOT RUNNING" }

    # Messenger
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8085/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Messenger: HEALTHY (http://localhost:8085)"
    } catch { Write-Err "Messenger: NOT RUNNING" }

    # Signal Web
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:5001/status" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Success "Signal Web: HEALTHY (http://localhost:5001)"
    } catch { Write-Err "Signal Web: NOT RUNNING" }

    Write-Host ""
}

function Show-URLs {
    Write-Host ""
    Write-Host "Service URLs:" -ForegroundColor Cyan
    Write-Host "  Main Website:       http://localhost:8081" -ForegroundColor White
    Write-Host "  Traefik Dashboard:  http://localhost:8080" -ForegroundColor White
    Write-Host "  Consul UI:          http://localhost:8500" -ForegroundColor White
    Write-Host "  Prometheus:         http://localhost:9090" -ForegroundColor White
    Write-Host "  Grafana:            http://localhost:3000  (admin/falcon123)" -ForegroundColor White
    Write-Host "  Redis:              localhost:6379" -ForegroundColor White
    Write-Host "  PostgreSQL:         localhost:5432  (falcon/falcon_secret)" -ForegroundColor White
    Write-Host "  PG Metrics:         http://localhost:9187/metrics" -ForegroundColor White
    Write-Host "  Messenger:          http://localhost:8085" -ForegroundColor White
    Write-Host "  Signal Web:         http://localhost:5001" -ForegroundColor White
    Write-Host ""
}

function Remove-FalconStack {
    Write-Warn "This will remove ALL Falcon containers, volumes, and data."
    $confirm = Read-Host "Type 'yes' to confirm"
    
    if ($confirm -ne "yes") {
        Write-Info "Cancelled"
        return
    }
    
    Write-Info "Removing containers..."
    foreach ($name in $ContainerNames) {
        podman rm -f $name 2>$null | Out-Null
    }
    
    Write-Info "Removing network..."
    podman network rm falcon 2>$null | Out-Null
    
    Write-Info "Removing volumes..."
    foreach ($vol in $VolumeNames) {
        podman volume rm $vol 2>$null | Out-Null
    }
    
    Write-Info "Removing local files..."
    if (Test-Path $FalconRoot) {
        Remove-Item -Recurse -Force $FalconRoot
    }
    
    Write-Success "Cleanup complete"
}

# Main execution
Show-Banner

switch ($Action) {
    "start" {
        Test-Podman
        Initialize-Directories
        Initialize-ConfigFiles
        Initialize-Volumes
        Copy-ConfigsToVolumes
        Initialize-Network
        Start-FalconContainers
        Show-Status
        Show-URLs
        
        Write-Host "Falcon Gateway is ready!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Open your browser to: http://localhost:8081" -ForegroundColor Cyan
        Write-Host ""
    }
    "stop" {
        Stop-FalconContainers
        Show-Status
    }
    "restart" {
        Stop-FalconContainers
        Start-Sleep -Seconds 2
        Start-FalconContainers
        Show-Status
        Show-URLs
    }
    "status" {
        Show-Status
        Show-URLs
    }
    "clean" {
        Stop-FalconContainers
        Remove-FalconStack
    }
}
