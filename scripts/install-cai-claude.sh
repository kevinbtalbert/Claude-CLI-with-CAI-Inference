#!/usr/bin/env bash
#
# install-cai-claude.sh
#
# One-time installer for Claude Code + Cloudera AI Inference (local LiteLLM proxy).
#
#   1. Fail fast if python3 or curl are missing
#   2. Create ~/.claude/cai-inference/venv and install litellm[proxy]
#   3. Optionally install Claude Code CLI
#   4. Prompt for CAI endpoint URL + JWT; validate connection
#   5. Install launch script → ~/.local/bin/claude-cai
#
# After install, run:  claude-cai
#
# Unattended:
#   CAI_NONINTERACTIVE=1 CAI_API_BASE=... CAI_CDP_TOKEN=... ./install-cai-claude.sh

set -Eeuo pipefail
IFS=$' \t\n'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAI_HOME_DEFAULT="${HOME}/.claude/cai-inference"
CAI_HOME="${CAI_INSTALL_HOME:-$CAI_HOME_DEFAULT}"
VENV_DIR="${CAI_HOME}/venv"
LAUNCH_NAME="claude-cai"
LOCAL_BIN="${HOME}/.local/bin"
INSTALLED_LAUNCH="${LOCAL_BIN}/${LAUNCH_NAME}"

# ---------------------------------------------------------------------------
# Logging (minimal — full UX comes after lib is installed)
# ---------------------------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_interactive() {
  [ -t 0 ] && [ -t 1 ] && [ -z "${CAI_NONINTERACTIVE:-}" ]
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="$1" default="${2:-y}" reply hint
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if ! is_interactive; then
    [ "$default" = "y" ] && return 0 || return 1
  fi
  printf '%s %s: ' "$prompt" "$hint" >&2
  read -r reply || reply=""
  [ -z "$reply" ] && reply="$default"
  case "$reply" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Step 1 — Requirements (fail fast)
# ---------------------------------------------------------------------------
check_requirements() {
  log ""
  log "=== Step 1/6 — Checking requirements ==="

  have_cmd python3 || die "python3 is required. Install Python 3.9+ and re-run this script."
  have_cmd curl || die "curl is required. Install curl and re-run this script."

  local pyver
  pyver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  log "  python3: $(command -v python3) (${pyver})"
  log "  curl:    $(command -v curl)"

  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
    || die "Python 3.9+ required (found ${pyver})."

  log "  Requirements OK."
}

