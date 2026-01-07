# n8n self-host (Docker + Traefik + External Task Runners + Redis)

This repo provides a minimal, reproducible self-hosted n8n setup:

- Traefik reverse proxy + Let's Encrypt
- n8n
- External Task Runners (for Code node isolation / lower main-process memory)
- Redis (optional, independent of n8n unless you wire it in)

## 1) Create a Google Cloud VM (quick checklist)

Create an instance:

- URL: https://console.cloud.google.com/compute/instancesAdd

Machine configuration:

- Region: `europe-north2` (Stockholm)
- Zone: any
- Series: `E2`
- Preset: `e2-medium`

OS and storage:

- Debian Linux 12 or 13
- Disk size: 20GB

Networking (IMPORTANT):

- Firewall: check all
  - Allow HTTP traffic
  - Allow HTTPS traffic
  - Allow Load Balancer Health Checks

Note:

- You _can_ use `e2-micro` for very basic tests, but it’s heavily limited.
- `e2-medium` is a practical default and can host a few additional small services without pain.

## 2) DNS (required for TLS)

Before TLS certificates can be issued, you must set DNS:

- Create/update an A record: `<SUBDOMAIN>.<DOMAIN>` -> `<VM_PUBLIC_IP>`

Traefik will fail TLS issuance until DNS is correct. Once DNS resolves properly, Traefik will retry automatically.

## 3) Install

### Option A: one-liner (recommended for onboarding)

```bash
curl -fsSL https://raw.githubusercontent.com/dcazrael/n8n-selfhost/main/install.sh | bash
```

### Option B: clone + run

```bash
git clone https://github.com/dcazrael/n8n-selfhost.git
cd n8n-selfhost
chmod +x install.sh configure.sh
./install.sh
```

## 4) Configure / Reconfigure

```bash
./configure.sh
cd deploy
sudo docker compose --env-file .env up -d
```

## 5) Logs

```bash
cd deploy
./logs.sh
```
