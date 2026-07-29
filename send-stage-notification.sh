#!/usr/bin/env bash
set -euo pipefail

STAGE_NAME="${CYBERVISOR_STAGE_NAME:-Unknown}"
ITERATION_COUNT="${CYBERVISOR_STAGE_ITERATION:-1}"
MAX_ITERATIONS="${CYBERVISOR_STAGE_MAX_ITERATIONS:-1}"
ATTEMPT="${CYBERVISOR_STAGE_ATTEMPT:-1}"
MAX_RETRIES="${CYBERVISOR_STAGE_MAX_RETRIES:-1}"
STAGE_SUCCESS="${CYBERVISOR_STAGE_SUCCESS:-}"

WORKSPACE_NAME="$(basename "$PWD")"
WORKSPACE_KEY="$(printf '%s' "${PWD}" | md5sum | awk '{print $1}')"
STATE_DIR="${HOME}/.cybervisor/hooks/state"
BASELINE_FILE="${STATE_DIR}/baseline_${WORKSPACE_KEY}.txt"

escape_html() {
  local str="$1"
  str="${str//&/&amp;}"
  str="${str//</&lt;}"
  str="${str//>/&gt;}"
  printf '%s' "${str}"
}

discover_repos() {
  local repos=()

  if git -C . rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repos+=(".")
  fi

  while IFS= read -r git_entry; do
    if [[ -n "${git_entry}" ]]; then
      local dir
      dir="$(dirname "${git_entry#./}")"
      if [[ "${dir}" != "." && "${dir}" != ".." && "${dir}" != .* && "${dir}" != */.* && "${dir}" != *node_modules* && "${dir}" != *venv* ]]; then
        if git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          repos+=("${dir}")
        fi
      fi
    fi
  done < <(find . -mindepth 2 \( -name .git \) 2>/dev/null | sort)

  printf '%s\n' "${repos[@]}"
}

record_baseline() {
  mkdir -p "${STATE_DIR}"
  mapfile -t repos < <(discover_repos)
  local tmp_file
  tmp_file="$(mktemp)"
  for repo in "${repos[@]}"; do
    local head
    head="$(git -C "${repo}" rev-parse HEAD 2>/dev/null || true)"
    printf '%s\t%s\n' "${repo}" "${head}" >> "${tmp_file}"
  done
  mv "${tmp_file}" "${BASELINE_FILE}"
}

get_baseline_head() {
  local target_repo="$1"
  if [[ -f "${BASELINE_FILE}" ]]; then
    awk -F'\t' -v r="${target_repo}" '$1 == r {print $2}' "${BASELINE_FILE}"
  fi
}

HOOK_PHASE="${CYBERVISOR_HOOK_PHASE:-}"

if [[ "${HOOK_PHASE}" == "before_stage" ]] || [[ -z "${STAGE_SUCCESS}" ]]; then
  STATUS_BADGE="🚀 <b>Starting</b>"
  record_baseline
elif [[ "${STAGE_SUCCESS}" == "true" ]]; then
  STATUS_BADGE="✅ <b>Completed</b>"
elif [[ "${STAGE_SUCCESS}" == "false" ]]; then
  STATUS_BADGE="❌ <b>Failed</b>"
else
  STATUS_BADGE="$(escape_html "${STAGE_SUCCESS}")"
fi

SAFE_WORKSPACE="$(escape_html "${WORKSPACE_NAME}")"
SAFE_STAGE="$(escape_html "${STAGE_NAME}")"
SAFE_ITERATION="$(escape_html "${ITERATION_COUNT}/${MAX_ITERATIONS}")"
SAFE_ATTEMPT="$(escape_html "${ATTEMPT}/${MAX_RETRIES}")"

MESSAGE="<b>Workspace:</b> <code>${SAFE_WORKSPACE}</code>
<b>Stage:</b> <b>${SAFE_STAGE}</b> — ${STATUS_BADGE}
<b>Iteration:</b> <code>${SAFE_ITERATION}</code>
<b>Attempt:</b> <code>${SAFE_ATTEMPT}</code>"

if [[ "${STAGE_NAME}" == "Commit" && "${HOOK_PHASE}" != "before_stage" && -n "${STAGE_SUCCESS}" ]]; then
  mapfile -t repos < <(discover_repos)
  COMMIT_REPORT=""

  for repo in "${repos[@]}"; do
    repo_name="${repo#./}"
    if [[ "${repo_name}" == "." ]]; then
      repo_name="workspace"
    fi

    base_head="$(get_baseline_head "${repo}")"
    curr_head="$(git -C "${repo}" rev-parse HEAD 2>/dev/null || true)"

    commit_hashes=""
    if [[ -n "${base_head}" && -n "${curr_head}" && "${base_head}" != "${curr_head}" ]]; then
      commit_hashes="$(git -C "${repo}" log "${base_head}..${curr_head}" --format="%H" 2>/dev/null || true)"
    fi

    if [[ -n "${commit_hashes}" ]]; then
      SAFE_REPO="$(escape_html "${repo_name}")"
      COMMIT_REPORT+=$'\n\n📁 <b>'"${SAFE_REPO}"'</b>'

      while IFS= read -r commit_hash; do
        if [[ -n "${commit_hash}" ]]; then
          log_line="$(git -C "${repo}" log -1 --format="%h %s" "${commit_hash}" 2>/dev/null || true)"
          stat_line="$(git -C "${repo}" log -1 --shortstat --format="" "${commit_hash}" 2>/dev/null | xargs || true)"

          if [[ -n "${log_line}" ]]; then
            hash="${log_line%% *}"
            subject="${log_line#* }"
            SAFE_HASH="$(escape_html "${hash}")"
            SAFE_SUBJECT="$(escape_html "${subject}")"
            SAFE_STAT="$(escape_html "${stat_line}")"

            COMMIT_REPORT+=$'\n• <code>'"${SAFE_HASH}"'</code> '"${SAFE_SUBJECT}"
            if [[ -n "${SAFE_STAT}" ]]; then
              COMMIT_REPORT+=$'\n  <i>'"${SAFE_STAT}"'</i>'
            fi
          fi
        fi
      done <<< "${commit_hashes}"
    fi
  done

  if [[ -n "${COMMIT_REPORT}" ]]; then
    MESSAGE+=$'\n\n<b>📌 Commit Report</b>'"${COMMIT_REPORT}"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEND_TELEGRAM="${SCRIPT_DIR}/send-telegram-message.sh"

if [[ -x "${SEND_TELEGRAM}" ]]; then
  printf '%s\n' "${MESSAGE}" | "${SEND_TELEGRAM}"
elif command -v send-telegram-message.sh >/dev/null 2>&1; then
  printf '%s\n' "${MESSAGE}" | send-telegram-message.sh
else
  echo "send-telegram-message.sh not found or not executable" >&2
  exit 1
fi
