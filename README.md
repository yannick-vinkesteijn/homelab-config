# homelab-config

Homelab configs, docker compose, etc.

## Stack overview

These are included in the top-level `docker-compose.yaml` and currently running:

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
- **tsdproxy** and the **Technitium DNS server** are commented out and not deployed yet. Technitium is the plan, see the `.env` table below.

### system
- **homarr**
- **portainer**

### home
- Nothing active right now. **mealie** is defined here but commented out in `home/home.docker-compose.yaml`.

These aren't part of the top-level orchestration and don't run on this host:
- `social/social.docker-compose.yaml`: the Mastodon stack (db, web, streaming, sidekiq).
- `vps/pangolin.docker-compose.yaml`: Pangolin, Traefik, CrowdSec, and Gerbil. Runs on the separate VPS, not here. See [docs/pangolin-setup.md](docs/pangolin-setup.md).

## Repository layout
- `docker-compose.yaml`: top-level orchestration. Includes `system/`, `network/`, `database/`, `media/`, `arr/`, and `home/`.
- `arr/`: service definitions in `arr/arr.docker-compose.yaml`.
- `database/`: databases in `database/db.docker-compose.yaml`.
- `media/`: media services in `media/media.docker-compose.yaml`.
- `network/`: perimeter services in `network/network.docker-compose.yaml`.
- `system/`: host-management services in `system/sys.docker-compose.yaml`.
- `home/`: home-related services in `home/home.docker-compose.yaml`. Nothing active right now.
- `social/`: standalone Mastodon stack, not part of the top-level orchestration.
- `vps/`: the Pangolin stack that runs on the separate VPS, not part of the top-level orchestration. `config.example.yml` is a sanitized template. The real `config.yml` has a live secret in it and stays on the VPS only, gitignored.
- `scripts/`: automation helpers.
- `docs/`: setup guides and troubleshooting notes.

Home Assistant doesn't run from this repo. See "Where is Home Assistant?" below.

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
| `PREFERRED_REGION` | Preferred PIA region, consumed by `scripts/get_pia_wireguard_conf.sh`. |
| `DIP_TOKEN` *(optional)* | Dedicated IP token for PIA, defaults to `none`. |
| `HOMARR_KEY` | API key for Homarr widgets. |
| `PANGOLIN_ENDPOINT` | Pangolin server URL, e.g. `https://pangolin.<your-domain>`. |
| `NEWT_ID` | Newt site ID from Pangolin. |
| `NEWT_SECRET` | Newt site secret from Pangolin. |
| `MEALIE_DEFAULT_EMAIL`, `MEALIE_DEFAULT_PASSWORD`, `MEALIE_BASE_URL` *(optional)* | Only used if the commented-out `mealie` service in `home/home.docker-compose.yaml` gets enabled. |
| `TAILSCALE_KEY`, `TAILSCALE_HOSTNAME` | Only used if the commented-out `tsdproxy` service in `network/network.docker-compose.yaml` gets enabled. |
| `DNS_SERVER_ADMIN_PASSWORD`, `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD` | Only used if the commented-out Technitium `dns-server` service in `network/network.docker-compose.yaml` gets enabled. |

`VPN_PIA_PREFERRED_REGION` is deprecated. Use `PREFERRED_REGION` instead, otherwise the scripts fail.

### `.secrets/pia.env`
Copied from the PIA portal for `scripts/get_pia_wireguard_conf.sh`:

```
PIA_USER=<PIA_USER>
PIA_PASS=<PIA_PASS>
PREFERRED_REGION=<REGION_ID>
DIP_TOKEN=<OPTIONAL_TOKEN>
```

## Scripts
- `scripts/detect_ipv6_prefix_change.sh`: logs IPv6 prefix changes on the WAN interface.
- `scripts/setup_ipv6_monitor.sh`: installs the systemd service and timer wrapper for the detector.
- `scripts/get_pia_wireguard_conf.sh`: fetches WireGuard configuration into `.secrets/pia.conf`.
- `scripts/setup_nvme.sh`: one-time partition/format/mount for the NVMe enclosure. See [docs/nvme-setup-guide.md](docs/nvme-setup-guide.md).

## Usage
1. Populate `.env` and `.secrets/pia.env` with the values listed above.
2. Pull container images with `docker compose pull`.
3. Launch stacks per directory or top-level with `docker compose up -d`.
4. Enable the IPv6 monitor using `sudo scripts/setup_ipv6_monitor.sh`.

IPv6 tooling writes to `/var/log/ipv6_prefix_monitor.log`.

## VPS & Pangolin

Hetzner CX22 running [Pangolin](https://pangolin.dev) as a tunneled reverse proxy for publicly exposed services (Jellyfin, Jellyseerr). It hides the homelab's IP behind the VPS.

Pangolin also sidesteps Cloudflare's restrictions on proxying video/streaming traffic through their free tier, which would otherwise get Jellyfin flagged or throttled.

See [docs/pangolin-setup.md](docs/pangolin-setup.md) for full setup details: VPS hardening, DNS, Newt configuration, and troubleshooting.

## Where is Home Assistant?

I started with Home Assistant docker however I found it to be unstable and difficult to manage. I switched to a dedicated server running Home Assistant OS, which has been rock solid. It also has the benefit of keeping Home Assistant separate from the rest of the stack, which is nice for security and stability.

The main driver was Docker's flaky USB passthrough for the Zigbee/Matter antennas (ZBT-2, Sonoff dongle). Device paths would drop or shift on container restart or host reboot, causing intermittent disconnects. Running HAOS directly on dedicated hardware avoids that entirely.

### Architecture
```
Internet → <your-domain> → VPS (Pangolin/Traefik) → WireGuard tunnel → Homelab (Newt) → services
```

Services routed through Pangolin:
- `social.<your-domain>`: Mastodon, port 3000.
- Future: Jellyfin, Jellyseerr, etc.

Everything else (Portainer, Sonarr, Radarr, etc.) is local network only. No Tailscale or other remote-access layer right now, just Pangolin for the services that need to be public.

## Troubleshooting

### Flashing Home Assistant connect ZBT-2 
If you have trouble flashing the ZBT-2 through home assistant, you can use the web flashing tool <https://toolbox.openhomefoundation.org/home-assistant-connect-zbt-2/install/>
