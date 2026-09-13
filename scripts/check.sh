#!/usr/bin/env bash
set -euo pipefail
zuzu_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$zuzu_root/server"
.venv/bin/python -m pytest tests -q
cd "$zuzu_root/mobile"
flutter analyze
flutter test
