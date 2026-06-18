#!/usr/bin/env bash
# smoke-test.sh — статические проверки тест-драйв установщика.
# Запускается в CI и локально: bash scripts/smoke-test.sh
#
# НЕ выполняет install-trial.sh (он ставит реальный софт) — только
# проверяет grep-асертами, что ключевые шаги и строки на месте.

set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ FAIL: $1"; exit 1; }
pass() { echo "✓ PASS: $1"; }

TRIAL=scripts/install-trial.sh

echo "=== Smoke-test openclaw-test-drive ==="
echo ""

# ─── Структура ──────────────────────────────────────────────────
[[ -f "$TRIAL" ]] || fail "нет scripts/install-trial.sh"
for f in IDENTITY AGENTS SOUL USER MEMORY; do
  [[ -f "templates/assistant/${f}.md" ]] || fail "нет templates/assistant/${f}.md"
done
pass "структура: install-trial.sh + templates/assistant/*.md на месте"

# ─── bash 3.2-совместимость (macOS) — без declare -A/mapfile/${^^} ─
if grep -nE 'declare -A|mapfile|\$\{[A-Za-z_]+\^\^\}' "$TRIAL"; then
  fail "bash 4+ конструкции (на macOS bash 3.2 упадёт)"
fi
pass "bash 3.2-совместимость (нет declare -A / mapfile / \${^^})"

# ─── REPO_RAW указывает на ЭТОТ репо (иначе шаблоны не скачаются) ─
grep -q 'openclaw-test-drive/main' "$TRIAL" \
  || fail "REPO_RAW не указывает на openclaw-test-drive (шаблоны не скачаются)"
grep -q 'openclaw-agents-pack' "$TRIAL" \
  && fail "остался указатель на openclaw-agents-pack (репо разделены)" \
  || true
pass "REPO_RAW указывает на openclaw-test-drive"

# ─── Движок: OpenClaw через npm (ЗАПИНЕННАЯ версия, не @latest) + Node nvm ─
grep -q '^OPENCLAW_VERSION=' "$TRIAL" \
  || fail "trial: нет пина OPENCLAW_VERSION — вернулись на плавающую версию"
if grep -q 'npm install -g openclaw@latest' "$TRIAL"; then
  fail "trial: остался openclaw@latest — апстрим снова будет ломать тест-клиентов"
fi
grep -q 'npm install -g openclaw@${OPENCLAW_VERSION}' "$TRIAL" \
  || fail "trial: установка движка не через пин OPENCLAW_VERSION"
grep -q 'nvm install 22' "$TRIAL" \
  || fail "trial не ставит Node.js через nvm"
grep -q 'brew install --cask openclaw' "$TRIAL" \
  && fail "brew-cask путь должен быть убран (macOS-only, требует Sequoia)" \
  || true
pass "движок: OpenClaw через npm + Node через nvm"

# Движок всегда приводится к ЗАПИНЕННОЙ версии (а не только при отсутствии)
grep -q 'Ставлю OpenClaw ${OPENCLAW_VERSION}' "$TRIAL" \
  || fail "trial не ставит запиненную версию движка (должно ставить/выравнивать всегда)"
pass "движок: всегда подтягивается последняя версия OpenClaw (ставит/обновляет)"

# ─── Xcode CLT auto-install (на чистом маке нет git/компиляторов) ──
grep -q 'xcode-select --install' "$TRIAL" \
  || fail "trial не запускает auto-install Xcode CLT"
grep -q 'xcode-select -p' "$TRIAL" \
  || fail "trial не проверяет наличие Xcode CLT"
pass "Xcode CLT auto-install + wait-loop (без ошибки у клиента)"

# ─── nvm прописан в shell rc (иначе openclaw не в PATH новых терминалов) ─
grep -q 'persist_nvm_in_shell_rc' "$TRIAL" \
  || fail "trial не прописывает nvm в shell rc (openclaw будет недоступен)"
