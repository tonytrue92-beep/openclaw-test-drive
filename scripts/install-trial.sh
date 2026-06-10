#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
#  AI TEAM 2.0 — TRIAL / ДЕМО установщик
#
#  ⚠️  ЭТО ОТДЕЛЬНЫЙ УСТАНОВЩИК. Не связан с install-agents.sh.
#      Ставит OpenClaw движок + ОДНОГО агента-ассистента (демо).
#      ПО ТОКЕНУ (после оплаты): TRY-токен выдаёт @AITeamVIPBot после
#      успешной оплаты (Prodamus). Тот же Ed25519-механизм, что в платном.
#
#  Агент-ассистент каждые 2-3 сообщения мягко предлагает полную версию
#  курса со ссылкой https://serditov.tonytrue.pro/ (логика в шаблоне
#  templates/assistant/AGENTS.md + SOUL.md).
#
#  Цель: недорогой платный вход (квалифицирует лида) → конвертировать
#  в полную версию (6 агентов + Hermes).
#
#  Работает на macOS / Linux / VPS / Windows (WSL/Git Bash).
# ═══════════════════════════════════════════════════════════════════════

# ─── Bash: работаем на 3.2+ (wave 31) ───────────────────────────
# Код 3.2-совместим. Если свежий bash уже есть в brew — используем его
# (стабильнее), но НЕ требуем и НЕ ставим его сами: на старых маках
# сборка bash из исходников — это минуты ожидания и барьер на входе.
if (( BASH_VERSINFO[0] < 4 )); then
  for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
      exec "$_newer_bash" "$0" "$@"
    fi
  done
  # bash 4+ не найден — продолжаем на текущем 3.2 (код совместим).
fi

TRIAL_VERSION="2026.06.09"
TRIAL_COMMIT="__COMMIT_PLACEHOLDER__"
COURSE_URL="https://serditov.tonytrue.pro/"
REPO_RAW="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main"

# ─── Цвета ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  CYAN=$'\033[36m'; WHITE=$'\033[37m'; MAGENTA=$'\033[35m'
else
  BOLD=''; DIM=''; NC=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; WHITE=''; MAGENTA=''
fi

