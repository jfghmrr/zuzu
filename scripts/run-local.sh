#!/usr/bin/env bash
set -euo pipefail
zuzu_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$zuzu_root/server"
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
.venv/bin/pip install -r requirements.txt
export AUTH_MODE=dev APP_ENV=development
exec .venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000
