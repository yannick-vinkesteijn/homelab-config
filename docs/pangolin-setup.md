# Pangolin Setup

Pangolin is a self-hosted tunneled reverse proxy that exposes homelab services publicly without revealing the homelab's IP address. Traffic flows through a VPS running Pangolin, which tunnels requests to the homelab via WireGuard.

## Architecture

```
Internet → VPS (Pangolin + Traefik) → WireGuard tunnel → Homelab (Newt) → Local services
```

- **Pangolin** runs on the VPS and handles TLS termination, routing, and authentication.
- **Newt** runs on the homelab and creates an outbound WireGuard tunnel to the VPS. No port forwarding needed on the home network.
- **Traefik** (bundled with Pangolin) routes subdomains to the correct backend service.

## VPS Setup

### Server details
| Setting | Value |
| --- | --- |
| Provider | Hetzner Cloud |
| Plan | CX22 (2 vCPU, 4GB RAM) |
| Location | Falkenstein |
| OS | Ubuntu 24.04 |
| Hostname | helms-deep |

### Initial hardening
1. Create a non-root user with sudo access.
2. Copy SSH public key to `~/.ssh/authorized_keys`.
3. Disable root login: `PermitRootLogin no` in `/etc/ssh/sshd_config`.
4. Disable password auth: `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/50-cloud-init.conf` (Ubuntu 24.04 uses a cloud-init override that takes precedence over the main config).
5. Restart SSH: `sudo systemctl restart ssh`.
6. Install fail2ban: `sudo apt install -y fail2ban && sudo systemctl enable --now fail2ban`.

### Firewall
```bash
sudo ufw allow 80/tcp    # HTTP (Let's Encrypt challenges)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 51820/udp # WireGuard (Gerbil)
sudo ufw allow 21820/udp # WireGuard (client connections)
sudo ufw reload
```

## DNS

Point the base domain and a wildcard to the VPS IP:

| Type | Name | Value |
| --- | --- | --- |
| A | `vinkels.dev` | `<VPS_IP>` |
| A | `*.vinkels.dev` | `<VPS_IP>` |

## Pangolin Installation

```bash
curl -fsSL https://setup.pangolin.dev | sudo bash
```

The installer asks for:
- **Base domain:** `vinkels.dev`
- **Admin email:** used for Let's Encrypt certificates
- **Gerbil (WireGuard tunneling):** Yes
- **CrowdSec:** Yes (recommended, can also be added later by re-running the installer)

After installation, visit `https://pangolin.vinkels.dev` to complete setup.

### Organization & Site

1. **Create Organization** — display name and identifier for grouping sites and resources.
2. **Create Site** — select "Newt" type. This generates the Newt credentials (endpoint, ID, secret).

## Newt (Homelab Side)

Newt is the tunnel agent that runs on the homelab and connects outbound to Pangolin.

### Docker Compose

Defined in `network/network.docker-compose.yaml`:

```yaml
newt:
  image: fosrl/newt
  container_name: newt
  restart: unless-stopped
  network_mode: host
  environment:
    - PANGOLIN_ENDPOINT=https://pangolin.vinkels.dev
    - NEWT_ID=${NEWT_ID}
    - NEWT_SECRET=${NEWT_SECRET}
```

### Why `network_mode: host`?

Newt needs to reach local services by their host LAN IP (e.g., `192.168.86.66`). In the default Docker bridge network, Newt cannot route to the host's LAN IP — connections time out. Host networking gives Newt direct access to the host's network stack, so all local service IPs are reachable.

### Environment variables

`NEWT_ID` and `NEWT_SECRET` are stored in the root `.env` file (gitignored). These are generated when creating a site in Pangolin. Regenerate them in Pangolin → Sites → (site name) if they are ever exposed.

## Adding Resources

Resources are individual services exposed through Pangolin.

1. In the Pangolin UI, go to **Resources → Add Resource**.
2. Enter a name and subdomain (e.g., `jellyfin` creates `jellyfin.vinkels.dev`).
3. Select the site where the service runs.
4. Choose **HTTP Resource**.
5. Set the target to the service's LAN IP and port (e.g., `http://192.168.86.66:8096`).
6. Enable **Health Check** to monitor availability.

### Current resources

| Service | Subdomain | Target |
| --- | --- | --- |
| Jellyfin | `jellyfin.vinkels.dev` | `http://192.168.86.66:8096` |
| Jellyseerr | `jellyseerr.vinkels.dev` | `http://192.168.86.66:5055` |

### Authentication

Pangolin supports multiple auth methods per resource: Platform SSO, password, PIN, 2FA, and temporary share links. Configure in the resource's Authentication tab. Disable SSO for public resources.

## Troubleshooting

### Newt shows "Offline" in Pangolin
- Check container is running: `docker ps | grep newt`
- Check logs: `docker logs newt`
- Verify firewall ports 51820/udp and 21820/udp are open on the VPS

