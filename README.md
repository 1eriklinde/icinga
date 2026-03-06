# Icinga2 Monolith Setup

Single-server monitoring stack on Ubuntu 20.04 / 22.04 / 24.04.

## Stack

| Component    | Role                        |
|--------------|-----------------------------|
| Icinga2      | Monitoring engine           |
| IcingaDB     | Database connector          |
| Redis        | Message bus (Icinga ↔ DB)  |
| MariaDB      | Persistent storage          |
| IcingaWeb2   | Web UI                      |
| Apache2+PHP  | Web server                  |
| Go           | Custom integration scripts  |

## Before You Deploy

Both config files live in `scripts/` and are gitignored — they are never committed. Create them from the examples before running `setup.sh`.

### 1. scripts/config.env — connection settings

```bash
cp scripts/config.env.example scripts/config.env
```

Edit `scripts/config.env`:

```bash
ICINGA2_HOST="localhost"          # Icinga2 API host (localhost for monolith)
ICINGA2_PORT="5665"               # Icinga2 API port
ICINGA2_USER="icinga-scripts"     # API user for scripts (created by setup.sh)

QUESTDB_HOST="your-questdb-host"  # hostname or IP of your QuestDB instance
QUESTDB_PORT="9000"               # QuestDB HTTP port

ICINGA2_HOST_TEMPLATE="linux-player"  # host template for imported hosts
ICINGA2_HOST_ZONE=""              # zone for imported hosts — leave blank for monolith
```

### 2. scripts/secrets.env — credentials

```bash
cp scripts/secrets.env.example scripts/secrets.env
```

Edit `scripts/secrets.env`:

```bash
QUESTDB_USER="admin"              # QuestDB username
QUESTDB_PASS="your-password"      # QuestDB password
ICINGA2_PASS=""                   # leave blank — auto-filled by setup.sh
```

`ICINGA2_PASS` is automatically patched in by `setup.sh` after generating the `icinga-scripts` API user.

## Deploy

```bash
sudo bash setup.sh
```

`setup.sh` will:
- Install and configure the full stack
- Auto-generate Icinga2/MariaDB passwords (saved to `/etc/icinga-setup/credentials.env`)
- Create a dedicated `icinga-scripts` API user with minimal permissions (host query/modify only)
- Copy `scripts/` to `/opt/icinga-scripts/` including your config and secrets
- Auto-patch `ICINGA2_PASS` in `/opt/icinga-scripts/secrets.env` with the `icinga-scripts` API password
- Run `import-hosts-questdb.sh` to import hosts from QuestDB (skipped if `QUESTDB_HOST` is `localhost`)

After setup, open: `http://<server-ip>/icingaweb2`
Login: `admin` / password shown in setup output, or `sudo cat /etc/icinga-setup/credentials.env`

You can pre-set the web admin password via environment variable:

```bash
ICINGAWEB_ADMIN_PASS=mypass sudo -E bash setup.sh
```

### HaloITSM notifications (optional)

HaloITSM notifications are **not deployed by default**. To enable them:

```bash
ENABLE_HALO_NOTIFICATIONS=true sudo -E bash setup.sh
```

This copies `icinga2/zones.d/master/notification_apply.conf` and `notification_templates.conf` to `/etc/icinga2/zones.d/master/`, which deploys the notification apply rules, templates, NotificationCommand objects, and the `halo-digital-user`.

You must also fill in the HaloITSM credentials in `scripts/secrets.env` and `scripts/config.env` before or after setup:

```bash
# scripts/config.env
HALO_URL="https://your-instance.haloitsm.com/api/notify/icinga"
ICINGA2_WEB_URL="https://your-icinga2.example.com/icingaweb2"

# scripts/secrets.env
HALO_USER="your-client-id"
HALO_PASS="your-client-secret"
```

The notification scripts (`notify-host-halo.sh`, `notify-service-halo.sh`) are always installed to `/opt/icinga-scripts/` — only the Icinga2 config that wires them in is gated behind the flag.

## Directory Structure

```
icinga/
├── setup.sh                          # Main deployment script (idempotent)
├── icinga2/
│   ├── conf.d/                       # Icinga2 config (copied to /etc/icinga2/conf.d/)
│   │   └── templates.conf            # Defines generic-host, linux-player, notification templates
│   └── zones.d/master/               # Optional: deployed when ENABLE_HALO_NOTIFICATIONS=true
│       ├── notification_templates.conf  # NotificationCommands, templates, halo-digital-user
│       └── notification_apply.conf      # apply Notification rules for host and service
└── scripts/
    ├── config.env.example            # Non-sensitive config template (commit this)
    ├── config.env                    # Your config — gitignored, create from example
    ├── secrets.env.example           # Secrets template (commit this)
    ├── secrets.env                   # Your credentials — gitignored, create from example
    ├── lib.sh                        # Shared helpers (Icinga2 API, QuestDB query)
    ├── import-hosts-questdb.sh       # Import hosts from QuestDB (dry-run supported)
    ├── notify-host-halo.sh           # HaloITSM host notification script
    ├── notify-service-halo.sh        # HaloITSM service notification script
    └── checks/
        └── check-questdb.sh          # QuestDB health check
```

## Host Import from QuestDB

`setup.sh` automatically runs `import-hosts-questdb.sh` after install if `QUESTDB_HOST` is not `localhost`.

The script queries `SELECT DISTINCT host FROM cpu` in QuestDB and creates a passive host object in Icinga2 for each result, using the `linux-player` template (defined in `icinga2/conf.d/templates.conf`).

To re-run manually:

```bash
sudo bash /opt/icinga-scripts/import-hosts-questdb.sh
```

## Adding Hosts Manually

Edit [icinga2/conf.d/hosts.conf](icinga2/conf.d/hosts.conf):

```conf
object Host "my-server" {
  import "generic-host"
  address = "192.168.1.10"
  vars.os = "Linux"
}
```

Then reload:

```bash
sudo icinga2 daemon -C && sudo systemctl reload icinga2
```

## Useful Commands

```bash
# Check Icinga2 config
sudo icinga2 daemon -C

# Reload config (use pkill -HUP on WSL2 where systemctl is unavailable)
sudo systemctl reload icinga2
sudo pkill -HUP icinga2

# View generated credentials
sudo cat /etc/icinga-setup/credentials.env

# Service status
sudo systemctl status icinga2 icingadb redis-server mariadb apache2

# Logs
sudo journalctl -u icinga2 -f
sudo journalctl -u icingadb -f
sudo tail -f /var/log/apache2/error.log

# Icinga2 API test
curl -sSk -u root:<pass> https://localhost:5665/v1/status
```

## Re-deploying

The script is idempotent for package installation. For a fresh re-deploy on a clean machine, just run `setup.sh` again. On an existing machine with data, re-running will reset passwords — back up `/etc/icinga-setup/credentials.env` first.