ok()   { echo -e "   ${GREEN}✓${NC} $*"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $*" >&2; }
err()  { echo -e "   ${RED}✗${NC} $*" >&2; }
divider() { echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# Wave 38: прописать nvm в shell rc-файлы (как factory). БЕЗ ЭТОГО
# команда openclaw недоступна в новых терминалах — nvm не загружается,
# node/openclaw не попадают в PATH. Это была главная причина «openclaw
# не вызывается после установки».
persist_nvm_in_shell_rc() {
  local nvm_block='
# NVM (AI TEAM 2.0 trial installer)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [[ ! -f "$rc" ]] && touch "$rc"
    if ! grep -q "AI TEAM 2.0 trial installer" "$rc" 2>/dev/null; then
      echo "$nvm_block" >> "$rc"
      echo -e "   ${DIM}↳ прописал nvm в ${rc}${NC}"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════
#  TRY-токен доступа (тот же механизм, что в платном install-agents.sh)
# ═══════════════════════════════════════════════════════════════
#
# Формат:  TRY-<hash16>-<tg_id>-<подпись_b64url>
# Подпись: Ed25519 над "TRY|<hash16>|<tg_id>" приватным ключом @AITeamVIPBot.
# Проверяется встроенным ПУБЛИЧНЫМ ключом (тот же, что у платных тарифов) —
# приватный есть только у бота. Сеть для проверки не нужна.
#
# Двухфазно (т.к. node ставится только на Шаге 1):
#   • Фаза A (до установки) — формат + извлечение TG_ID. Мгновенно,
#     блокирует пустой/мусорный токен ДО любой установки.
#   • Фаза B (после установки node) — крипто-проверка подписи через node.
TRIAL_TOKEN_CACHE="$HOME/.openclaw/trial-token"
TRIAL_PUBLIC_KEY_PEM=$(cat <<'PEMEOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
PEMEOF
)
TRIAL_TOKEN_PRESET="${TRIAL_TOKEN:-}"   # из env TRIAL_TOKEN или флага --token
TRIAL_TOKEN=""        # валидный токен (заполняется гейтом)
TRIAL_TG_ID=""        # TG ID, зашитый в токен (для allowlist)

# Санитизация (пробелы / юникод-тире / кавычки) — как wave 17 в agents-pack.
_trial_sanitize_token() {
  local t="$1"
  t=$(printf '%s' "$t" | tr -d '[:space:]')
  t="${t//—/-}"; t="${t//–/-}"; t="${t//‐/-}"; t="${t//‑/-}"
  t="${t//\"/}"; t="${t//\'/}"
  printf '%s' "$t"
}

# Формат-проверка (без крипто). Set TRIAL_TG_ID. 0 = форма верна.
_trial_token_format_ok() {
  local t="$1"
  if [[ "$t" =~ ^TRY-[A-F0-9]{16}-([0-9]{5,15})-[A-Za-z0-9_-]{80,100}$ ]]; then
    TRIAL_TG_ID="${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Крипто-проверка Ed25519 (нужен node — гарантирован после Шага 1).
# 0 = подпись валидна, иначе != 0.
_trial_token_verify_sig() {
  local t="$1"
  local hash_part tg_part sig_part
  hash_part=$(printf '%s' "$t" | cut -d'-' -f2)
  tg_part=$(printf '%s' "$t" | cut -d'-' -f3)
  sig_part=$(printf '%s' "$t" | cut -d'-' -f4-)
  command -v node >/dev/null 2>&1 || return 2
  TRIAL_PUB="$TRIAL_PUBLIC_KEY_PEM" \
  TRIAL_PAYLOAD="TRY|${hash_part}|${tg_part}" \
  TRIAL_SIG="$sig_part" node - >/dev/null 2>&1 <<'JS'
const crypto = require('crypto');
try {
  const pk = crypto.createPublicKey(process.env.TRIAL_PUB);
  const payload = Buffer.from(process.env.TRIAL_PAYLOAD || '', 'utf8');
  const sig = Buffer.from(process.env.TRIAL_SIG || '', 'base64url');
  process.exit(crypto.verify(null, payload, pk, sig) ? 0 : 1);
} catch { process.exit(1); }
JS
}

# Фаза A: получить токен (флаг/env → кэш → prompt) + формат-проверка.
# 0 = форма ок (TRIAL_TOKEN + TRIAL_TG_ID заполнены).
_trial_token_gate_format() {
  local raw=""
  if [[ -n "$TRIAL_TOKEN_PRESET" ]]; then
    raw="$TRIAL_TOKEN_PRESET"
  elif [[ -f "$TRIAL_TOKEN_CACHE" ]]; then
    raw=$(cat "$TRIAL_TOKEN_CACHE" 2>/dev/null || true)
  fi
  raw=$(_trial_sanitize_token "$raw")
  if [[ -n "$raw" ]] && _trial_token_format_ok "$raw"; then
    TRIAL_TOKEN="$raw"; return 0
  fi
  local attempts=0 t
  while [[ $attempts -lt 3 ]]; do
    attempts=$((attempts + 1))
    echo -e "   ${BOLD}${WHITE}Вставь токен доступа (попытка ${attempts}/3):${NC}"
    read -r t || t=""   # не-tty/EOF (curl|bash без --token) → не падаем под set -e
    t=$(_trial_sanitize_token "$t")
    if [[ -z "$t" ]]; then warn "Пустой ввод."; continue; fi
    if _trial_token_format_ok "$t"; then TRIAL_TOKEN="$t"; return 0; fi
    warn "Формат токена не похож на TRY-… Проверь, что скопировал целиком."
  done
  return 1
}

# Сохранить токен в кэш (chmod 600) — на повторных запусках не спрашиваем.
_trial_token_save_cache() {
  mkdir -p "$(dirname "$TRIAL_TOKEN_CACHE")" 2>/dev/null || true
  ( umask 077; printf '%s\n' "$TRIAL_TOKEN" > "$TRIAL_TOKEN_CACHE" )
  chmod 600 "$TRIAL_TOKEN_CACHE" 2>/dev/null || true
}

# ─── Парсинг флагов ─────────────────────────────────────────────
VPS_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vps|--headless) VPS_MODE=true; shift ;;
    --token|--trial-token)
      TRIAL_TOKEN_PRESET="${2:-}"
      shift 2 2>/dev/null || shift
      ;;
    --uninstall|--reset)
      # Wave 36: чистое удаление того что поставил trial — для повторной
      # установки с нуля. Node.js/Xcode CLT НЕ трогаем (не мешают, ускоряют
      # переустановку). Удаляем: gateway + assistant-агента + npm openclaw
      # + ~/.openclaw.
      echo ""
      echo "Это удалит OpenClaw движок, агента-ассистента и папку ~/.openclaw"
      echo "(данные и настройки). Node.js и Xcode CLT останутся."
      echo ""
      printf "Продолжить удаление? [y/N]: "
      read -r _confirm || _confirm="n"   # не-tty/EOF → считаем «нет» (без set -e краша)
      if [[ "${_confirm:-n}" != "y" && "${_confirm:-n}" != "Y" ]]; then
        echo "Отменено."
        exit 0
      fi
      echo ""
      echo "Останавливаю gateway..."
      openclaw gateway stop &>/dev/null || true
      launchctl unload "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" &>/dev/null || true
      echo "Удаляю агента-ассистента..."
      openclaw agents delete assistant --yes &>/dev/null || true
      echo "Удаляю движок OpenClaw (npm)..."
      npm uninstall -g openclaw &>/dev/null || true
      echo "Удаляю данные ~/.openclaw..."
      rm -rf "$HOME/.openclaw" 2>/dev/null || true
      echo ""
      echo "✓ Готово. OpenClaw удалён. Запусти установку снова чтобы начать с чистого листа."
      exit 0
      ;;
    --version)
      echo "AI TEAM 2.0 Trial v${TRIAL_VERSION} (${TRIAL_COMMIT})"
      exit 0
      ;;
    --help)
      cat <<HELP
