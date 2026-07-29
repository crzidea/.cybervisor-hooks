#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${CYBERVISOR_TELEGRAM_ENV_FILE:-${HOME}/.cybervisor/telegram.env}"

if [[ ! -r "${ENV_FILE}" ]]; then
  echo "Telegram environment file is not readable: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${CYBERVISOR_TELEGRAM_BOT_TOKEN:?Telegram bot token is required}"
: "${CYBERVISOR_TELEGRAM_CHAT_ID:?Telegram chat ID is required}"

MESSAGE="$(cat)"
if [[ -z "${MESSAGE}" ]]; then
  echo "Telegram message must not be empty" >&2
  exit 1
fi

PARSE_MODE="${PARSE_MODE:-HTML}"

RESPONSE="$(curl --fail --silent --show-error \
  --form-string "chat_id=${CYBERVISOR_TELEGRAM_CHAT_ID}" \
  --form-string "parse_mode=${PARSE_MODE}" \
  --form-string "text=${MESSAGE}" \
  "https://api.telegram.org/bot${CYBERVISOR_TELEGRAM_BOT_TOKEN}/sendMessage")"

if command -v jq >/dev/null 2>&1; then
  MSG_ID="$(jq -r '.result.message_id // empty' <<< "${RESPONSE}" 2>/dev/null || true)"
  if [[ -n "${MSG_ID}" ]]; then
    echo "Telegram notification sent successfully (Message ID: ${MSG_ID})."
  else
    echo "Telegram notification sent successfully."
  fi
else
  echo "Telegram notification sent successfully."
fi
