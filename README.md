# Level Up

Одно iOS-приложение для задач, дневника, целей, покупок, финансов и тренировок: ввод голосом или текстом, ИИ раскладывает всё по местам, а прогресс превращается в уровень.

Полный план — [docs/PLAN.md](docs/PLAN.md).

## Структура

```
backend/     FastAPI + PostgreSQL (Python 3.13, uv, SQLAlchemy, Alembic)
ios/         SwiftUI-приложение; Xcode-проект генерируется XcodeGen из ios/project.yml
  LevelUp/         приложение
  LevelUpWidgets/  виджеты
  LevelUpKit/      общий Swift-пакет: API-клиент, модели, токены, данные для виджетов
deploy/      сервер на VPS: Docker Compose + Caddy, скрипты выкладки
docs/        план и решения
```

## Что нужно на Mac

Xcode 26+, Docker, [uv](https://docs.astral.sh/uv/) и [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install uv xcodegen
```

## Запуск

1. Сервер:

   ```bash
   cp backend/.env.example backend/.env   # и заполнить JWT_SECRET
   make db
   make migrate
   make api
   ```

   Проверка: http://localhost:8000/health, документация API: http://localhost:8000/docs.

2. Приложение:

   ```bash
   cp ios/Config/Local.example.xcconfig ios/Config/Local.xcconfig   # и заполнить
   make ios-open
   ```

   В Xcode выбрать симулятор или iPhone и нажать Run.

## Запуск на iPhone

- В `ios/Config/Local.xcconfig`:
  - `DEVELOPMENT_TEAM` — **личный Personal Team**, не командный аккаунт компании;
  - `API_BASE_URL` — IP Mac в той же Wi-Fi сети, например `http:/$()/192.168.0.54:8000`. IP можно узнать командой `ipconfig getifaddr en0`.
- После правок в `Local.xcconfig` или `project.yml` нужно снова выполнить `make ios`.
- При первом запуске на iPhone:
  - разрешить доступ к локальной сети;
  - если iOS попросит, довериться разработчику: Настройки → Основные → VPN и управление устройством.
- Сборка на бесплатном Personal Team работает 7 дней. Потом снова Run из Xcode.

## Сервер в интернете

Чтобы приложение работало не только в домашнем Wi-Fi, сервер живёт на VPS. В `deploy/` лежат Postgres, API и Caddy: Caddy сам получает HTTPS-сертификат. Раз в сутки делается дамп базы, дампы хранятся 14 дней.

1. Купить VPS с **Ubuntu 24.04** (например, Hetzner CX22, ~€4/мес). При создании добавить свой SSH-ключ (`cat ~/.ssh/id_ed25519.pub`).
2. Создать секреты сервера. Домен получится вида `1-2-3-4.sslip.io` (бесплатный, указывает на IP сервера):

   ```bash
   make server-env IP=<IP сервера>
   ```

   Сохрани `deploy/.env` в менеджере паролей. Без `ENCRYPTION_KEY` ключи ИИ не расшифровать.
3. Подготовить сервер (один раз): Docker, файрвол, автообновления.

   ```bash
   make server-setup HOST=root@<IP сервера>
   ```

4. Выложить. Эту же команду повторять после каждого изменения бэкенда:

   ```bash
   make deploy HOST=root@<IP сервера>
   ```

5. В `ios/Config/Local.xcconfig`: `API_BASE_URL = https:/$()/<домен из deploy/.env>`. Затем `make ios` и Run.

На сервере начинается чистая база: войти заново и снова ввести ключ ИИ.

Полезное:
- `make server-logs HOST=…` — логи API;
- `make server-backup HOST=…` — скачать дампы в `backups/`.

## Вход через Google

1. Открыть [Google Cloud Console](https://console.cloud.google.com/) и создать проект «Level Up».
2. **Google Auth Platform → Audience:** тип External. Добавить свой email в Test users (или опубликовать приложение — для базовых прав входа проверка Google не нужна).
3. **Clients → Create client → iOS**, Bundle ID: значение `BUNDLE_ID_PREFIX` из `Local.xcconfig` + `.levelup` (сейчас `com.zharylkasynov.levelup`).
4. Скопировать значения из созданного клиента:
   - **Client ID** → `GOOGLE_CLIENT_ID` в `ios/Config/Local.xcconfig` и `GOOGLE_CLIENT_IDS` в `backend/.env`;
   - **iOS URL scheme** → `GOOGLE_REVERSED_CLIENT_ID` в `ios/Config/Local.xcconfig`.
5. Перезапустить сервер и выполнить `make ios`.

## ИИ-помощник

Каждый пользователь подключает свой ключ: «Ещё → ИИ-помощник».

- **Gemini (бесплатно):** [Google AI Studio](https://aistudio.google.com/apikey) → Create API key.
- **OpenAI (платно):** [platform.openai.com/api-keys](https://platform.openai.com/api-keys).

Ключ уходит на сервер один раз и хранится зашифрованным (`ENCRYPTION_KEY` в `backend/.env`). Если потерять `ENCRYPTION_KEY`, ключи придётся ввести заново.

## Тесты

```bash
make test       # бэкенд (нужен make db)
make test-kit   # LevelUpKit
make lint
make ios-build  # собрать приложение для симулятора
make strings    # после сборки: у всех строк интерфейса есть перевод
```

## Сессия и токены

- Access JWT живёт 1 час.
- Refresh-токен живёт 180 дней и при каждом обновлении продлевается. Если приложение открывали хотя бы раз в полгода, сессия не кончается.
- Refresh-токены одноразовые. Повторное использование старого токена отзывает весь вход. Исключение — 60 секунд на повтор запроса, если ответ потерялся в сети.
- Без сети приложение не разлогинивает: показывает профиль из кэша.
