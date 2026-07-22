#!/usr/bin/env bash
#
# claude-cai-launch.sh — Launch Claude Code via local LiteLLM → CAI Inference.
#
# Installed to ~/.local/bin/claude-cai by install-cai-claude.sh.
# Uses the Python venv and config created during install.
#
# Usage:
#   claude-cai                  # interactive Claude Code session
#   claude-cai -p "hello"       # one-shot prompt
#   claude-cai --stop-proxy     # stop background LiteLLM proxy

set -Eeuo pipefail
IFS=$' \t\n'

# install-cai-claude.sh writes this file with absolute paths.
INSTALL_ENV="${CAI_INSTALL_ENV:-${HOME}/.claude/cai-inference/install.env}"
if [ ! -f "$INSTALL_ENV" ]; then
  printf 'ERROR: Not installed. Run install-cai-claude.sh first.\n' >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$INSTALL_ENV"

CAI_HOME="${CAI_HOME:?}"
# shellcheck disable=SC1090
source "${CAI_HOME}/lib/cai-common.sh"

usage() {
  cat <<EOF
Usage: claude-cai [claude-args...]

Launch Claude Code through a local LiteLLM proxy to Cloudera AI Inference.

  claude-cai --stop-proxy     Stop the background LiteLLM proxy
  claude-cai --reconfigure    Re-prompt for endpoint URL and JWT

Install / reinstall: ${CAI_INSTALL_SCRIPT:-install-cai-claude.sh}
EOF
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --stop-proxy)
      cai_stop_proxy
      cai_log "Stopped LiteLLM proxy."
      exit 0
      ;;
    --reconfigure)
      cai_load_config
      cai_prompt_user_config
      cai_log "Configuration saved to ${CONFIG_FILE}"
      exit 0
      ;;
  esac

  cai_load_config

  if [ -z "${CAI_API_BASE:-}" ] || [ -z "${CAI_CDP_TOKEN:-}" ]; then
    cai_prompt_user_config
  else
    CAI_API_BASE="$(cai_normalize_url "$CAI_API_BASE" "$CAI_CDP_TOKEN")"
  fi

  [ -n "$CAI_MODEL_NAME" ] || CAI_MODEL_NAME="$(cai_fetch_model_name "$CAI_API_BASE" "$CAI_CDP_TOKEN")"

  cai_start_litellm_proxy
  cai_launch_claude "$@"
}

main "$@"