AI TEAM 2.0 — ТЕСТ-ДРАЙВ установщик v${TRIAL_VERSION}

Тест-драйв: OpenClaw + один агент-ассистент.
Нужен TRY-токен (выдаётся после оплаты, @AITeamVIPBot). Полная версия — ${COURSE_URL}

Usage:
  bash <(curl -fsSL .../install-trial.sh) --token TRY-XXXX [флаги]

Options:
  --token, --trial-token <T>  TRY-токен из @AITeamVIPBot (или env TRIAL_TOKEN)
  --vps, --headless           Режим VPS/сервера (без GUI, dashboard через SSH)
  --uninstall                 Удалить OpenClaw + агента (для чистой переустановки)
  --version                   Показать версию
  --help                      Эта справка
HELP
      exit 0
      ;;
    *) shift ;;
  esac
done

# ─── detect ОС ──────────────────────────────────────────────────
detect_os() {
  case "${OSTYPE:-}" in
    cygwin|msys|mingw*) printf 'windows-bash'; return ;;
    darwin*)            printf 'macos'; return ;;
  esac
  if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
    uname -r 2>/dev/null | grep -qiE 'microsoft|wsl' && printf 'wsl' || printf 'linux'
    return
  fi
  printf 'unknown'
}
OS_NAME=$(detect_os)

# ─── Banner ─────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${MAGENTA}"
cat << 'LOGO'
    _    ___   _____ _____    _    __  __   ____    ___
   / \  |_ _| |_   _| ____|  / \  |  \/  | |___ \  / _ \
  / _ \  | |    | | |  _|   / _ \ | |\/| |   __) || | | |
 / ___ \ | |    | | | |___ / ___ \| |  | |  / __/ | |_| |
/_/   \_\___|   |_| |_____/_/   \_\_|  |_| |_____(_)___/
LOGO
echo -e "${NC}"
echo -e "${BOLD}${YELLOW}                  Т Е С Т - Д Р А Й В   В Е Р С И Я${NC}"
echo ""
echo -e "${BOLD}${WHITE}   Попробуй личного AI-ассистента в деле.${NC}"
echo -e "${DIM}   Это тест-драйв одного агента. Полная версия — команда из 6 агентов${NC}"
echo -e "${DIM}   которые работают на тебя 24/7: ${CYAN}${COURSE_URL}${NC}"
echo ""
echo -e "${DIM}   trial v${TRIAL_VERSION}${NC}"
if [[ "$VPS_MODE" == true ]]; then
  echo -e "${BOLD}${MAGENTA}   🌐 VPS-режим${NC}"
else
  case "$OS_NAME" in
    macos)        _os_label="macOS" ;;
    linux)        _os_label="Linux" ;;
    wsl)          _os_label="Windows (WSL)" ;;
    windows-bash) _os_label="Windows (Git Bash)" ;;
    *)            _os_label="неизвестная ОС" ;;
  esac
  echo -e "${DIM}   🖥  Система: ${BOLD}${_os_label}${NC}${DIM} (на VPS — запусти с --vps)${NC}"
fi
echo ""
divider
echo ""

# ═══════════════════════════════════════════════════════════════
#  Доступ — TRY-токен из @AITeamVIPBot (обязателен)
# ═══════════════════════════════════════════════════════════════
# Фаза A: формат-проверка ДО любой установки. Полную крипто-проверку
# подписи делаем после Шага 1 (там появляется node).
echo -e "${BOLD}${WHITE}🔑 Доступ — нужен токен из @AITeamVIPBot${NC}"
echo ""
echo -e "${DIM}   Доступ по токену (выдаётся после оплаты):${NC}"
echo -e "   ${CYAN}1.${NC} Открой ${BOLD}@AITeamVIPBot${NC} в Telegram → /start"
echo -e "   ${CYAN}2.${NC} Оплати по ссылке — бот пришлёт TRY-токен"
echo -e "   ${CYAN}3.${NC} Вставь токен сюда"
echo ""
if ! _trial_token_gate_format; then
  echo ""
  err "Без токена установка невозможна. Оплати и получи TRY-токен в @AITeamVIPBot."
  echo -e "${BOLD}${CYAN}      https://t.me/AITeamVIPBot${NC}"
  exit 1
fi
ok "Токен принят. Подпись проверю после установки движка."
echo ""
divider
echo ""

