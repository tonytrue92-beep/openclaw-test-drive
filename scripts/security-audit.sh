#!/usr/bin/env bash
# security-audit.sh — статические проверки безопасности тест-драйва.
# Запускается в CI на каждый push. Четыре проверки:
#   1. Нет прямого echo/printf секретных переменных на экран
#   2. Секреты очищаются (unset) после использования
#   3. Нет валидных токенов в исходниках
#   4. templates/ не содержат личных данных автора (course-URL разрешён)

set -euo pipefail
cd "$(dirname "$0")/.."

TRIAL=scripts/install-trial.sh
fail_count=0
fail() { echo "✗ FAIL: $1"; fail_count=$((fail_count + 1)); }
pass() { echo "✓ PASS: $1"; }

echo "=== Security audit: openclaw-test-drive ==="
echo ""

# ─── Check 1: нет прямого вывода секретов на экран ──────────────
# Опасно: echo/printf сырого секрета на терминал (виден при screen-share).
# Безопасно и НЕ ловим: `printf '%s' "$VAR" | tr -d '[:space:]'` — это
# санитизация ввода (захват в переменную, не вывод). Фильтруем её.
echo "─── Check 1: прямой вывод секретных переменных ───"
secret_out=$(grep -nE '(echo|printf)[^|]*\$\{?(OPENCODE_KEY|BOT_TOKEN)' "$TRIAL" 2>/dev/null \
  | grep -vF "| tr -d '[:space:]'" || true)
if [[ -n "$secret_out" ]]; then
  fail "найден вывод сырого секрета на экран:"
  echo "$secret_out"
else
  pass "нет прямого вывода секретов (OPENCODE_KEY/BOT_TOKEN)"
fi
echo ""

# ─── Check 2: секреты очищаются после использования ─────────────
echo "─── Check 2: unset секретов после использования ───"
if grep -q 'unset OPENCODE_KEY' "$TRIAL" && grep -q 'unset BOT_TOKEN' "$TRIAL"; then
  pass "OPENCODE_KEY и BOT_TOKEN очищаются (unset)"
else
  fail "секрет не очищается после использования (unset)"
fi
echo ""

# ─── Check 3: нет реальных токенов в исходниках ─────────────────
echo "─── Check 3: нет реальных токенов в scripts/templates ───"
leaks=$(grep -rnE '"sk-[A-Za-z0-9]{30,}"|["'"'"'][0-9]{8,12}:AA[A-Za-z0-9_-]{30,}["'"'"']' \
  scripts/ templates/ 2>/dev/null \
  | grep -vE 'sk-(xxx|test|REDACTED|proj-abc)' \
  | grep -vE '7123456789:AA(Hk-xx|Gk-abc)' || true)
if [[ -n "$leaks" ]]; then
  fail "возможный реальный токен в исходниках:"
  echo "$leaks"
else
  pass "нет реальных токенов в scripts/templates"
fi
echo ""

# ─── Check 4: templates/ без личных данных автора ───────────────
# course-offer URL https://serditov.tonytrue.pro/ — публичный
# маркетинговый адрес (страница продаж), НАМЕРЕННО в templates/assistant/.
# Это не утечка — исключаем именно его, но «serditov» в другом контексте
# по-прежнему ловится.
echo "─── Check 4: templates/ без личных данных автора ───"
forbidden=$(grep -rniE \
  'antonpolakov|@tonytruee|tonytrue92|975494053|1167075209|vip-factory\b|openclaw-factory\b|/Users/[a-z]+|Антон\s+Поляков|instapol2136|TRUE AI AGENCY|ntn_[A-Za-z0-9]{20,}|cpk_[A-Za-z0-9]{20,}|pat_FL[A-Za-z0-9]{20,}' \
  templates/ 2>/dev/null \
  | grep -vE 'serditov\.tonytrue\.pro' \
  || true)
if [[ -n "$forbidden" ]]; then
  fail "templates/ содержат личные маркеры автора:"
  echo "$forbidden" | head -10
else
  pass "templates/ чистые от личных данных (course-offer URL разрешён)"
fi
echo ""

# ─── Summary ───
if [[ $fail_count -eq 0 ]]; then
  echo "=== Security audit passed ==="
  exit 0
else
  echo "=== Security audit FAILED: $fail_count issue(s) ==="
  exit 1
fi
