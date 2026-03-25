#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# GPUShare — Curl Installer (one-liner bootstrap)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Slaymish/GPUShare/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --quick
#   curl -fsSL ... | bash -s -- --quick --skip-ollama
# ──────────────────────────────────────────────────────────────────────────────

REPO="Slaymish/GPUShare"
BRANCH="main"
INSTALL_DIR="$HOME/GPUShare"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}[i]${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}[+]${RESET} %s\n" "$*"; }
fail()  { printf "${RED}[x]${RESET} %s\n" "$*"; exit 1; }

# ── Check git ─────────────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
  fail "Git is required. Install it first."
fi

# ── Clone or update ───────────────────────────────────────────────────────────

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating existing GPUShare installation..."
  git -C "$INSTALL_DIR" pull --ff-only
  ok "Updated to latest version"
else
  info "Cloning GPUShare to $INSTALL_DIR..."
  git clone --depth 1 "https://github.com/$REPO.git" "$INSTALL_DIR"
  ok "Cloned successfully"
fi

cd "$INSTALL_DIR"

# ── Make setup.sh executable ─────────────────────────────────────────────────

chmod +x setup.sh

# ── Run setup.sh with forwarded arguments ─────────────────────────────────────

info "Launching GPUShare installer..."
echo ""
exec ./setup.sh "$@"
