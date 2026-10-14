.PHONY: db api migrate migration test lint format ios ios-open ios-build strings test-kit docker docker-logs docker-stop server-env server-setup deploy server-logs server-backup

# --- Бэкенд ---
db:            ## Поднять Postgres в Docker (порт 5433)
	docker compose up -d db

api:           ## Запустить API с автоперезагрузкой (доступен с iPhone по IP Mac)
	cd backend && uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

migrate:       ## Применить миграции
	cd backend && uv run alembic upgrade head

migration:     ## Создать миграцию: make migration m="add tasks"
	cd backend && uv run alembic revision --autogenerate -m "$(m)"

test:          ## Тесты бэкенда (нужен `make db`)
	cd backend && uv run pytest

lint:
	cd backend && uv run ruff check . && uv run ruff format --check .

format:
	cd backend && uv run ruff check --fix . && uv run ruff format .

docker:        ## Поднять базу и API в фоне, дождаться готовности (миграции автоматические)
	docker compose up -d --build --wait --wait-timeout 180

docker-logs:   ## Логи запросов к контейнеру API
	docker compose logs -f --tail=50 api

docker-stop:   ## Остановить контейнеры; данные базы сохраняются
	docker compose stop

# --- Сервер на VPS (см. README → «Сервер в интернете») ---
server-env:    ## Создать deploy/.env с секретами: make server-env IP=1.2.3.4
	./deploy/init-env.sh $(IP)

server-setup:  ## Подготовить чистый Ubuntu 24.04: make server-setup HOST=root@1.2.3.4
	ssh $(HOST) 'bash -s' < deploy/setup-server.sh

deploy:        ## Выложить бэкенд: make deploy HOST=root@1.2.3.4
	./deploy/deploy.sh $(HOST)

server-logs:   ## Логи API на сервере: make server-logs HOST=root@1.2.3.4
	ssh $(HOST) 'cd /opt/levelup/deploy && docker compose logs --tail=200 -f api'

server-backup: ## Скачать свежий дамп базы в backups/: make server-backup HOST=root@1.2.3.4
	mkdir -p backups
	rsync -az $(HOST):/opt/levelup/backups/ backups/

# --- iOS ---
ios:           ## Сгенерировать Xcode-проект из ios/project.yml
	cd ios && xcodegen generate

ios-open: ios
	open ios/LevelUp.xcodeproj

ios-build: ios  ## Собрать приложение для симулятора
	cd ios && xcodebuild -project LevelUp.xcodeproj -scheme LevelUp -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build -quiet

strings:       ## Проверить, что у всех строк интерфейса есть перевод (после сборки)
	python3 ios/scripts/check_strings.py

test-kit:      ## Тесты LevelUpKit
	cd ios/LevelUpKit && swift test
