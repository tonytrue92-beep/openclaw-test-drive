# AI TEAM 2.0 — Тест-драйв 🤖

Установщик «тест-драйв» версии AI TEAM 2.0: ставит движок **OpenClaw**
+ одного агента-ассистента в твой Telegram. Доступ **по токену** из бота,
который выдаётся **после оплаты** (Prodamus) — недорогой платный вход
квалифицирует лида перед полной версией.

> Полная версия (6 агентов + супер-агент): **https://serditov.tonytrue.pro/**

---

## Доступ — токен из бота

Доступ выдаётся по **TRY-токену** после оплаты:

1. Открой **[@AITeamVIPBot](https://t.me/AITeamVIPBot)** в Telegram → /start
2. Оплати по ссылке (Prodamus) — бот пришлёт TRY-токен (привязан к твоему Telegram)
3. Запусти команду установки с этим токеном

Токен подписан Ed25519 (тот же механизм, что у платных тарифов) и
проверяется локально — без интернета к боту. В токене зашит твой TG ID,
поэтому отдать его другу нельзя (бот ответит только тебе).

## Установка (одна команда)

macOS / Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --token TRY-XXXX
```

На сервере (VPS, без GUI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --token TRY-XXXX --vps
```

Можно и без `--token` — установщик спросит токен интерактивно. Или
через переменную: `TRIAL_TOKEN=TRY-XXXX bash <(curl …)`.

Переустановить с нуля (сначала удалить):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --uninstall
```

---

## Что делает установщик

Полностью автоматически, по шагам (клиент только вставляет ключи):

1. **Доступ** — проверяет TRY-токен (формат сразу, подпись Ed25519 после
   установки движка). Без валидного токена установка не идёт.
2. **Движок** — ставит Node.js (через nvm) и OpenClaw (`npm install -g openclaw`).
   На macOS сам доустанавливает Xcode Command Line Tools.
3. **Мозги** — подключает бесплатную модель `opencode-go/deepseek-v4-flash`
   (карта не нужна). Открывает opencode.ai в браузере для получения ключа.
4. **Telegram** — подключает бота (токен из @BotFather). TG ID владельца
   берётся **из TRY-токена** — клиента не спрашивают (бот уже знает его).
5. **Финальная сборка** — прогоняет `openclaw onboard` в авто-режиме +
   поднимает gateway (страховочно, проверенными командами).
6. **Быстрый онбординг** — понятный русский чек-лист ✓/✗: движок, модель,
   Telegram, агент, gateway. В конце открывает страницу полной версии.

Агент-ассистент каждые 2-3 сообщения мягко предлагает полную версию
курса (логика в `templates/assistant/AGENTS.md` + `SOUL.md`).

---

## Флаги

| Флаг | Что делает |
|---|---|
| `--token`, `--trial-token <T>` | TRY-токен из @AITeamVIPBot (или env `TRIAL_TOKEN`) |
| `--vps`, `--headless` | Режим VPS/сервера (dashboard через SSH) |
| `--uninstall`, `--reset` | Удалить OpenClaw + агента (для чистой переустановки) |
| `--version` | Показать версию |
| `--help` | Справка |

---

## Связь с другими репозиториями

- **Этот репо (`openclaw-test-drive`)** — тест-драйв (1 агент,
  лидогенерация). По TRY-токену из @AITeamVIPBot — выдаётся после оплаты (Prodamus).
- **`openclaw-agents-pack`** — платный продукт: полная команда агентов
  (Base / Pro / Hermes), требует курс-токен. Это то, что мы продаём.
- **`openclaw-factory`** — установщик самого движка OpenClaw (первая
  ступень).

Тест-драйв намеренно изолирован: не вызывает и не зависит от других
установщиков.

---

## Разработка

```bash
bash scripts/smoke-test.sh        # статические проверки установщика
bash scripts/security-audit.sh    # нет утечек секретов + чистые шаблоны
bash scripts/update-checksums.sh  # пересобрать SHA256SUMS после правок
bash -n scripts/install-trial.sh  # проверка синтаксиса
```

CI (`.github/workflows/ci.yml`) гоняет всё это на каждый push/PR:
ShellCheck, `bash -n`, smoke-test, security-audit, свежесть SHA256SUMS.

Скрипт держим **bash 3.2-совместимым** (macOS по умолчанию идёт со
старым bash) — без `declare -A`, `mapfile`, `${var^^}`.
