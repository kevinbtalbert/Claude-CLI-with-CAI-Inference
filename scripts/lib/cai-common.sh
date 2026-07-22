#!/usr/bin/env bash
# cai-common.sh — shared helpers for CAI Inference + Claude Code + LiteLLM.
# Sourced by install-cai-claude.sh and claude-cai-launch.sh. Do not execute directly.

: "${CAI_HOME:?CAI_HOME must be set before sourcing cai-common.sh}"

CONFIG_FILE="${CAI_CONFIG_FILE:-${CAI_HOME}/cai-inference.conf}"
LITELLM_CONFIG="${CAI_LITELLM_CONFIG:-${CAI_HOME}/litellm-config.yaml}"
LITELLM_PID_FILE="${CAI_LITELLM_PID_FILE:-${CAI_HOME}/litellm.pid}"
LITELLM_LOG="${CAI_LITELLM_LOG:-${CAI_HOME}/litellm.log}"
LITELLM_PORT="${CAI_LITELLM_PORT:-4000}"
LITELLM_MASTER_KEY="${CAI_LITELLM_MASTER_KEY:-sk-cai-local-proxy}"
PROXY_URL="http://127.0.0.1:${LITELLM_PORT}"

CLAUDE_OPUS_ALIAS="${CAI_CLAUDE_OPUS_ALIAS:-claude-opus-4-6}"
CLAUDE_SONNET_ALIAS="${CAI_CLAUDE_SONNET_ALIAS:-claude-sonnet-4-6}"
CLAUDE_HAIKU_ALIAS="${CAI_CLAUDE_HAIKU_ALIAS:-claude-haiku-4-5-20251001}"

CAI_API_BASE="${CAI_API_BASE:-}"
CAI_MODEL_NAME="${CAI_MODEL_NAME:-}"
CAI_CDP_TOKEN="${CAI_CDP_TOKEN:-}"

cai_log() { printf '%s\n' "$*" >&2; }
cai_die() { cai_log "ERROR: $*"; exit 1; }

cai_is_interactive() {
  [ -t 0 ] && [ -t 1 ] && [ -z "${CAI_NONINTERACTIVE:-}" ]
}

cai_have_cmd() { command -v "$1" >/dev/null 2>&1; }

cai_prompt_default() {
  local __var="$1" __prompt="$2" __default="$3" __reply=""
  if ! cai_is_interactive; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi
  printf '%s [%s]: ' "$__prompt" "$__default" >&2
  read -r __reply || __reply=""
  if [ -z "$__reply" ]; then __reply="$__default"; fi
  printf -v "$__var" '%s' "$__reply"
}

cai_prompt_secret_default() {
  local __var="$1" __prompt="$2" __default="$3" __reply=""
  if ! cai_is_interactive; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi
  if [ -n "$__default" ]; then
    cai_log "${__prompt} — press Enter to keep saved token, or paste a new one:"
  else
    cai_log "${__prompt} — paste token, then press Enter:"
  fi
  cai_log "(Visible while pasting — avoids terminal hang with long JWTs.)"

  # read -rs + bracketed paste hangs on long JWT pastes in many terminals (Cursor, iTerm, etc.)
  if [ -r /dev/tty ]; then
    printf '\e[?2004l' >/dev/tty 2>/dev/null || true
    read -r __reply </dev/tty || __reply=""
    printf '\e[?2004h' >/dev/tty 2>/dev/null || true
  else
    read -r __reply || __reply=""
  fi

  # Trim whitespace/newlines accidentally included when pasting
  __reply="$(printf '%s' "$__reply" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [ -z "$__reply" ]; then __reply="$__default"; fi
  printf -v "$__var" '%s' "$__reply"
}

cai_shell_quote() {
  local q
  printf -v q '%q' "$1"
  printf '%s' "$q"
}

cai_load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    set -a
    source "$CONFIG_FILE"
    set +a
  fi
  CAI_API_BASE="${CAI_API_BASE:-}"
  CAI_MODEL_NAME="${CAI_MODEL_NAME:-}"
  CAI_CDP_TOKEN="${CAI_CDP_TOKEN:-${CDP_TOKEN:-}}"
  CAI_LITELLM_PORT="${CAI_LITELLM_PORT:-$LITELLM_PORT}"
  LITELLM_PORT="$CAI_LITELLM_PORT"
  PROXY_URL="http://127.0.0.1:${LITELLM_PORT}"
}