### Health check fails / "no available server"
- Verify target IP and port are reachable from inside the Newt container
- If using bridge networking, Newt may not be able to reach the host LAN IP — switch to `network_mode: host`
- A failing health check removes the target from Traefik's routing pool, causing 503 errors. Disable the health check temporarily to confirm this is the issue.

### Page loads forever but no errors
- Check Newt logs for `Error connecting to target: connection timed out`
- This usually means the target IP is unreachable from Newt's network context

## CrowdSec

CrowdSec is a collaborative intrusion detection system that analyzes Traefik access logs and automatically blocks malicious IPs. It includes a community blocklist of known-bad IPs shared across all CrowdSec users.

### What it protects

```
Internet
  → UFW firewall (ports 80, 443, 51820, 21820 only)
  → CrowdSec firewall bouncer (blocks known-bad IPs at network level, including SSH)
  → fail2ban (SSH brute-force protection)
  → Traefik + CrowdSec bouncer plugin (blocks web attacks before they reach services)
  → Pangolin (routing + optional SSO)
  → Services (Jellyfin, Jellyseerr)
```

### Installation

CrowdSec can be installed via the Pangolin installer. If skipped during initial install, re-run the installer — it detects the existing installation and only adds CrowdSec:

```bash
cd /opt/pangolin
sudo docker compose down
curl -fsSL https://setup.pangolin.dev -o installer && chmod +x installer
sudo ./installer
# Select "Yes" for CrowdSec when prompted
```

The installer adds:
- **CrowdSec container** — detection engine that reads Traefik access logs
- **Traefik bouncer plugin (Badger)** — blocks banned IPs at the reverse proxy level
- **Log rotation** — daily rotation of Traefik access logs, keeping 7 compressed copies

### SSH firewall bouncer

The Traefik bouncer only protects web traffic. To also protect SSH and block known-bad IPs at the network level, install the firewall bouncer on the VPS host:

1. Install the CrowdSec repo and firewall bouncer:
   ```bash
   curl -s https://install.crowdsec.net | sudo sh
   sudo apt install crowdsec-firewall-bouncer-iptables
   ```

2. The bouncer auto-registers with CrowdSec and generates an API key. Verify:
   ```bash
   sudo grep api_key /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
   sudo grep api_url /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
   ```
   `api_url` should be `http://127.0.0.1:8080/`.

3. Expose CrowdSec's local API port (localhost only) in `/opt/pangolin/docker-compose.yml` under the `crowdsec` service:
   ```yaml
   ports:
     - 127.0.0.1:8080:8080
   ```

4. If a metrics port (6060) is also exposed, bind it to localhost too:
   ```yaml
   ports:
     - 127.0.0.1:6060:6060
     - 127.0.0.1:8080:8080
   ```

5. Restart:
   ```bash
   sudo docker compose up -d
   sudo systemctl restart crowdsec-firewall-bouncer
   ```

6. Verify both bouncers are connected:
   ```bash
   sudo docker exec crowdsec cscli metrics
   ```
   Look for `traefik-bouncer` and `vps-firewall` in the bouncers table.

### If the firewall bouncer fails to connect

If `sudo systemctl status crowdsec-firewall-bouncer` shows "bouncer stream halted":
1. Delete and recreate the bouncer registration:
   ```bash
   sudo docker exec crowdsec cscli bouncers delete vps-firewall
   sudo docker exec crowdsec cscli bouncers add vps-firewall
   ```
2. Update the API key in `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`.
3. Restart: `sudo systemctl restart crowdsec-firewall-bouncer`.

### Privacy

CrowdSec sends minimal signal data to its central API (attacker IPs, triggered scenarios, timestamps). It does **not** send traffic content, URLs, or user data. In return, you receive the community blocklist. This can be disabled for local-only operation if needed.

## Geo-blocking

Pangolin supports geo-blocking per resource using the MaxMind GeoLite2 database. The installer downloads the database automatically.

### Configuring rules

In the Pangolin UI, go to a resource → **Rules** tab. Block regions where you don't expect users:

**Blocked regions:** Asia, Africa, South America, North America, Oceania, Eastern Europe
**Allowed:** Western Europe, Northern Europe, Southern Europe

Apply the same rules to each publicly exposed resource (Jellyfin, Jellyseerr, etc.).

### GeoIP database updates

The MaxMind database gets stale over time as IP-to-country mappings change. A cron job on the VPS updates it monthly:

**Script:** `/opt/pangolin/update-geoip.sh`
```bash
#!/bin/bash
set -e
cd /opt/pangolin
curl -sL -o GeoLite2-Country.tar.gz https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/GeoLite2-Country.tar.gz
tar -xzf GeoLite2-Country.tar.gz
mv GeoLite2-Country_*/GeoLite2-Country.mmdb config/
rm -rf GeoLite2-Country.tar.gz GeoLite2-Country_*
docker compose restart pangolin
echo "$(date): GeoIP database updated" >> /var/log/geoip-update.log
```

**Cron job:** `/etc/cron.d/geoip-update`
```
0 3 1 * * root /opt/pangolin/update-geoip.sh
```

Runs on the 1st of each month at 3am UTC. Logs to `/var/log/geoip-update.log`.
