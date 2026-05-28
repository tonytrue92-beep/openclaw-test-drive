# Changelog

История изменений тест-драйв установщика AI TEAM 2.0.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

---

## 2026-05-28 — v2026.05.28.13 (выделение в отдельный репозиторий)

Тест-драйв установщик выделен из `openclaw-agents-pack` в собственный
репозиторий `openclaw-test-drive`. Код переехал как есть; `REPO_RAW`
теперь указывает на этот репо (шаблоны качаются отсюда).

### Возможности на момент выделения

- **Движок:** OpenClaw через `npm install -g openclaw@latest` + Node.js
  через nvm (кроссплатформенно). На macOS — авто-установка Xcode
  Command Line Tools с ожиданием в цикле.
- **nvm-персист:** прописывается в shell rc + `nvm alias default 22`,
  чтобы `openclaw` был доступен в новых терминалах.
- **Модель:** фиксированная бесплатная `opencode/deepseek-v4-flash-free`
  (без меню выбора). auth-profile пишется напрямую агенту.
- **Telegram:** `channels add` + `dmPolicy allowlist` + `allowFrom` +
  `bind telegram`.
- **Gateway:** `gateway.mode local` → `install` → `launchctl bootstrap`
  → `start`, проверка по надёжному маркеру `LaunchAgent (loaded)`.
- **onboard:** прогон `openclaw onboard --non-interactive` (best-effort,
  `</dev/null` против зависания) поверх проверенной ручной настройки.
- **Русский онбординг:** видимый чек-лист ✓/✗ по 5 узлам системы.
- **Финал:** авто-открытие страницы полной версии в браузере.
- **Флаги:** `--vps`, `--uninstall`/`--reset`, `--version`, `--help`.

### Инфраструктура

- `scripts/smoke-test.sh` — статические grep-проверки установщика.
- `scripts/security-audit.sh` — нет утечек секретов + чистые шаблоны.
- `scripts/update-checksums.sh` + `SHA256SUMS`.
- CI: ShellCheck, `bash -n`, smoke, security-audit, SHA256SUMS freshness.

> Предыдущая история (waves 30-44) — в `openclaw-agents-pack/CHANGELOG.md`.