grep -q 'nvm alias default' "$TRIAL" \
  || fail "нет nvm alias default (openclaw не в PATH новых терминалов)"
pass "nvm персистится в shell rc + alias default"

# ─── Модель: opencode-ключ + auth-profile + фикс. DeepSeek, без меню ─
grep -q 'opencode.ai' "$TRIAL" \
  || fail "trial не запрашивает opencode-ключ для модели"
grep -q 'auth-profiles.json' "$TRIAL" \
  || fail "trial не пишет auth-profiles.json (агент будет молчать)"
grep -q 'agents.defaults.model.primary' "$TRIAL" \
  || fail "trial не устанавливает модель по умолчанию"
grep -q 'opencode-go/deepseek-v4-flash' "$TRIAL" \
  || fail "trial не ставит deepseek-v4-flash-free по умолчанию"
grep -q 'Выбери модель' "$TRIAL" \
  && fail "меню выбора модели должно быть убрано" \
  || true
grep -qiE 'minimax|gpt-5|claude-sonnet' "$TRIAL" \
  && fail "остались старые модели (minimax/gpt-5/claude-sonnet)" \
  || true
pass "модель: opencode-ключ + auth-profile + фиксированный DeepSeek (без меню)"

# ─── --uninstall: чистое удаление для переустановки ─────────────
grep -q '\-\-uninstall|--reset)' "$TRIAL" \
  || fail "флаг --uninstall не обработан"
grep -q 'npm uninstall -g openclaw' "$TRIAL" \
  || fail "--uninstall не удаляет npm-пакет openclaw"
grep -q 'rm -rf "\$HOME/.openclaw"' "$TRIAL" \
  || fail "--uninstall не удаляет ~/.openclaw"
pass "--uninstall (чистое удаление для переустановки)"

# ─── Telegram: channels add + dmPolicy/allowFrom + bind ─────────
grep -q 'openclaw channels add --channel telegram' "$TRIAL" \
  || fail "telegram-токен не через channels add (бот будет молчать)"
grep -q 'channels.telegram.dmPolicy allowlist' "$TRIAL" \
  || fail "нет dmPolicy allowlist (бот попросит pairing)"
grep -q 'channels.telegram.allowFrom' "$TRIAL" \
  || fail "нет allowFrom (владелец не в allowlist)"
grep -q -- '--bind telegram' "$TRIAL" \
  || fail "agents add без --bind telegram"
pass "telegram: channels add + dmPolicy/allowFrom + bind telegram"

# ─── Gateway: install безусловно + launchctl bootstrap + маркер ──
grep -q 'config set gateway.mode local' "$TRIAL" \
  || fail "trial не ставит gateway.mode local (gateway упадёт)"
grep -q 'openclaw gateway install' "$TRIAL" \
  || fail "trial не делает gateway install (сервис не создаётся)"
grep -q 'launchctl bootstrap' "$TRIAL" \
  || fail "trial не делает launchctl bootstrap (LaunchAgent не грузится)"
grep -q 'LaunchAgent \\(loaded\\)' "$TRIAL" \
  || fail "проверка gateway не на надёжный маркер (LaunchAgent loaded)"
pass "gateway: install + launchctl bootstrap + надёжный маркер"

# ─── onboard non-interactive + видимый русский онбординг ─────────
grep -q 'openclaw onboard' "$TRIAL" \
  || fail "trial не прогоняет openclaw onboard"
grep -q 'opencode-zen-api-key' "$TRIAL" \
  || fail "onboard без --opencode-zen-api-key (модель не настроится)"
grep -q 'non-interactive' "$TRIAL" \
  || fail "onboard не в non-interactive (повиснет на промпте)"
grep -q 'Быстрый онбординг' "$TRIAL" \
  || fail "нет видимого русского онбординг-чеклиста"
pass "onboard non-interactive + русский онбординг-чеклист"

# ─── Финал: авто-открытие сайта-продажника в браузере ───────────
grep -qF 'open "$COURSE_URL"' "$TRIAL" \
  || fail "финал не открывает сайт-продажник через open (macOS)"
