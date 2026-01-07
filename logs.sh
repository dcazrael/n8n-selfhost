#!/usr/bin/env bash
set -euo pipefail
sudo docker compose --env-file .env logs -f --tail=200