cai_save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  umask 077
  cat >"$CONFIG_FILE" <<EOF
# Cloudera AI Inference — saved by install-cai-claude.sh / claude-cai
CAI_API_BASE=$(cai_shell_quote "$CAI_API_BASE")
CAI_MODEL_NAME=$(cai_shell_quote "$CAI_MODEL_NAME")
CAI_CDP_TOKEN=$(cai_shell_quote "$CAI_CDP_TOKEN")
CAI_LITELLM_PORT=$(cai_shell_quote "$LITELLM_PORT")
EOF
  chmod 600 "$CONFIG_FILE"
}

cai_normalize_url() {
  local url="$1"
  local token="$2"
  url="${url%/}"

  case "$url" in
    */openai/v1|*/v1)
      printf '%s' "$url"
      return 0
      ;;
  esac

  local try_openai="${url}/openai/v1"
  local try_v1="${url}/v1"
  if curl -sf -o /dev/null --connect-timeout 8 --max-time 15 \
    -H "Authorization: Bearer ${token}" "${try_openai}/models" 2>/dev/null; then
    printf '%s' "$try_openai"
    return 0
  fi
  if curl -sf -o /dev/null --connect-timeout 8 --max-time 15 \
    -H "Authorization: Bearer ${token}" "${try_v1}/models" 2>/dev/null; then
    printf '%s' "$try_v1"
    return 0
  fi

  cai_die "Could not reach ${url}. Expected .../v1 (NIM) or .../openai/v1 (vLLM). Check URL and token."
}

cai_detect_endpoint_kind() {
  case "$1" in
    */openai/v1) printf 'vllm' ;;
    */v1) printf 'nim' ;;
    *) printf 'unknown' ;;
  esac
}

cai_fetch_model_name() {
  local base="$1" token="$2"
  local body
  body="$(curl -sf --connect-timeout 8 --max-time 20 \
    -H "Authorization: Bearer ${token}" \
    "${base}/models")" || cai_die "GET ${base}/models failed — check token and URL."

  if cai_have_cmd python3; then
    printf '%s' "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["id"])'
    return 0
  fi
  if cai_have_cmd jq; then
    jq -r '.data[0].id // empty' <<<"$body"
    return 0
  fi
  cai_die "Need python3 or jq to parse /models response."
}

cai_validate_connection() {
  local base="$1" token="$2"
  curl -sf --connect-timeout 8 --max-time 20 \
    -H "Authorization: Bearer ${token}" \
    "${base}/models" >/dev/null \
    || cai_die "Connection test failed for ${base}/models"
}

cai_litellm_bin() {
  local bin="${CAI_VENV_BIN:-${CAI_HOME}/venv/bin}/litellm"
  [ -x "$bin" ] || cai_die "LiteLLM not installed. Run: install-cai-claude.sh"
  printf '%s' "$bin"
}

cai_write_litellm_config() {
  mkdir -p "$(dirname "$LITELLM_CONFIG")"
  local openai_model="openai/${CAI_MODEL_NAME}"
  cat >"$LITELLM_CONFIG" <<YAML
# Generated by claude-cai — local proxy to Cloudera AI Inference
model_list:
  - model_name: ${CLAUDE_OPUS_ALIAS}
    litellm_params:
      model: ${openai_model}
      api_base: ${CAI_API_BASE}
      api_key: os.environ/CAI_CDP_TOKEN
  - model_name: ${CLAUDE_SONNET_ALIAS}
    litellm_params:
      model: ${openai_model}
      api_base: ${CAI_API_BASE}
      api_key: os.environ/CAI_CDP_TOKEN
  - model_name: ${CLAUDE_HAIKU_ALIAS}
    litellm_params:
      model: ${openai_model}
      api_base: ${CAI_API_BASE}
      api_key: os.environ/CAI_CDP_TOKEN

litellm_settings:
  master_key: ${LITELLM_MASTER_KEY}
  drop_params: true
YAML
}

cai_proxy_health_ok() {
  curl -sf --connect-timeout 2 --max-time 5 \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    "${PROXY_URL}/health/liveliness" >/dev/null 2>&1 \
    || curl -sf --connect-timeout 2 --max-time 5 "${PROXY_URL}/health" >/dev/null 2>&1
}

cai_stop_proxy() {
  if [ -f "$LITELLM_PID_FILE" ]; then
    local pid
    pid="$(cat "$LITELLM_PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
    rm -f "$LITELLM_PID_FILE"
  fi
}