grep -qF 'xdg-open "$COURSE_URL"' "$TRIAL" \
  || fail "финал не открывает сайт-продажник через xdg-open (Linux)"
pass "финал авто-открывает сайт полной версии в браузере"

# ─── TRY-токен: гейт доступа (тот же механизм, что платный) ─────
# Бесплатно, но по токену из @AITeamVIPBot. Ed25519, встроенный
# публичный ключ, двухфазный гейт (формат до установки, подпись после).
grep -q 'TRIAL_PUBLIC_KEY_PEM' "$TRIAL" \
  || fail "нет встроенного публичного ключа для проверки токена"
grep -q 'BEGIN PUBLIC KEY' "$TRIAL" \
  || fail "нет PEM публичного ключа"
grep -qF 'TRY-[A-F0-9]{16}' "$TRIAL" \
  || fail "нет формат-проверки TRY-токена"
grep -q 'crypto.verify' "$TRIAL" \
  || fail "нет Ed25519 крипто-проверки подписи (node)"
grep -qF 'TRY|' "$TRIAL" \
  || fail "payload подписи должен быть TRY|<hash>|<tg>"
grep -q -- '--token|--trial-token' "$TRIAL" \
  || fail "нет флага --token/--trial-token"
grep -q 'TRIAL_TG_ID' "$TRIAL" \
  || fail "TG ID не извлекается из токена (для allowFrom)"
grep -qF 'Без токена установка невозможна' "$TRIAL" \
  || fail "нет жёсткого гейта (выход без валидного токена)"
pass "TRY-токен: гейт + Ed25519 + TG из токена + --token флаг"

# Безопасность: приватного ключа в репо быть НЕ должно (только у бота)
if grep -rqE 'BEGIN (OPENSSH |EC |RSA |DSA |)PRIVATE KEY' scripts/ templates/ 2>/dev/null; then
  fail "в репо есть приватный ключ — он должен быть ТОЛЬКО у бота!"
fi
pass "приватного ключа в репо нет (только публичный)"

# Windows Companion GUI offer в финале (всем Windows-клиентам)
grep -q 'docs.openclaw.ai/platforms/windows' "$TRIAL" \
  || fail "Windows Companion: нет ссылки на страницу загрузки"
grep -q 'OpenClaw Windows Hub' "$TRIAL" \
  || fail "Windows Companion: нет текста предложения"
pass "Windows Companion GUI offer на месте (trial)"

echo ""
echo "=== All smoke tests passed ==="

# ─── IP-gated доставка (2026-06-14) ───
grep -q 'ip_dl_trial()' scripts/install-trial.sh || { echo "FAIL: ip_dl_trial нет"; exit 1; }
grep -q 'IP_BASE="${IP_BASE:-}"' scripts/install-trial.sh || { echo "FAIL: IP_BASE дефолт не пуст"; exit 1; }
grep -qF 'curl -fsSL --connect-timeout 10 --max-time 25 "$2" -o "$3"' scripts/install-trial.sh || { echo "FAIL: github-ветка не чистая"; exit 1; }
grep -q 'for _try in 1 2 3' scripts/install-trial.sh || { echo "FAIL: ip_dl_trial без ретраев"; exit 1; }
echo "OK: trial ip_dl_trial шов + ретраи (gateway+Bearer / github без заголовка)"

# ─── Все токены/ключи вводятся ВИДИМО (решение Антона, как в factory/agents) ───
if grep -qE 'read -rs |read -r -s ' scripts/install-trial.sh; then
  fail "trial: остался скрытый ввод (-s) токена/ключа — все должны быть видимыми"
fi
grep -q 'символы видны при вводе' scripts/install-trial.sh \
  || fail "trial: подпись ввода токена не обновлена на «символы видны»"
echo "OK: токены/ключи (opencode key, bot token) вводятся видимо — нет read -s"

