#!/usr/bin/env bash
# Behavioral regression: trial accepts only freshly issued OC5-TRY tokens.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
trial_script="$repo_root/scripts/install-trial.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

private_key="$tmpdir/test.private.pem"
public_key="$tmpdir/test.public.pem"
openssl genpkey -algorithm ED25519 -out "$private_key" >/dev/null 2>&1
openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1

# Import only the token helpers; never execute the real installer in a test.
# shellcheck disable=SC1090
source <(sed -n '/^#  TRY-токен доступа/,/^# ─── Парсинг флагов/p' "$trial_script" | sed '$d')
TRIAL_PUBLIC_KEY_PEM="$(<"$public_key")"

token="$(TEST_PRIVATE_KEY="$private_key" node -e '
const crypto = require("crypto");
const fs = require("fs");
const hash = "ABCDEF0123456789";
const tg = "123456789";
const nonce = "ABCDEF0123456789ABCDEF01";
const payload = `OC5|TRY|${hash}|${tg}|${nonce}`;
const key = crypto.createPrivateKey(fs.readFileSync(process.env.TEST_PRIVATE_KEY));
const signature = crypto.sign(null, Buffer.from(payload), key).toString("base64url");
process.stdout.write(`OC5-TRY-${hash}-${tg}-${nonce}-${signature}`);
')"

_trial_token_format_ok "$token"
[[ "$TRIAL_TG_ID" == "123456789" ]]
_trial_token_verify_sig "$token"

legacy="TRY-ABCDEF0123456789-123456789-$(printf 'X%.0s' {1..86})"
if _trial_token_format_ok "$legacy"; then
  echo "legacy TRY token was accepted" >&2
  exit 1
fi

echo "trial token rotation cases passed"