# ═══════════════════════════════════════════════════════════════
#  T1. Preflight — Node.js + OpenClaw движок (через npm)
# ═══════════════════════════════════════════════════════════════
#
# Wave 34: ставим OpenClaw через `npm install -g openclaw@latest` —
# тот же путь что в factory demo-install.sh. Кроссплатформенно
# (macOS любой версии / Linux / VPS / Windows с Node), БЕЗ требования
# macOS 15 (Sequoia) — это ограничение было у brew-cask, не у npm.
echo -e "${BOLD}${WHITE}Шаг 1/4 — Проверяю Node.js и ставлю OpenClaw...${NC}"
echo ""

# Wave 35: Xcode Command Line Tools (git/компиляторы). На чистом маке
# их нет, а nvm install использует git → ошибка «need Xcode CLT».
# Ставим САМИ и ждём пока готово — пользователь не видит криптовую ошибку.
if [[ "$OS_NAME" == "macos" ]] && ! xcode-select -p &>/dev/null; then
  echo -e "   ${DIM}Нужны Apple Command Line Tools (для Node.js). Запускаю установку...${NC}"
  xcode-select --install &>/dev/null || true
  echo ""
  echo -e "   ${BOLD}${WHITE}📦 Открылось окно Apple «Установить инструменты разработчика».${NC}"
  echo -e "   ${BOLD}${WHITE}   Нажми «Установить» в этом окне и дождись завершения.${NC}"
  echo -e "   ${DIM}   Жду автоматически (обычно 3-7 минут)...${NC}"
  echo ""
  _waited=0
  while ! xcode-select -p &>/dev/null; do
    sleep 5
    _waited=$((_waited + 5))
    if (( _waited % 30 == 0 )); then
      echo -e "   ${DIM}   ...всё ещё жду установку Command Line Tools (${_waited}с)${NC}"
    fi
    if (( _waited >= 900 )); then
      echo ""
      err "Command Line Tools не установились за 15 минут."
      echo -e "   ${DIM}Заверши установку в окне Apple (или: xcode-select --install)${NC}"
      echo -e "   ${DIM}и запусти команду снова.${NC}"
      exit 1
    fi
  done
  ok "Apple Command Line Tools готовы"
fi

