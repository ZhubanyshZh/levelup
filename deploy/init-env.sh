#!/usr/bin/env bash
# Создаёт deploy/.env для сервера: домен по IP и случайные секреты.
# Google Client ID берётся из backend/.env. Запуск: make server-env IP=1.2.3.4
set -euo pipefail

IP="${1:?Укажи IP сервера: make server-env IP=1.2.3.4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/deploy/.env"

if [[ -f "$ENV_FILE" ]]; then
  echo "deploy/.env уже есть — не перезаписываю: в нём ключ шифрования, без него ключи ИИ не расшифровать." >&2
  exit 1
fi

google_ids="$(grep -E '^GOOGLE_CLIENT_IDS=' "$ROOT/backend/.env" 2>/dev/null | cut -d= -f2- || true)"

secrets="$(python3 - <<'PY'
import base64, os, secrets
print(f"POSTGRES_PASSWORD={secrets.token_urlsafe(24)}")
print(f"JWT_SECRET={secrets.token_urlsafe(48)}")
print(f"ENCRYPTION_KEY={base64.urlsafe_b64encode(os.urandom(32)).decode()}")
PY
)"

umask 077
cat > "$ENV_FILE" <<EOF
# Секреты сервера. Создан $(date +%F) командой make server-env. В git не попадает.
# Сохрани копию в менеджере паролей: без ENCRYPTION_KEY ключи ИИ не расшифровать.
DOMAIN=${IP//./-}.sslip.io
GOOGLE_CLIENT_IDS=$google_ids
$secrets
EOF

echo "Создан deploy/.env, домен: ${IP//./-}.sslip.io"
[[ -n "$google_ids" ]] || echo "⚠️  GOOGLE_CLIENT_IDS пуст — вход через Google не заработает. Впиши его в deploy/.env."
