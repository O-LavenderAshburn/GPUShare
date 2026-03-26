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
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}[i]${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}[+]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
fail()  { printf "${RED}[x]${RESET} %s\n" "$*"; exit 1; }

# ── Check git ─────────────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
  fail "Git is required. Install it first."
fi

# ── Clone or update ───────────────────────────────────────────────────────────

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Existing GPUShare installation found at $INSTALL_DIR"
  CURRENT_BRANCH=$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  CURRENT_SHA=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # Check if there are uncommitted changes
  if ! git -C "$INSTALL_DIR" diff --quiet 2>/dev/null; then
    warn "You have uncommitted changes in your GPUShare installation."
    info "Stashing changes before updating..."
    git -C "$INSTALL_DIR" stash push -m "gpushare-installer-autostash-$(date +%s)" || true
  fi

  info "Pulling latest changes (branch: $CURRENT_BRANCH, was at $CURRENT_SHA)..."
  git -C "$INSTALL_DIR" fetch --depth=1 origin "$BRANCH" 2>/dev/null || git -C "$INSTALL_DIR" fetch --depth=1 origin 2>/dev/null || true
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" 2>/dev/null || git -C "$INSTALL_DIR" pull --ff-only || true
  ok "Updated to latest version"
else
  info "Cloning GPUShare to $INSTALL_DIR..."
  git clone --depth 1 "https://github.com/$REPO.git" "$INSTALL_DIR"
  ok "Cloned successfully"
fi

cd "$INSTALL_DIR"

# ── Stop running services if they exist ───────────────────────────────────────

if [ -f docker-compose.yml ] || [ -f compose.yml ]; then
  COMPOSE_FILE=""
  [ -f docker-compose.yml ] && COMPOSE_FILE="docker-compose.yml"
  [ -f compose.yml ] && COMPOSE_FILE="compose.yml"

  if docker compose -f "$COMPOSE_FILE" ps --quiet 2>/dev/null | grep -q .; then
    info "Stopping running GPUShare services before update..."
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    ok "Services stopped"
  fi
fi

# ── Make setup.sh executable ─────────────────────────────────────────────────

chmod +x setup.sh

# ── Run setup.sh with forwarded arguments ─────────────────────────────────────

info "Launching GPUShare installer..."
echo ""
exec ./setup.sh "$@"