cai_start_litellm_proxy() {
  local litellm_bin
  litellm_bin="$(cai_litellm_bin)"
  cai_write_litellm_config

  local new_hash="" old_hash=""
  if cai_have_cmd shasum; then
    new_hash="$(shasum -a 256 "$LITELLM_CONFIG" | awk '{print $1}')"
    old_hash="$(cat "${LITELLM_CONFIG}.hash" 2>/dev/null || true)"
  fi

  if cai_proxy_health_ok && [ -n "$new_hash" ] && [ "$new_hash" = "$old_hash" ]; then
    cai_log "LiteLLM proxy already running at ${PROXY_URL}"
    return 0
  fi

  if cai_proxy_health_ok; then
    cai_log "Config changed — restarting LiteLLM proxy"
  fi
  cai_stop_proxy

  cai_log "Starting LiteLLM proxy at ${PROXY_URL} → ${CAI_API_BASE}"
  export CAI_CDP_TOKEN
  : >"$LITELLM_LOG"

  "$litellm_bin" --config "$LITELLM_CONFIG" --host 127.0.0.1 --port "$LITELLM_PORT" \
    >>"$LITELLM_LOG" 2>&1 &
  local pid=$!
  echo "$pid" >"$LITELLM_PID_FILE"

  local i
  for i in $(seq 1 30); do
    if cai_proxy_health_ok; then
      cai_log "LiteLLM proxy ready (pid ${pid}). Log: ${LITELLM_LOG}"
      [ -n "$new_hash" ] && printf '%s' "$new_hash" >"${LITELLM_CONFIG}.hash"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cai_log "LiteLLM failed to start. Last log lines:"
      tail -20 "$LITELLM_LOG" >&2 || true
      cai_die "LiteLLM proxy exited unexpectedly."
    fi
    sleep 0.5
  done
  cai_die "LiteLLM proxy did not become healthy within 15s. See ${LITELLM_LOG}"
}

cai_prompt_user_config() {
  local default_url="${CAI_API_BASE:-}"
  local default_token="${CAI_CDP_TOKEN:-}"
  local default_model="${CAI_MODEL_NAME:-}"
  local input_url input_token endpoint_kind

  if cai_is_interactive; then
    cai_log ""
    cai_log "Claude Code + Cloudera AI Inference"
    cai_log "Press Enter to keep saved values in [brackets]."
    cai_log ""
  fi

  cai_prompt_default input_url "CAI endpoint URL (from Model Endpoint Code Sample)" "$default_url"
  cai_prompt_secret_default input_token "CDP JWT / API token" "$default_token"

  [ -n "$input_url" ] || cai_die "Endpoint URL is required."
  [ -n "$input_token" ] || cai_die "CDP token is required."

  cai_log "Checking endpoint (may take a few seconds) ..."
  CAI_API_BASE="$(cai_normalize_url "$input_url" "$input_token")"
  endpoint_kind="$(cai_detect_endpoint_kind "$CAI_API_BASE")"
  cai_log "Endpoint type: ${endpoint_kind} (${CAI_API_BASE})"

  if [ -n "$default_model" ]; then
    cai_prompt_default CAI_MODEL_NAME "Model name" "$default_model"
  else
    cai_log "Discovering model from GET /models ..."
    CAI_MODEL_NAME="$(cai_fetch_model_name "$CAI_API_BASE" "$input_token")"
    cai_log "Using model: ${CAI_MODEL_NAME}"
  fi

  CAI_CDP_TOKEN="$input_token"
  cai_save_config
}

cai_ensure_claude() {
  cai_have_cmd claude || cai_die "Claude Code not installed. Run: install-cai-claude.sh"
}

cai_launch_claude() {
  cai_ensure_claude
  export ANTHROPIC_BASE_URL="$PROXY_URL"
  export ANTHROPIC_API_KEY="$LITELLM_MASTER_KEY"
  export ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$CLAUDE_OPUS_ALIAS"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$CLAUDE_SONNET_ALIAS"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$CLAUDE_HAIKU_ALIAS"
  export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="${CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY:-1}"

  cai_log ""
  cai_log "Launching Claude Code → LiteLLM (${PROXY_URL}) → CAI (${CAI_MODEL_NAME})"
  cai_log ""

  if [ $# -gt 0 ]; then
    exec claude "$@"
  else
    exec claude
  fi
}