# ---------------------------------------------------------------------------
# Step 2 — Python virtual environment + LiteLLM
# ---------------------------------------------------------------------------
setup_venv() {
  log ""
  log "=== Step 2/6 — Creating Python virtual environment ==="
  log "  Location: ${VENV_DIR}"

  mkdir -p "$CAI_HOME"
  if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR" || die "Failed to create venv at ${VENV_DIR}"
  else
    log "  Reusing existing venv."
  fi

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  log "  Upgrading pip ..."
  python -m pip install --upgrade pip wheel -q

  log "  Installing litellm[proxy] (may take a minute) ..."
  python -m pip install 'litellm[proxy]' -q

  [ -x "${VENV_DIR}/bin/litellm" ] || die "litellm install failed."
  log "  LiteLLM: $("${VENV_DIR}/bin/litellm" --version 2>/dev/null | head -1 || echo installed)"

  deactivate 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Step 3 — Claude Code CLI
# ---------------------------------------------------------------------------
ensure_claude_code() {
  log ""
  log "=== Step 3/6 — Claude Code CLI ==="

  if have_cmd claude; then
    log "  Claude Code: $(claude --version 2>/dev/null | head -1)"
    return 0
  fi

  log "  Claude Code not found."
  if is_interactive && confirm "Install Claude Code now (curl installer)?" "y"; then
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="${HOME}/.local/bin:${PATH}"
  fi

  if have_cmd claude; then
    log "  Claude Code: $(claude --version 2>/dev/null | head -1)"
  else
    die "Claude Code is required. Install: curl -fsSL https://claude.ai/install.sh | bash"
  fi
}

# ---------------------------------------------------------------------------
# Step 4 — Install launch script + library
# ---------------------------------------------------------------------------
install_launcher() {
  log ""
  log "=== Step 4/6 — Installing launcher ==="

  mkdir -p "${CAI_HOME}/lib" "${CAI_HOME}/bin" "$LOCAL_BIN"

  cp "${SCRIPT_DIR}/lib/cai-common.sh" "${CAI_HOME}/lib/cai-common.sh"
  cp "${SCRIPT_DIR}/claude-cai-launch.sh" "${CAI_HOME}/bin/claude-cai-launch.sh"
  chmod +x "${CAI_HOME}/bin/claude-cai-launch.sh"

  # Wrapper in ~/.local/bin delegates to installed launch script.
  cat >"$INSTALLED_LAUNCH" <<EOF
#!/usr/bin/env bash
exec "${CAI_HOME}/bin/claude-cai-launch.sh" "\$@"
EOF
  chmod +x "$INSTALLED_LAUNCH"

  cat >"${CAI_HOME}/install.env" <<EOF
# Generated by install-cai-claude.sh — do not edit
CAI_HOME=${CAI_HOME}
CAI_VENV_BIN=${VENV_DIR}/bin
CAI_INSTALL_SCRIPT=${SCRIPT_DIR}/install-cai-claude.sh
CAI_INSTALL_ENV=${CAI_HOME}/install.env
EOF
  chmod 600 "${CAI_HOME}/install.env"

  log "  Library:  ${CAI_HOME}/lib/cai-common.sh"
  log "  Launcher: ${INSTALLED_LAUNCH}"
}

ensure_local_bin_on_path() {
  case ":${PATH}:" in
    *":${LOCAL_BIN}:"*) return 0 ;;
  esac
  if is_interactive && confirm "Add ${LOCAL_BIN} to PATH in this shell session?" "y"; then
    export PATH="${LOCAL_BIN}:${PATH}"
  fi
  if is_interactive && confirm "Add ${LOCAL_BIN} to ~/.zshrc or ~/.bashrc permanently?" "y"; then
    local profile=""
    [ -f "${HOME}/.zshrc" ] && profile="${HOME}/.zshrc"
    [ -z "$profile" ] && [ -f "${HOME}/.bashrc" ] && profile="${HOME}/.bashrc"
    if [ -n "$profile" ] && ! grep -qF "${LOCAL_BIN}" "$profile" 2>/dev/null; then
      printf '\n# Claude Code + CAI Inference launcher\nexport PATH="%s:$PATH"\n' "$LOCAL_BIN" >>"$profile"
      log "  Added PATH to ${profile}"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Step 5 — Configure CAI endpoint
# ---------------------------------------------------------------------------
configure_endpoint() {
  log ""
  log "=== Step 5/6 — Configure Cloudera AI Inference endpoint ==="

  CAI_HOME="$CAI_HOME"
  # shellcheck disable=SC1090
  source "${CAI_HOME}/lib/cai-common.sh"

  cai_load_config

  if [ -z "${CAI_API_BASE:-}" ] || [ -z "${CAI_CDP_TOKEN:-}" ]; then
    cai_prompt_user_config
  else
    CAI_API_BASE="$(cai_normalize_url "$CAI_API_BASE" "$CAI_CDP_TOKEN")"
    [ -n "${CAI_MODEL_NAME:-}" ] || CAI_MODEL_NAME="$(cai_fetch_model_name "$CAI_API_BASE" "$CAI_CDP_TOKEN")"
    cai_save_config
  fi

  log "  Validating connection ..."
  cai_validate_connection "$CAI_API_BASE" "$CAI_CDP_TOKEN"
  log "  Connection OK."
  log "  Model: ${CAI_MODEL_NAME}"
  log "  Config: ${CONFIG_FILE}"
}

# ---------------------------------------------------------------------------
# Step 6 — Smoke test proxy + summary
# ---------------------------------------------------------------------------
smoke_test_and_finish() {
  log ""
  log "=== Step 6/6 — Smoke test local LiteLLM proxy ==="

  CAI_HOME="$CAI_HOME"
  # shellcheck disable=SC1090
  source "${CAI_HOME}/lib/cai-common.sh"
  cai_load_config

  cai_start_litellm_proxy

  if curl -sf --connect-timeout 5 --max-time 10 \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    "${PROXY_URL}/health/liveliness" >/dev/null 2>&1; then
    log "  LiteLLM proxy healthy at ${PROXY_URL}"
  else
    log "  WARN: Proxy health check inconclusive — see ${LITELLM_LOG}"
  fi

  log ""
  log "============================================"
  log "  Install complete!"
  log ""
  log "  Launch Claude Code anytime:"
  log "    claude-cai"
  log ""
  log "  One-shot prompt:"
  log "    claude-cai -p \"explain this repo\""
  log ""
  log "  Reconfigure URL/token:"
  log "    claude-cai --reconfigure"
  log ""
  log "  Stop background proxy:"
  log "    claude-cai --stop-proxy"
  log ""
  log "  Files:"
  log "    ${CAI_HOME}/"
  log "============================================"

  if is_interactive && confirm "Launch Claude Code now?" "y"; then
    exec "$INSTALLED_LAUNCH"
  fi
}

main() {
  case "${1:-}" in
    -h|--help)
      sed -n '2,16p' "$0" >&2
      exit 0
      ;;
  esac

  check_requirements
  setup_venv
  ensure_claude_code
  install_launcher
  ensure_local_bin_on_path
  configure_endpoint
  smoke_test_and_finish
}

main "$@"
