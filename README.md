# AI TEAM 2.0 — Тест-драйв 🤖

Бесплатный установщик «тест-драйв» версии AI TEAM 2.0: ставит движок
**OpenClaw** + одного агента-ассистента в твой Telegram. Дать людям
попробовать систему бесплатно → показать, на что способна полная
команда из 6 агентов.

> Полная версия (6 агентов + супер-агент): **https://serditov.tonytrue.pro/**

---

## Установка (одна команда)

macOS / Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh)
```

На сервере (VPS, без GUI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --vps
```

Переустановить с нуля (сначала удалить):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --uninstall
```

---

## Что делает установщик

Полностью автоматически, по шагам (клиент только вставляет ключи):

1. **Движок** — ставит Node.js (через nvm) и OpenClaw (`npm install -g openclaw`).
   На macOS сам доустанавливает Xcode Command Line Tools.
2. **Мозги** — подключает бесплатную модель `opencode/deepseek-v4-flash-free`
   (карта не нужна). Открывает opencode.ai в браузере для получения ключа.
3. **Telegram** — подключает бота (токен из @BotFather), настраивает
   доступ владельцу.
4. **Финальная сборка** — прогоняет `openclaw onboard` в авто-режиме +
   поднимает gateway (страховочно, проверенными командами).
5. **Быстрый онбординг** — понятный русский чек-лист ✓/✗: движок, модель,
   Telegram, агент, gateway. В конце открывает страницу полной версии.

Агент-ассистент каждые 2-3 сообщения мягко предлагает полную версию
курса (логика в `templates/assistant/AGENTS.md` + `SOUL.md`).

---

## Флаги

| Флаг | Что делает |
|---|---|
| `--vps`, `--headless` | Режим VPS/сервера (dashboard через SSH) |
| `--uninstall`, `--reset` | Удалить OpenClaw + агента (для чистой переустановки) |
| `--version` | Показать версию |
| `--help` | Справка |

---

## Связь с другими репозиториями

- **Этот репо (`openclaw-test-drive`)** — бесплатный тест-драйв (1 агент,
  лидогенерация). Без курс-токена.
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