# ─── Node.js (нужен для npm install openclaw) ───────────────────
if ! command -v node &>/dev/null; then
  if [[ "$OS_NAME" == "windows-bash" ]]; then
    err "Нужен Node.js. На Windows поставь с https://nodejs.org (LTS), затем запусти снова."
    echo -e "${BOLD}${YELLOW}   Полная версия (6 агентов): ${CYAN}${COURSE_URL}${NC}"
    exit 1
  fi
  echo -e "   ${DIM}Node.js не найден — ставлю через nvm (1-2 минуты)...${NC}"
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>/dev/null | bash 2>&1 | tail -3 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  fi
  [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
  if command -v nvm &>/dev/null; then
    nvm install 22 2>&1 | tail -3 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
    nvm use 22 &>/dev/null || true
    # Wave 39: КРИТИЧНО — alias default, иначе в новом терминале nvm
    # не активирует node автоматически → openclaw «command not found».
    nvm alias default 22 &>/dev/null || true
    # Wave 38: прописать nvm в shell rc (без этого nvm не грузится в
    # новых терминалах вообще).
    persist_nvm_in_shell_rc
  fi
fi
if command -v node &>/dev/null; then
  ok "Node.js $(node -v 2>/dev/null) готов"
else
  err "Не удалось подготовить Node.js. Поставь вручную с https://nodejs.org и запусти снова."
  exit 1
fi

# ─── OpenClaw движок через npm (как factory) ────────────────────
# Всегда ставим/обновляем до АБСОЛЮТНО последней версии (Антон: тянуть
# самый свежий движок). npm install -g openclaw@latest идемпотентен —
# поставит, а если уже стоит — обновит. Если обновление не прошло, но
# движок уже есть — продолжаем с текущим (не падаем).
echo -e "   ${DIM}Ставлю/обновляю OpenClaw до последней версии (npm install -g openclaw@latest)...${NC}"
# Стабильность при плохой сети (как factory)
npm config set fetch-retries 5 >/dev/null 2>&1 || true
npm config set fetch-retry-maxtimeout 120000 >/dev/null 2>&1 || true
npm config set fetch-timeout 300000 >/dev/null 2>&1 || true

_npm_err=$(mktemp -t openclaw-npm-err.XXXXXX 2>/dev/null || echo "/tmp/openclaw-npm-err.$$")
# `|| true` — иначе под set -o pipefail падение npm убьёт скрипт ДО дружелюбного
# обработчика ниже (проверка `command -v openclaw` + понятная подсказка).
{ npm install -g openclaw@latest 2>"$_npm_err" || true; } | tail -8 | while IFS= read -r line; do
  echo -e "   ${DIM}${line}${NC}"
done

if ! command -v openclaw &>/dev/null; then
  echo ""
  if grep -qiE 'EACCES|permission denied' "$_npm_err" 2>/dev/null; then
    err "npm: нет прав на глобальную установку. Попробуй: sudo npm install -g openclaw@latest"
    echo -e "   ${DIM}Или настрой npm prefix без sudo: https://docs.npmjs.com/resolving-eacces-permissions-errors${NC}"
  else
    err "Не удалось поставить OpenClaw через npm. Последние строки ошибки:"
    tail -5 "$_npm_err" 2>/dev/null | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done
  fi
  rm -f "$_npm_err"
  echo -e "${BOLD}${YELLOW}   Полная версия (6 агентов): ${CYAN}${COURSE_URL}${NC}"
  exit 1
fi
rm -f "$_npm_err"
ok "OpenClaw установлен/обновлён: $(openclaw --version 2>/dev/null | head -1 || echo 'готов')"
echo ""

# ═══════════════════════════════════════════════════════════════
#  Доступ (фаза B) — крипто-проверка подписи токена (теперь есть node)
# ═══════════════════════════════════════════════════════════════
echo -e "${DIM}   Проверяю подпись токена...${NC}"
if _trial_token_verify_sig "$TRIAL_TOKEN"; then
  _trial_token_save_cache
  ok "Токен подтверждён (TRY-тариф, TG ID ${TRIAL_TG_ID})"
else
  echo ""
  err "Подпись токена не прошла проверку — повреждён, подделан или отозван."
  echo -e "${DIM}   Получи свежий TRY-токен в @AITeamVIPBot и запусти снова.${NC}"
  echo -e "${BOLD}${CYAN}      https://t.me/AITeamVIPBot${NC}"
  exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  T2. Подключение модели («мозги» агента) — opencode DeepSeek Flash Free
# ═══════════════════════════════════════════════════════════════
#
# Wave 37: без этого шага агент молчит — нет подключённой модели.
# Делаем как factory R3: opencode API-ключ → auth-profiles.json +
# config set model. DeepSeek Flash Free — бесплатная (карта не нужна).
echo -e "${BOLD}${WHITE}Шаг 2/4 — Подключаю мозги (AI-модель)...${NC}"
echo ""
echo -e "${DIM}   Агенту нужна модель чтобы думать. Используем ${BOLD}DeepSeek Flash Free${NC}${DIM}${NC}"
echo -e "${DIM}   от opencode — бесплатно, карта не нужна.${NC}"
echo ""
echo -e "   ${CYAN}1.${NC} Открой ${CYAN}https://opencode.ai${NC} (открою сам в браузере)"
echo -e "   ${CYAN}2.${NC} Зарегистрируйся и создай API-ключ (начинается с ${BOLD}sk-${NC})"
echo -e "   ${CYAN}3.${NC} Вставь его сюда"
echo ""

# Открываем браузер автоматически (как factory)
if command -v open &>/dev/null; then
  open "https://opencode.ai" &>/dev/null &
  echo -e "   ${DIM}✓ Открыл opencode.ai в браузере${NC}"
elif command -v xdg-open &>/dev/null; then
  xdg-open "https://opencode.ai" &>/dev/null &
  echo -e "   ${DIM}✓ Открыл opencode.ai в браузере${NC}"
fi
echo ""

OPENCODE_KEY=""
attempts=0
while [[ $attempts -lt 3 ]]; do
  attempts=$((attempts + 1))
  echo -e "   ${BOLD}${WHITE}Вставь API-ключ opencode.ai:${NC}"
  echo -e "   ${DIM}(символы не отображаются при вводе — это нормально)${NC}"
  read -rs OPENCODE_KEY
  echo ""
  OPENCODE_KEY=$(printf '%s' "$OPENCODE_KEY" | tr -d '[:space:]')
  if [[ -z "$OPENCODE_KEY" ]]; then
    warn "Пустой ключ."
    continue
  fi
  if [[ ! "$OPENCODE_KEY" =~ ^sk- ]]; then
    warn "Ключ обычно начинается с 'sk-'. Продолжить всё равно? [y/N]"
    read -r _force
    [[ "$_force" != "y" && "$_force" != "Y" ]] && { OPENCODE_KEY=""; continue; }
  fi
  break
done

if [[ -z "$OPENCODE_KEY" ]]; then
  err "Не получил API-ключ. Создай бесплатный на https://opencode.ai и запусти снова."
  echo -e "${BOLD}${YELLOW}   Полная версия (6 агентов): ${CYAN}${COURSE_URL}${NC}"
  exit 1
fi
ok "Ключ получен (${#OPENCODE_KEY} символов)"
echo ""

# Wave 43: модель фиксирована (Антон) — БЕЗ меню выбора. Тест-драйв
# всегда ставит бесплатную DeepSeek Flash Free, чтобы не путать клиента.
TRIAL_MODEL="opencode-go/deepseek-v4-flash"
ok "Модель: ${TRIAL_MODEL} (бесплатно)"
echo ""

# ═══════════════════════════════════════════════════════════════
#  T3. Telegram-бот для ассистента
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${WHITE}Шаг 3/4 — Telegram-бот для ассистента...${NC}"
echo ""
echo -e "   ${DIM}Создай бота через ${BOLD}@BotFather${NC}${DIM} в Telegram (/newbot) и вставь токен.${NC}"
echo ""

BOT_TOKEN=""
attempts=0
while [[ $attempts -lt 3 ]]; do
  attempts=$((attempts + 1))
  echo -e "   ${BOLD}${WHITE}🤖 Токен бота для Ассистента:${NC}"
  echo -e "   ${DIM}(символы не отображаются при вводе — это нормально)${NC}"
  read -rs BOT_TOKEN
  echo ""
  BOT_TOKEN=$(printf '%s' "$BOT_TOKEN" | tr -d '[:space:]')
  if [[ -z "$BOT_TOKEN" ]]; then
    warn "Пустой токен."
    continue
  fi
  # Валидация через Telegram getMe
  username=$(curl -fsSL --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null \
    | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
  if [[ -n "$username" ]]; then
    ok "Токен валиден: @${username}"
    break
  fi
  warn "Токен не прошёл проверку. Проверь в @BotFather → /mybots."
  BOT_TOKEN=""
done

if [[ -z "$BOT_TOKEN" ]]; then
  err "Не удалось получить рабочий токен бота. Создай бота в @BotFather и запусти снова."
  exit 1
fi

# Wave 39: подключаем Telegram-канал через `openclaw channels add`
# (НЕ config set — это была причина «токен не записался» → бот молчал).
echo -e "   ${DIM}Подключаю Telegram-канал...${NC}"
{ openclaw channels add --channel telegram --name "AI Assistant" --token "$BOT_TOKEN" 2>&1 || true; } \
  | sed -E 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/[TG_TOKEN_REDACTED]/g' \
  | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done
unset BOT_TOKEN
ok "Telegram-бот @${username} подключён"

# DM-политика + allowlist владельца. БЕЗ ЭТОГО бот отвечает «access not
# configured» + pairing code вместо нормального общения.
# TG ID берём ИЗ ТОКЕНА (бот его знает) — клиента не спрашиваем. Это
# заодно анти-шаринг: allowlist на того, кому бот выдал токен.
echo ""
TG_USER_ID="$TRIAL_TG_ID"
if [[ -z "$TG_USER_ID" ]]; then
  # Fallback (на случай токена без TG) — спросим вручную.
  echo -e "   ${BOLD}${WHITE}Твой Telegram user ID (чтобы бот сразу отвечал тебе):${NC}"
  echo -e "   ${DIM}Узнать ID: напиши @userinfobot в Telegram. Можно Enter чтобы пропустить.${NC}"
  read -r TG_USER_ID
  TG_USER_ID=$(printf '%s' "$TG_USER_ID" | tr -cd '0-9')
fi
if [[ -n "$TG_USER_ID" ]]; then
  openclaw config set channels.telegram.dmPolicy allowlist &>/dev/null || true
  openclaw config set channels.telegram.allowFrom "[\"${TG_USER_ID}\"]" &>/dev/null || true
  ok "Доступ настроен на твой Telegram (ID ${TG_USER_ID} из токена)"
else
  warn "TG ID неизвестен — при первом сообщении бот может попросить код подтверждения."
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  T4. Финальная сборка: onboard --non-interactive + прямая настройка
# ═══════════════════════════════════════════════════════════════
#
# Wave 42: Антон просил «прогнать анборд». Прогоняем штатный
# `openclaw onboard --non-interactive` (в его логе он дал «Gateway:
# reachable»). НО onboard в non-interactive режиме не проверен на
# чистой машине — поэтому НЕ полагаемся только на него: ниже сами
# пишем auth-profile и поднимаем gateway проверенными командами
# (wave 37/40/41, идемпотентны). Пояса и подтяжки = надёжность.
# </dev/null — чтобы onboard не завис на возможном промпте.
echo -e "${BOLD}${WHITE}Шаг 4/4 — Финальная настройка (модель + gateway)...${NC}"
echo ""
echo -e "${DIM}   Запускаю штатный мастер OpenClaw в авто-режиме${NC}"
echo -e "${DIM}   (настроит доступ к модели и поднимет движок)...${NC}"

{ openclaw onboard \
    --non-interactive \
    --accept-risk \
    --flow quickstart \
    --auth-choice opencode-zen \
    --opencode-zen-api-key "$OPENCODE_KEY" \
    --skip-channels \
    --skip-search \
    --skip-hooks \
    --skip-skills \
    --skip-ui </dev/null 2>&1 || true; } | tail -10 | sed -E 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
  | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done
# OPENCODE_KEY ещё нужен ниже для прямой записи auth-profile — unset позже.

# Модель по умолчанию (выбор клиента из T2)
openclaw config set agents.defaults.model.primary "$TRIAL_MODEL" &>/dev/null || true
ok "Модель настроена: ${TRIAL_MODEL}"
echo ""

# ─── Агент-ассистент ────────────────────────────────────────────
WORKSPACE="$HOME/.openclaw/workspace-assistant"
mkdir -p "$WORKSPACE"
for f in IDENTITY AGENTS SOUL USER MEMORY; do
  curl -fsSL --max-time 15 "${REPO_RAW}/templates/assistant/${f}.md" -o "${WORKSPACE}/${f}.md" 2>/dev/null \
    && ok "${f}.md" \
    || warn "Не скачал ${f}.md — ассистент в базовом режиме"
done

echo -e "   ${DIM}Регистрирую ассистента...${NC}"
{ openclaw agents add assistant \
    --non-interactive \
    --workspace "$WORKSPACE" \
    --model "$TRIAL_MODEL" \
    --bind telegram 2>&1 || true; } | while IFS= read -r line; do
  echo -e "   ${DIM}${line}${NC}"
done
openclaw agents bind --agent assistant --bind telegram &>/dev/null || true

# Wave 37+42: пишем auth-profile ассистенту НАПРЯМУЮ (проверенный путь
# factory R3 — не зависит от того, создал ли onboard профиль для main).
# БЕЗ ЭТОГО АГЕНТ МОЛЧИТ — нет авторизации к provider.
AUTH_DIR="$HOME/.openclaw/agents/assistant/agent"
mkdir -p "$AUTH_DIR"
cat > "${AUTH_DIR}/auth-profiles.json" <<AUTHEOF
{
  "version": 1,
  "profiles": {
    "opencode-go:default": {
      "type": "api_key",
      "provider": "opencode-go",
      "key": "${OPENCODE_KEY}"
    }
  },
  "lastGood": {
    "opencode": "opencode-go:default"
  }
}
AUTHEOF
chmod 600 "${AUTH_DIR}/auth-profiles.json"
unset OPENCODE_KEY  # ключ больше не нужен в памяти
ok "Доступ к модели записан ассистенту"

# Wave 40/41: НАДЁЖНЫЙ запуск gateway (страховка — даже если onboard
# выше уже всё поднял, команды идемпотентны). Прошлые баги: grep
# «running» ловил «not running»; gateway start не грузит LaunchAgent —
# нужен launchctl bootstrap. mode local → install → bootstrap → start.
echo -e "   ${DIM}Настраиваю и поднимаю gateway (движок)...${NC}"
openclaw config set gateway.mode local &>/dev/null || true
openclaw gateway install &>/dev/null || true
if [[ "$OS_NAME" == "macos" ]]; then
  _plist="$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
  if [[ -f "$_plist" ]]; then
    launchctl bootstrap "gui/$(id -u)" "$_plist" 2>/dev/null \
      || launchctl load "$_plist" 2>/dev/null || true
  fi
fi
openclaw gateway start &>/dev/null || true
openclaw gateway restart &>/dev/null || true  # подхватить только что добавленного агента
sleep 3

# ═══════════════════════════════════════════════════════════════
#  T5. Быстрый онбординг — проверяем что всё на месте (по-русски)
# ═══════════════════════════════════════════════════════════════
#
# Wave 42: Антон просил «прогнать анборд по-русски» — чтобы человек,
# который не разбирается в техничке, сам убедился что всё встало.
# Прогоняем понятный чек-лист по каждому узлу: движок, модель,
# Telegram, агент, gateway. Никакого английского TUI — простой ✓/✗.
echo ""
divider
echo -e "${BOLD}${WHITE}🚀 Быстрый онбординг — проверяю что всё работает...${NC}"
echo ""

_onb_ok=0
_onb_total=5

if command -v openclaw >/dev/null 2>&1; then
  ok "Движок OpenClaw установлен"; _onb_ok=$((_onb_ok + 1))
else err "Движок OpenClaw установлен"; fi

if openclaw config get agents.defaults.model.primary 2>/dev/null | grep -q .; then
  ok "Мозги (AI-модель) подключены"; _onb_ok=$((_onb_ok + 1))
else err "Мозги (AI-модель) подключены"; fi

if openclaw channels status 2>&1 | grep -qi telegram; then
  ok "Telegram-бот привязан"; _onb_ok=$((_onb_ok + 1))
else err "Telegram-бот привязан"; fi

if openclaw agents list 2>&1 | grep -qi assistant; then
  ok "Агент-ассистент создан"; _onb_ok=$((_onb_ok + 1))
else err "Агент-ассистент создан"; fi

if openclaw gateway status 2>&1 | grep -qE "LaunchAgent \(loaded\)|RPC probe: ok|reachable"; then
  ok "Gateway (движок) запущен"; _onb_ok=$((_onb_ok + 1))
else err "Gateway (движок) запущен"; fi

echo ""
if [[ "$_onb_ok" -eq "$_onb_total" ]]; then
  echo -e "   ${BOLD}${GREEN}✅ Онбординг пройден: ${_onb_ok}/${_onb_total} — всё работает!${NC}"
else
  echo -e "   ${BOLD}${YELLOW}Онбординг: ${_onb_ok}/${_onb_total} проверок прошло.${NC}"
  echo -e "   ${DIM}   Если бот молчит — открой НОВЫЙ терминал и выполни:${NC} ${BOLD}openclaw onboard${NC}"
fi

# ═══════════════════════════════════════════════════════════════
#  Финал
# ═══════════════════════════════════════════════════════════════
divider
echo ""
echo -e "${BOLD}${GREEN}🎉 Демо готово! Твой AI-ассистент работает.${NC}"
echo ""
echo -e "   ${BOLD}${WHITE}Что дальше:${NC}"
echo -e "   ${CYAN}1.${NC} Открой Telegram, найди своего бота, напиши ${BOLD}/start${NC} или ${BOLD}привет${NC}"
echo -e "   ${CYAN}2.${NC} Попробуй: «придумай 3 идеи для поста» / «помоги составить план»"
echo -e "   ${CYAN}3.${NC} Ассистент покажет на что способна AI-команда"
echo ""
# Wave 39: если openclaw не в PATH текущей сессии — подскажем про новый
# терминал (nvm прописан в rc, но текущая сессия его ещё не перечитала).
if ! command -v openclaw &>/dev/null; then
  echo -e "   ${BOLD}${YELLOW}⚠ Команда openclaw в этом терминале пока недоступна.${NC}"
  echo -e "   ${DIM}   Открой НОВЫЙ терминал — или выполни: ${BOLD}source ~/.zshrc${NC}"
  echo -e "   ${DIM}   После этого заработает: openclaw --version / openclaw doctor${NC}"
  echo ""
fi
if [[ "$VPS_MODE" == true ]]; then
  echo -e "   ${BOLD}${WHITE}Dashboard (VPS):${NC} ssh -L 18789:127.0.0.1:18789 root@<ip>, затем http://127.0.0.1:18789"
else
  echo -e "   ${BOLD}${WHITE}Dashboard:${NC} ${CYAN}http://127.0.0.1:18789${NC}"
fi
echo ""
# ─── Windows: предложить официальный интерфейс (Companion GUI) ───
# Только в интерактивном терминале (в headless/CI не спрашиваем).
if [[ -t 0 && ( "$OS_NAME" == "windows-bash" || "$OS_NAME" == "wsl" ) ]]; then
  echo -e "${BOLD}${WHITE}🪟 Хочешь удобный интерфейс для Windows? (OpenClaw Windows Hub)${NC}"
  echo -e "${DIM}   Трей-иконка, командный центр, диагностика — без терминала.${NC}"
  echo -e "${BOLD}${WHITE}   Открыть страницу загрузки? [y/N]:${NC}"
  read -r _companion_ans || true
  if [[ "${_companion_ans:-}" =~ ^[Yy]$ ]]; then
    _companion_url="https://docs.openclaw.ai/platforms/windows"
    if   command -v cmd.exe        >/dev/null 2>&1; then cmd.exe /c start "" "$_companion_url" >/dev/null 2>&1 || true
    elif command -v powershell.exe >/dev/null 2>&1; then powershell.exe -NoProfile -Command "Start-Process '$_companion_url'" >/dev/null 2>&1 || true
    elif command -v explorer.exe   >/dev/null 2>&1; then explorer.exe "$_companion_url" >/dev/null 2>&1 || true
    elif command -v start          >/dev/null 2>&1; then start "" "$_companion_url" >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}✓${NC} Страница загрузки: ${CYAN}${_companion_url}${NC}"
    unset _companion_url
  fi
  unset _companion_ans
  echo ""
fi
echo -e "${BOLD}${YELLOW}   ⭐ Понравилось? Полная версия — команда из 6 агентов + супер-агент:${NC}"
echo -e "${BOLD}${CYAN}      ${COURSE_URL}${NC}"
echo ""
# Wave 44: открываем сайт-продажник в браузере (как opencode.ai в Шаге 2) —
# клиент сразу видит полную версию, а не просто ссылку в терминале.
if command -v open &>/dev/null; then
  open "$COURSE_URL" &>/dev/null &
  echo -e "   ${DIM}✓ Открыл страницу полной версии в браузере${NC}"
elif command -v xdg-open &>/dev/null; then
  xdg-open "$COURSE_URL" &>/dev/null &
  echo -e "   ${DIM}✓ Открыл страницу полной версии в браузере${NC}"
fi
echo ""
divider
