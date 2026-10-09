#!/usr/bin/env bash
# Выкладывает бэкенд на VPS и перезапускает его. Миграции применяются при старте API.
# Запуск: make deploy HOST=root@1.2.3.4
set -euo pipefail

HOST="${1:?Укажи сервер: make deploy HOST=root@1.2.3.4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE=/opt/levelup

if [[ ! -f "$ROOT/deploy/.env" ]]; then
  echo "Нет deploy/.env — сначала make server-env IP=…" >&2
  exit 1
fi
DOMAIN="$(grep -E '^DOMAIN=' "$ROOT/deploy/.env" | cut -d= -f2-)"

echo "→ Копирую код на $HOST"
rsync -az --delete \
  --exclude .venv --exclude __pycache__ --exclude .pytest_cache --exclude .ruff_cache \
  --exclude .env --exclude tests \
  "$ROOT/backend/" "$HOST:$REMOTE/backend/"
rsync -az --delete "$ROOT/deploy/" "$HOST:$REMOTE/deploy/"
ssh "$HOST" "chmod 600 $REMOTE/deploy/.env"

echo "→ Собираю и перезапускаю"
ssh "$HOST" "cd $REMOTE/deploy && docker compose up -d --build --remove-orphans && docker image prune -f >/dev/null"

echo "→ Жду https://$DOMAIN/health"
for _ in $(seq 1 30); do
  if health="$(curl -fsS --max-time 5 "https://$DOMAIN/health" 2>/dev/null)"; then
    echo "✓ $health"
    exit 0
  fi
  sleep 3
done
echo "Сервер не ответил за 90 с. Логи: make server-logs HOST=$HOST" >&2
exit 1
