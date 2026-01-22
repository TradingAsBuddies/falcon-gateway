# Falcon Gateway

Infrastructure gateway stack for the Falcon Trading Platform. Provides API routing, service discovery, message queuing, and observability.

## Architecture

```
                         ┌─────────────────────────────────────┐
                         │          falcon-gateway             │
    Internet ──────────▶ │                                     │
                         │  ┌─────────┐      ┌─────────┐       │
                         │  │ Traefik │      │  Redis  │       │
                         │  │ :80/443 │      │  :6379  │       │
                         │  └────┬────┘      └────┬────┘       │
                         │       │                │            │
                         │  ┌────┴────┐      ┌────┴────┐       │
                         │  │ Consul  │      │Prometheus│      │
                         │  │  :8500  │      │  :9090  │       │
                         │  └─────────┘      └────┬────┘       │
                         │                   ┌────┴────┐       │
                         │                   │ Grafana │       │
                         │                   │  :3000  │       │
                         └───────────────────┴─────────┴───────┘
                                        │
            ┌───────────────────────────┼───────────────────────────┐
            ▼                           ▼                           ▼
   falcon-dashboard            falcon-screener              falcon-trader
   (192.168.1.162)             (192.168.1.232)             (192.168.1.232)
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| **Traefik** | 80, 443, 8080 | API gateway, TLS termination, load balancing |
| **Redis** | 6379 | Message queue (Redis Streams), caching |
| **Consul** | 8500, 8600 | Service discovery, health checks, DNS |
| **Prometheus** | 9090 | Metrics collection and alerting |
| **Grafana** | 3000 | Dashboards and visualization |

## Quick Start

### Local Development (Windows + Podman Desktop)

```powershell
# Clone the repo
git clone https://github.com/davdunc/falcon-gateway.git
cd falcon-gateway

# Start the stack
.\scripts\Setup-FalconGateway.ps1 start

# Check status
.\scripts\Setup-FalconGateway.ps1 status

# Open in browser
start http://localhost:8081
```

### Production (Fedora IoT on Raspberry Pi)

```bash
# On the Pi
cd /opt/falcon-gateway

# Deploy using Quadlet
sudo cp quadlet/*.{container,network} /etc/containers/systemd/
sudo cp -r configs/* /etc/falcon/
sudo systemctl daemon-reload
sudo systemctl start falcon-redis falcon-consul falcon-traefik falcon-prometheus falcon-grafana
```

## Repository Structure

```
falcon-gateway/
├── README.md
├── LICENSE
├── .gitignore
│
├── configs/                    # Service configurations
│   ├── traefik/
│   │   ├── traefik.yml        # Static config
│   │   └── dynamic/
│   │       └── routes.yml     # Dynamic routing rules
│   ├── prometheus/
│   │   └── prometheus.yml     # Scrape config
│   └── grafana/
│       └── provisioning/
│           ├── dashboards/
│           └── datasources/
│
├── quadlet/                    # Podman Quadlet definitions (for Pi)
│   ├── falcon.network
│   ├── redis.container
│   ├── consul.container
│   ├── traefik.container
│   ├── prometheus.container
│   └── grafana.container
│
├── scripts/                    # Setup and management scripts
│   ├── Setup-FalconGateway.ps1    # Windows/Podman Desktop
│   └── deploy-to-pi.sh            # Deploy to Raspberry Pi
│
├── website/                    # Landing page
│   └── index.html
│
└── docs/                       # Documentation
    ├── LOCAL_SETUP.md
    ├── PI_DEPLOYMENT.md
    └── ARCHITECTURE.md
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FALCON_DOMAIN` | `localhost` | Domain for TLS certificates |
| `GRAFANA_ADMIN_PASSWORD` | `falcon123` | Grafana admin password |
| `ACME_EMAIL` | - | Email for Let's Encrypt |

### Traefik Routes

Edit `configs/traefik/dynamic/routes.yml` to add new services:

```yaml
http:
  routers:
    my-service:
      rule: "Host(`myservice.falcon.localhost`)"
      service: my-service-svc
      entryPoints:
        - web

  services:
    my-service-svc:
      loadBalancer:
        servers:
          - url: "http://my-service:8000"
```

## Message Queue (Redis Streams)

Services communicate via Redis Streams:

```python
import redis

r = redis.Redis(host='falcon-gateway', port=6379)

# Producer (falcon-screener)
r.xadd('screener.results', {'profile': 'Momentum', 'stocks': '["AAPL","NVDA"]'})

# Consumer (falcon-trader)
messages = r.xread({'screener.results': '$'}, block=5000)
```

### Stream Channels

| Stream | Producer | Consumer | Purpose |
|--------|----------|----------|---------|
| `screener.results` | falcon-screener | falcon-trader | Stock screening results |
| `trade.signals` | falcon-trader | falcon-executor | Trade execution signals |
| `trade.status` | falcon-executor | falcon-dashboard | Execution status updates |

## Service Discovery (Consul)

Register services with Consul for dynamic discovery:

```bash
curl -X PUT http://falcon-gateway:8500/v1/agent/service/register \
  -d '{
    "Name": "falcon-dashboard",
    "Address": "192.168.1.162",
    "Port": 5000,
    "Check": {"HTTP": "http://192.168.1.162:5000/health", "Interval": "10s"}
  }'
```

## Monitoring

### Prometheus Metrics

- **Traefik**: Request rates, latencies, error rates
- **Redis**: Memory usage, connections, commands/sec
- **Consul**: Service health, cluster status

### Grafana Dashboards

Default credentials: `admin` / `falcon123`

Pre-configured dashboards:
- Falcon Overview
- Traefik Metrics
- Redis Performance

## Deployment Targets

| Environment | Platform | Config Location |
|-------------|----------|-----------------|
| Local Dev | Windows + Podman Desktop | `~/falcon-dev/` |
| Production | Fedora IoT (Pi 4) | `/etc/falcon/` |

## Related Repositories

- [falcon-screener](https://github.com/davdunc/falcon-screener) - Stock screening service
- [falcon-trader](https://github.com/davdunc/falcon-trader) - Trading execution service
- [falcon-dashboard](https://github.com/davdunc/falcon-dashboard) - Web dashboard

## License

MIT License - see [LICENSE](LICENSE)
