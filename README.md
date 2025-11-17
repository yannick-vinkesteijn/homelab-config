# homelab-config

Homelab configs, docker compose, etc.

## Stack overview

### arr
- **bazarr**
- **jellyseerr**
- **lidarr**
- **prowlarr**
- **qbt**
- **radarr**
- **sonarr**

### database
- **influxdb**
- **mariadb**

### homeassistant
- **homeassistant**
- **matter-server**
- **vscode**

### media
- **filebrowser**
- **jellyfin**

### network
- **swag**
- **pangolin**
- **adguardhome**

## Repository layout
- `docker-compose.yaml` – top-level stack orchestration.
- `arr/` – service definitions in `arr/arr.docker-compose.yaml`.
- `database/` – databases in `database/db.docker-compose.yaml`.
- `homeassistant/` – HA stack in `homeassistant/hass.docker-compose.yaml`.
- `media/` – media services in `media/media.docker-compose.yaml`.
- `network/` – perimeter services in `network/network.docker-compose.yaml`.
- `scripts/` – automation helpers.

## Environment files

### `.env`
| Variable | Description |
| --- | --- |
| `PUID` / `PGID` | Runtime user and group IDs for most containers. |
| `UID` / `GID` | System user and group IDs consumed by `homeassistant/hass.docker-compose.yaml`. |
| `TZ` | Time zone, for example `America/New_York`. |
| `INFLUXDB_USER`, `INFLUXDB_PASSWORD`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET`, `INFLUXDB_ADMIN_TOKEN` | InfluxDB credentials. |
| `MYSQL_ROOT_PASSWORD`, `MYSQL_HA_DATABASE`, `MYSQL_HA_USER`, `MYSQL_HA_PASSWORD` | MariaDB and Home Assistant database configuration. |
| `PREFERRED_REGION` | Preferred PIA region consumed by `scripts/get_pia_wireguard_conf.sh`. |
| `DIP_TOKEN` *(optional)* | Dedicated IP token for PIA, defaults to `none`. |
| `VPN_LAN_NETWORK` | LAN CIDR exposed through the VPN gateway. |
| `HOMARR_KEY` | API key for Homarr widgets. |
| `VSCODE_PASSWORD` | Password for the VS Code web UI. |

`VPN_PIA_PREFERRED_REGION` is deprecated. Use `PREFERRED_REGION` instead to avoid script failures.

### `.secrets/pia.env`
Copied from the PIA portal for `scripts/get_pia_wireguard_conf.sh`:

```
PIA_USER=<PIA_USER>
PIA_PASS=<PIA_PASS>
PREFERRED_REGION=<REGION_ID>
DIP_TOKEN=<OPTIONAL_TOKEN>
```

## Scripts
- `scripts/detect_ipv6_prefix_change.sh` – logs IPv6 prefix changes and triggers PIA updates.
- `scripts/setup_ipv6_monitor.sh` – installs the systemd service and timer wrapper for the detector.
- `scripts/update_pihole_ipv6.sh` – rewrites Pi-hole IPv6 records and restarts the container.
- `scripts/set-static-ula.sh` – idempotently adds a static ULA address to the host.
- `scripts/get_pia_wireguard_conf.sh` – fetches WireGuard configuration into `.secrets/pia.conf`.

## Usage
1. Populate `.env` and `.secrets/pia.env` with the values listed above.
2. Pull container images with `docker compose pull`.
3. Launch stacks per directory or top-level with `docker compose up -d`.
4. Enable the IPv6 monitor using `sudo scripts/setup_ipv6_monitor.sh`.

IPv6 tooling writes to `/var/log/ipv6_prefix_monitor.log` and `/var/log/update_pihole_ipv6.log`.

