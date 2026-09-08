# homelab-config

Homelab configs, docker compose, etc.

## Stack overview

Included in the top-level `docker-compose.yaml` (`include:` list) and currently running:

### arr
- **bazarr**
- **flaresolverr**
- **kapowarr**
- **lidarr**
- **prowlarr**
- **qbittorrent**
- **radarr**
- **seerr** (Overseerr/Jellyseerr-compatible replacement)
- **sonarr**

### database
- **influxdb**
- **mariadb**

### media
- **filebrowser**
- **jellyfin**
- **komga**

### network
- **newt** (Pangolin tunnel client)
- commented out, not currently deployed: **tsdproxy**, **Technitium DNS server** (planned — see `.env` note below)

### system
- **homarr**
- **portainer**

### home
- currently empty — **mealie** is defined but commented out in `home/home.docker-compose.yaml`

Not included in the top-level orchestration (standalone, not deployed on this host):
- **social/social.docker-compose.yaml** — Mastodon stack (db, web, streaming, sidekiq)
- **vps/pangolin.docker-compose.yaml** — Pangolin + Traefik + CrowdSec + Gerbil, runs on the separate VPS, not the homelab host. See [docs/pangolin-setup.md](docs/pangolin-setup.md).

## Repository layout
- `docker-compose.yaml` – top-level stack orchestration, includes `system/`, `network/`, `database/`, `media/`, `arr/`, `home/`.
- `arr/` – service definitions in `arr/arr.docker-compose.yaml`.
- `database/` – databases in `database/db.docker-compose.yaml`.
- `media/` – media services in `media/media.docker-compose.yaml`.
- `network/` – perimeter services in `network/network.docker-compose.yaml`.
- `system/` – host-management services in `system/sys.docker-compose.yaml`.
- `home/` – home-related services in `home/home.docker-compose.yaml` (currently none active).
- `social/` – standalone Mastodon stack, not part of the top-level orchestration.
- `vps/` – Pangolin stack that runs on the separate VPS, not part of the top-level orchestration. `config.example.yml` is a sanitized template — the real `config.yml` (with a live secret) stays on the VPS only, gitignored.
- `scripts/` – automation helpers.
- `docs/` – setup guides and troubleshooting notes.

Home Assistant is not run from this repo — see "Where is Home Assistant?" below.

## Environment files

### `.env`
| Variable | Description |
| --- | --- |
| `PUID` / `PGID` | Runtime user and group IDs for most containers. |
| `TZ` | Time zone, for example `America/New_York`. |
| `INFLUXDB_USER`, `INFLUXDB_PASSWORD`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET` | InfluxDB credentials. |
| `MYSQL_ROOT_PASSWORD`, `MYSQL_HA_DATABASE`, `MYSQL_HA_USER`, `MYSQL_HA_PASSWORD` | MariaDB credentials and database configuration. |
| `VPN_PIA_USER`, `VPN_PIA_PASS` | PIA VPN credentials for qBittorrent. |
| `VPN_LAN_NETWORK` | LAN CIDR exposed through the VPN gateway. |
| `PREFERRED_REGION` | Preferred PIA region consumed by `scripts/get_pia_wireguard_conf.sh`. |
| `DIP_TOKEN` *(optional)* | Dedicated IP token for PIA, defaults to `none`. |
| `HOMARR_KEY` | API key for Homarr widgets. |
| `PANGOLIN_ENDPOINT` | Pangolin server URL, e.g. `https://pangolin.<your-domain>`. |
| `NEWT_ID` | Newt site ID from Pangolin. |
| `NEWT_SECRET` | Newt site secret from Pangolin. |
| `MEALIE_DEFAULT_EMAIL`, `MEALIE_DEFAULT_PASSWORD`, `MEALIE_BASE_URL` *(optional)* | Only used if the commented-out `mealie` service in `home/home.docker-compose.yaml` is enabled. |
| `TAILSCALE_KEY`, `TAILSCALE_HOSTNAME` | Only used if the commented-out `tsdproxy` service in `network/network.docker-compose.yaml` is enabled. |
| `DNS_SERVER_ADMIN_PASSWORD`, `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD` | Only used if the commented-out Technitium `dns-server` service in `network/network.docker-compose.yaml` is enabled. |

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
- `scripts/detect_ipv6_prefix_change.sh` – logs IPv6 prefix changes on the WAN interface.
- `scripts/setup_ipv6_monitor.sh` – installs the systemd service and timer wrapper for the detector.
- `scripts/get_pia_wireguard_conf.sh` – fetches WireGuard configuration into `.secrets/pia.conf`.
- `scripts/setup_nvme.sh` – one-time partition/format/mount for the NVMe enclosure, see [docs/nvme-setup-guide.md](docs/nvme-setup-guide.md).

## Usage
1. Populate `.env` and `.secrets/pia.env` with the values listed above.
2. Pull container images with `docker compose pull`.
3. Launch stacks per directory or top-level with `docker compose up -d`.
4. Enable the IPv6 monitor using `sudo scripts/setup_ipv6_monitor.sh`.

IPv6 tooling writes to `/var/log/ipv6_prefix_monitor.log` and `/var/log/update_pihole_ipv6.log`.

## VPS & Pangolin

Hetzner CX22 running [Pangolin](https://pangolin.dev) as a tunneled reverse proxy for publicly exposed services (Jellyfin, Jellyseerr). Hides the homelab's IP behind the VPS.

See [docs/pangolin-setup.md](docs/pangolin-setup.md) for full setup details including VPS hardening, DNS, Newt configuration, and troubleshooting.

## Where is Home Assistant?

I started with Home Assistant docker however I found it to be unstable and difficult to manage. I switched to a dedicated server running Home Assistant OS, which has been rock solid. It also has the benefit of keeping Home Assistant separate from the rest of the stack, which is nice for security and stability.

The main driver was Docker's flaky USB passthrough for the Zigbee/Matter antennas (ZBT-2, Sonoff dongle) — device paths would drop or shift on container restart/host reboot, causing intermittent disconnects. Running HAOS directly on dedicated hardware avoids that entirely.

### Architecture
```
Internet → <your-domain> → VPS (Pangolin/Traefik) → WireGuard tunnel → Homelab (Newt) → services
```

Services routed through Pangolin:
- `social.<your-domain>` → Mastodon (port 3000)
- Future: Jellyfin, Jellyseerr, etc.

Admin-only services stay on Tailscale (tsdproxy): Portainer, Sonarr, Radarr, etc.

## Troubleshooting

### Flashing Home Assistant connect ZBT-2 
If you have trouble flashing the ZBT-2 through home assistant, you can use the web flashing tool <https://toolbox.openhomefoundation.org/home-assistant-connect-zbt-2/install/>