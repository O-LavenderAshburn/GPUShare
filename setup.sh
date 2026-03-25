#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# GPUShare — One-Click Installer for macOS / Linux
#
# Usage:
#   ./setup.sh              # interactive (guided wizard)
#   ./setup.sh --quick      # non-interactive, all defaults
#   ./setup.sh --quick --skip-ollama   # skip Ollama install/model pull
# ──────────────────────────────────────────────────────────────────────────────

VERSION="2.0.0"
QUICK_MODE=false
SKIP_OLLAMA=false
SKIP_TUNNEL=false
DRY_RUN=false

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --quick)       QUICK_MODE=true ;;
    --skip-ollama) SKIP_OLLAMA=true ;;
    --skip-tunnel) SKIP_TUNNEL=true ;;
    --dry-run)     DRY_RUN=true ;;
    --help|-h)
      echo "Usage: ./setup.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --quick         Non-interactive, use all defaults"
      echo "  --skip-ollama   Don't install or pull Ollama models"
      echo "  --skip-tunnel   Don't start Cloudflare tunnel"
      echo "  --dry-run       Show what would be done without executing"
      echo "  --help          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (use --help)"
      exit 1
      ;;
  esac
done

# ── OS Detection ──────────────────────────────────────────────────────────────

detect_os() {
  case "$(uname -s)" in
    Darwin*)  OS="macos";  DISTRO="macos" ;;
    Linux*)
      OS="linux"
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="${ID:-linux}"
      else
        DISTRO="linux"
      fi
      ;;
    *)        OS="unknown"; DISTRO="unknown" ;;
  esac
}

detect_arch() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64)   ARCH="amd64" ;;
    arm64|aarch64)  ARCH="arm64" ;;
  esac
}

# ── GPU Detection ─────────────────────────────────────────────────────────────

detect_gpu() {
  GPU_NAME="unknown"
  GPU_VRAM_MB=0
  GPU_TDP_WATTS=0

  if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)
    GPU_TDP_WATTS=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)
    GPU_VENDOR="nvidia"
  elif [ "$OS" = "macos" ]; then
    GPU_NAME=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | sed 's/.*: //' || echo "Apple Silicon")
    GPU_VRAM_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1048576)}' || echo 0)
    GPU_VENDOR="apple"
  elif lspci 2>/dev/null | grep -qi "vga\|3d\|display"; then
    GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | sed 's/.*: //' || echo "unknown")
    GPU_VENDOR="other"
  fi
}

recommend_model() {
  local vram_gb=$((GPU_VRAM_MB / 1024))
  if [ "$vram_gb" -ge 24 ]; then
    RECOMMENDED_MODEL="qwen2.5:32b"
    RECOMMENDED_NOTE="24GB+ VRAM detected — you can run larger models"
  elif [ "$vram_gb" -ge 16 ]; then
    RECOMMENDED_MODEL="qwen2.5:14b"
    RECOMMENDED_NOTE="16GB VRAM detected — good for 14B models"
  elif [ "$vram_gb" -ge 8 ]; then
    RECOMMENDED_MODEL="llama3.1:8b"
    RECOMMENDED_NOTE="8GB VRAM detected — 8B models recommended"
  elif [ "$vram_gb" -ge 4 ]; then
    RECOMMENDED_MODEL="qwen2.5:4b"
    RECOMMENDED_NOTE="4GB VRAM detected — use smaller models"
  else
    RECOMMENDED_MODEL="qwen2.5:1.5b"
    RECOMMENDED_NOTE="Low/no GPU detected — tiny model only (CPU inference)"
  fi
}

# ── Colors & Helpers ──────────────────────────────────────────────────────────

setup_colors() {
  if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    BOLD="$(tput bold)"
    BLUE="$(tput setaf 4)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    RED="$(tput setaf 1)"
    CYAN="$(tput setaf 6)"
    DIM="$(tput dim)"
    RESET="$(tput sgr0)"
  else
    BOLD="" BLUE="" GREEN="" YELLOW="" RED="" CYAN="" DIM="" RESET=""
  fi
}

info()   { printf "${BLUE}ℹ${RESET}  %s\n" "$*"; }
success(){ printf "${GREEN}✔${RESET}  %s\n" "$*"; }
warn()   { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }
fail()   { printf "${RED}✘${RESET}  %s\n" "$*"; exit 1; }
header() { printf "\n${BOLD}${CYAN}▸ %s${RESET}\n" "$*"; }

spinner() {
  local pid=$1 msg=$2
  local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${RESET} %s" "${chars:i%10:1}" "$msg"
    sleep 0.1
    i=$((i+1))
  done
  printf "\r"
}

run_with_spinner() {
  local msg="$1"; shift
  if $QUICK_MODE; then
    "$@" >/dev/null 2>&1 &
    spinner $! "$msg"
    wait $!
  else
    "$@"
  fi
}

prompt() {
  local prompt="$1" default="${2:-}" varname="$3"
  if $QUICK_MODE; then
    eval "$varname='$default'"
    return
  fi
  if [ -n "$default" ]; then
    read -rp "  $prompt [$default]: " value
  else
    read -rp "  $prompt: " value
  fi
  eval "$varname=\${value:-$default}"
}

confirm() {
  local prompt="$1" default="${2:-n}"
  if $QUICK_MODE; then
    [ "$default" = "y" ]
    return $?
  fi
  if [ "$default" = "y" ]; then
    read -rp "  $prompt [Y/n]: " answer
    [[ "${answer,,}" != "n" ]]
  else
    read -rp "  $prompt (y/N): " answer
    [[ "${answer,,}" == "y" ]]
  fi
}

progress_bar() {
  local msg="$1" duration="$2"
  local width=40
  printf "  %-40s [" "$msg"
  for i in $(seq 1 "$width"); do
    printf "█"
    sleep "$(awk "BEGIN{print $duration/$width}")"
  done
  printf "] Done\n"
}

# ── Pre-flight Checks ────────────────────────────────────────────────────────

check_docker() {
  if ! command -v docker &>/dev/null; then
    warn "Docker is not installed."
    if [ "$OS" = "macos" ]; then
      info "Download Docker Desktop: https://docs.docker.com/desktop/mac/install/"
      info "Or run:  brew install --cask docker"
    elif [ "$OS" = "linux" ]; then
      info "Run:  curl -fsSL https://get.docker.com | sh"
      info "Then: sudo usermod -aG docker \$USER && newgrp docker"
    fi
    fail "Install Docker and re-run this script."
  fi

  if ! docker compose version &>/dev/null 2>&1; then
    fail "Docker Compose v2 is required. Update Docker Desktop."
  fi

  if ! docker info &>/dev/null 2>&1; then
    fail "Docker daemon is not running. Start Docker and try again."
  fi

  success "Docker $(docker --version | awk '{print $3}' | tr -d ',') is ready"
}

check_prerequisites() {
  header "Checking prerequisites"

  check_docker

  # Check git
  if ! command -v git &>/dev/null; then
    fail "Git is required. Install it and re-run."
  fi
  success "Git $(git --version | awk '{print $3}') is ready"

  # Check port availability
  if lsof -Pi :8000 -sTCP:LISTEN -t &>/dev/null 2>&1; then
    warn "Port 8000 is already in use."
    info "The existing process will be stopped if you continue."
    if ! $QUICK_MODE && ! confirm "Continue anyway?"; then
      fail "Aborted by user."
    fi
  fi
}

# ── Ollama Setup ──────────────────────────────────────────────────────────────

setup_ollama() {
  if $SKIP_OLLAMA; then
    info "Skipping Ollama (--skip-ollama)"
    return
  fi

  header "Setting up Ollama"

  if ! command -v ollama &>/dev/null; then
    warn "Ollama is not installed. Installing..."

    if [ "$OS" = "macos" ]; then
      if command -v brew &>/dev/null; then
        run_with_spinner "Installing Ollama via Homebrew..." brew install --cask ollama
      else
        info "Downloading Ollama for macOS..."
        curl -fsSL https://ollama.com/download/Ollama-darwin.zip -o /tmp/ollama.zip
        unzip -q /tmp/ollama.zip -d /tmp/ollama-app
        cp -r /tmp/ollama-app/Ollama.app /Applications/
        rm -rf /tmp/ollama.zip /tmp/ollama-app
        success "Ollama installed to /Applications/Ollama.app"
        info "Launch Ollama from Applications, then continue."
        open /Applications/Ollama.app 2>/dev/null || true
        sleep 5
      fi
    elif [ "$OS" = "linux" ]; then
      run_with_spinner "Installing Ollama..." curl -fsSL https://ollama.com/install.sh | sh
    fi
  fi

  success "Ollama $(ollama --version 2>/dev/null || echo 'installed')"

  # Ensure Ollama is running
  if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    info "Starting Ollama..."
    if [ "$OS" = "macos" ]; then
      open /Applications/Ollama.app 2>/dev/null || ollama serve &>/dev/null &
    else
      if systemctl --user is-active ollama &>/dev/null 2>&1; then
        systemctl --user restart ollama
      else
        ollama serve &>/dev/null &
      fi
    fi
    # Wait for Ollama to start
    for i in $(seq 1 30); do
      if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi

  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    success "Ollama is running on port 11434"
  else
    fail "Cannot reach Ollama. Start it manually and re-run."
  fi

  # Pull model
  recommend_model
  header "Pulling AI model"
  info "$RECOMMENDED_NOTE"
  prompt "Model to pull" "$RECOMMENDED_MODEL" MODEL

  info "Downloading $MODEL (this may take several minutes)..."
  run_with_spinner "Pulling $MODEL..." ollama pull "$MODEL"
  success "Model $MODEL is ready"
}

# ── Database Configuration ───────────────────────────────────────────────────

configure_database() {
  header "Database configuration"

  if $QUICK_MODE; then
    DATABASE_URL="postgresql+asyncpg://user:pass@localhost:5432/gpushare"
    warn "Using placeholder DATABASE_URL — update .env before first run"
    return
  fi

  cat << 'DBHELP'
  You need a PostgreSQL database. Free options:
  ─────────────────────────────────────────────
  • Supabase (supabase.com) — create project → Settings → Database → URI
  • Neon (neon.tech)        — create project → copy connection string

  The URL must start with: postgresql+asyncpg://
DBHELP

  prompt "DATABASE_URL" "" DATABASE_URL

  if [[ -z "$DATABASE_URL" ]]; then
    DATABASE_URL="postgresql+asyncpg://user:pass@localhost:5432/gpushare"
    warn "Empty URL — using placeholder. Update .env before starting."
  fi

  success "Database URL configured"
}

# ── Core Configuration ───────────────────────────────────────────────────────

configure_core() {
  header "Node configuration"

  JWT_SECRET="$(openssl rand -hex 32)"

  prompt "Node name" "My GPU Share" NODE_NAME
  prompt "Admin email" "admin@localhost" ADMIN_EMAIL
  prompt "Electricity rate per kWh" "0.346" ELECTRICITY_RATE_KWH
  prompt "Currency (ISO code)" "NZD" CURRENCY

  # GPU wattage (auto-fill from GPU detection)
  local default_inf_watts=150
  local default_rnd_watts=300
  local default_sys_watts=80

  if [ "$GPU_VENDOR" = "nvidia" ] && [ "${GPU_TDP_WATTS%.*}" -gt 0 ] 2>/dev/null; then
    # Use actual TDP from nvidia-smi — much more accurate than VRAM heuristics
    local tdp_int=${GPU_TDP_WATTS%.*}
    default_inf_watts=$(( tdp_int * 80 / 100 ))   # sustained inference ~80% TDP
    default_rnd_watts=$(( tdp_int * 95 / 100 ))   # render pushes closer to TDP
    info "Using nvidia-smi TDP: ${GPU_TDP_WATTS}W (inference=${default_inf_watts}W, render=${default_rnd_watts}W)"
  elif [ "$GPU_VENDOR" = "nvidia" ] && [ "$GPU_VRAM_MB" -gt 0 ]; then
    # Fallback: estimate wattage from VRAM
    local vram_gb=$((GPU_VRAM_MB / 1024))
    if [ "$vram_gb" -ge 24 ]; then
      default_inf_watts=280; default_rnd_watts=380
    elif [ "$vram_gb" -ge 16 ]; then
      default_inf_watts=200; default_rnd_watts=300
    elif [ "$vram_gb" -ge 8 ]; then
      default_inf_watts=150; default_rnd_watts=200
    fi
  elif [ "$GPU_VENDOR" = "apple" ]; then
    # Apple Silicon TDP estimates
    local chip_name="${GPU_NAME,,}"
    if echo "$chip_name" | grep -q "m4"; then
      default_inf_watts=18; default_rnd_watts=20; default_sys_watts=25
    elif echo "$chip_name" | grep -q "m3"; then
      default_inf_watts=16; default_rnd_watts=18; default_sys_watts=25
    elif echo "$chip_name" | grep -q "m2"; then
      default_inf_watts=15; default_rnd_watts=17; default_sys_watts=25
    elif echo "$chip_name" | grep -q "m1"; then
      default_inf_watts=12; default_rnd_watts=14; default_sys_watts=25
    else
      default_inf_watts=15; default_rnd_watts=17; default_sys_watts=25
    fi
  fi

  prompt "GPU inference wattage" "$default_inf_watts" GPU_INFERENCE_WATTS
  prompt "GPU render wattage" "$default_rnd_watts" GPU_RENDER_WATTS
  prompt "System idle wattage" "$default_sys_watts" SYSTEM_WATTS

  success "Configuration complete"
}

# ── Optional Services ─────────────────────────────────────────────────────────

configure_services() {
  header "Optional services"

  SERVICES_ENABLED="inference"
  BILLING_ENABLED="false"
  STRIPE_SECRET_KEY=""
  STRIPE_WEBHOOK_SECRET=""
  R2_ACCOUNT_ID=""
  R2_ACCESS_KEY_ID=""
  R2_SECRET_ACCESS_KEY=""
  RESEND_API_KEY=""
  OPENROUTER_API_KEY=""

  # Stripe billing
  if confirm "Enable Stripe billing (card payments)?" "n"; then
    BILLING_ENABLED="true"
    prompt "STRIPE_SECRET_KEY" "" STRIPE_SECRET_KEY
    prompt "STRIPE_WEBHOOK_SECRET" "" STRIPE_WEBHOOK_SECRET
    success "Stripe billing enabled"
  fi

  # OpenRouter (cloud AI models)
  if confirm "Enable OpenRouter (cloud AI models like GPT-4o, Claude)?" "n"; then
    prompt "OPENROUTER_API_KEY" "" OPENROUTER_API_KEY
    success "OpenRouter enabled"
  fi

  # 3D rendering
  if confirm "Enable 3D rendering (Blender)?" "n"; then
    SERVICES_ENABLED="inference,render"
    info "Render requires Cloudflare R2 for file storage"
    prompt "CLOUDFLARE_R2_ACCOUNT_ID" "" R2_ACCOUNT_ID
    prompt "CLOUDFLARE_R2_ACCESS_KEY_ID" "" R2_ACCESS_KEY_ID
    prompt "CLOUDFLARE_R2_SECRET_ACCESS_KEY" "" R2_SECRET_ACCESS_KEY
    success "3D rendering enabled"
  fi

  # Email
  if confirm "Enable email notifications (Resend)?" "n"; then
    prompt "RESEND_API_KEY" "" RESEND_API_KEY
    success "Email notifications enabled"
  fi

  # Invite-only
  prompt "Invite-only signups? (true/false)" "true" INVITE_ONLY
}

# ── Write .env ────────────────────────────────────────────────────────────────

write_env() {
  header "Writing configuration"

  if [ -f .env ]; then
    if ! $QUICK_MODE && ! confirm "Overwrite existing .env?" "n"; then
      fail "Aborted — rename or remove .env and re-run."
    fi
    cp .env .env.bak
    info "Backed up existing .env to .env.bak"
  fi

  cat > .env << EOF
# ── GPUShare Configuration ──────────────────────────────────────────────────
# Generated by setup.sh v${VERSION} on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ────────────────────────────────────────────────────────────────────────────

# Required
DATABASE_URL=${DATABASE_URL}
JWT_SECRET=${JWT_SECRET}
ADMIN_EMAIL=${ADMIN_EMAIL}

# Node
NODE_NAME=${NODE_NAME}
ELECTRICITY_RATE_KWH=${ELECTRICITY_RATE_KWH}
CURRENCY=${CURRENCY}
GPU_INFERENCE_WATTS=${GPU_INFERENCE_WATTS}
GPU_RENDER_WATTS=${GPU_RENDER_WATTS}
SYSTEM_WATTS=${SYSTEM_WATTS}

# Services
SERVICES_ENABLED=${SERVICES_ENABLED}
MODELS=${MODEL:-qwen2.5:14b}
OLLAMA_HOST=http://host.docker.internal:11434
OLLAMA_KEEP_ALIVE=15m
BLENDER_PATH=/usr/bin/blender
BLENDER_MAX_CONCURRENT_JOBS=1

# Billing
BILLING_ENABLED=${BILLING_ENABLED}
SOFT_LIMIT_WARN=-5.00
HARD_LIMIT_DEFAULT=-20.00
INVOICE_DAY=1

# Stripe
STRIPE_SECRET_KEY=${STRIPE_SECRET_KEY}
STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}

# OpenRouter
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
OPENROUTER_MODELS=

# Cloudflare R2 (render file storage)
CLOUDFLARE_R2_ACCOUNT_ID=${R2_ACCOUNT_ID}
CLOUDFLARE_R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}
CLOUDFLARE_R2_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY}
CLOUDFLARE_R2_BUCKET=gpu-node-files

# Email (Resend)
RESEND_API_KEY=${RESEND_API_KEY}

# Access control
INVITE_ONLY=${INVITE_ONLY}
REQUIRE_APPROVAL=true
INITIAL_ADMIN_BOOTSTRAP_TOKEN=$(openssl rand -hex 16)

# CORS
CORS_ORIGINS=
EOF

  success ".env written"
}

# ── Build & Start ─────────────────────────────────────────────────────────────

build_and_start() {
  header "Building and starting services"

  info "Building Docker images (first time takes 2-5 minutes)..."
  if $DRY_RUN; then
    info "[dry-run] Would run: docker compose build"
  else
    run_with_spinner "Building Docker images..." docker compose build
    success "Images built"
  fi

  info "Running database migrations..."
  if $DRY_RUN; then
    info "[dry-run] Would run: docker compose run --rm fastapi alembic upgrade head"
  else
    run_with_spinner "Migrating database..." docker compose run --rm fastapi alembic upgrade head
    success "Database migrated"
  fi

  info "Starting services..."
  if $DRY_RUN; then
    info "[dry-run] Would run: docker compose up -d"
  else
    docker compose up -d
    sleep 3

    # Health check
    local healthy=false
    for i in $(seq 1 30); do
      if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        healthy=true
        break
      fi
      sleep 1
    done

    if $healthy; then
      success "GPUShare API is running on http://localhost:8000"
    else
      warn "Server may still be starting. Check: docker compose logs fastapi"
    fi
  fi
}

# ── Cloudflare Tunnel ─────────────────────────────────────────────────────────

setup_tunnel() {
  if $SKIP_TUNNEL || $DRY_RUN; then
    return
  fi

  header "Public access (Cloudflare Tunnel)"

  if ! $QUICK_MODE && ! confirm "Start a public tunnel? (free, no account needed)" "n"; then
    info "Skipping tunnel. Start later with:"
    info "  cloudflared tunnel --url http://localhost:8000"
    TUNNEL_URL=""
    return
  fi

  if ! command -v cloudflared &>/dev/null; then
    info "Installing cloudflared..."
    if [ "$OS" = "macos" ] && command -v brew &>/dev/null; then
      run_with_spinner "Installing cloudflared..." brew install cloudflared
    elif [ "$OS" = "linux" ]; then
      curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list
      sudo apt-get update -qq && sudo apt-get install -y -qq cloudflared
    fi
  fi

  if command -v cloudflared &>/dev/null; then
    info "Starting tunnel (takes ~10 seconds)..."
    cloudflared tunnel --url http://localhost:8000 &> /tmp/gpushare-tunnel.log &

    TUNNEL_URL=""
    for i in $(seq 1 20); do
      if url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/gpushare-tunnel.log 2>/dev/null | head -1); then
        if [ -n "$url" ]; then
          TUNNEL_URL="$url"
          break
        fi
      fi
      sleep 1
    done

    if [ -n "$TUNNEL_URL" ]; then
      success "Public URL: $TUNNEL_URL"
    else
      warn "Tunnel started but URL not yet available. Check /tmp/gpushare-tunnel.log"
    fi
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────

show_summary() {
  local services_display="${SERVICES_ENABLED//,/ }"
  local billing_display="disabled"
  [ "$BILLING_ENABLED" = "true" ] && billing_display="enabled"
  local public_url="${TUNNEL_URL:-http://localhost:8000}"

  echo ""
  printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════${RESET}\n"
  printf "${BOLD}${GREEN}  GPUShare is running!${RESET}\n"
  printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════${RESET}\n"
  echo ""
  printf "  ${BOLD}Local URL:${RESET}    http://localhost:8000\n"
  printf "  ${BOLD}API docs:${RESET}     http://localhost:8000/docs\n"
  if [ -n "$TUNNEL_URL" ]; then
    printf "  ${BOLD}Public URL:${RESET}   %s\n" "$TUNNEL_URL"
    printf "  ${DIM}(URL changes on restart — use a persistent tunnel for production)${RESET}\n"
  fi
  printf "  ${BOLD}Services:${RESET}     %s\n" "$services_display"
  printf "  ${BOLD}Model:${RESET}        %s\n" "${MODEL:-$RECOMMENDED_MODEL}"
  printf "  ${BOLD}Billing:${RESET}      %s\n" "$billing_display"
  printf "  ${BOLD}OS:${RESET}           %s (%s)\n" "$OS" "$ARCH"
  printf "  ${BOLD}GPU:${RESET}          %s\n" "$GPU_NAME"
  echo ""
  printf "  ${BOLD}Next steps:${RESET}\n"
  echo ""
  printf "  1. ${BOLD}Deploy the frontend to Vercel:${RESET}\n"
  printf "     → Import this repo at https://vercel.com/new\n"
  printf "     → Set root directory to: packages/frontend\n"
  printf "     → Add env variable: VITE_API_URL = %s\n" "$public_url"
  echo ""
  printf "  2. ${BOLD}Create your admin account:${RESET}\n"
  printf "     → Open the frontend and sign up\n"
  printf "     → First user automatically becomes admin\n"
  echo ""
  printf "  3. ${BOLD}Useful commands:${RESET}\n"
  printf "     docker compose logs -f           # follow all logs\n"
  printf "     docker compose restart           # restart services\n"
  printf "     docker compose down              # stop everything\n"
  printf "     docker compose up -d             # start everything\n"
  echo ""
  printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════${RESET}\n"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  setup_colors
  detect_os
  detect_arch
  detect_gpu

  if ! $QUICK_MODE; then
    cat << 'BANNER'

   ██████  ██████  ██    ██     ███    ██  ██████  ██████  ███████
  ██       ██   ██ ██    ██     ████   ██ ██    ██ ██   ██ ██
  ██   ███ ██████  ██    ██     ██ ██  ██ ██    ██ ██   ██ █████
  ██    ██ ██      ██    ██     ██  ██ ██ ██    ██ ██   ██ ██
   ██████  ██       ██████      ██   ████  ██████  ██████  ███████

BANNER
    printf "  ${BOLD}One-Click Installer${RESET} v%s\n" "$VERSION"
    printf "  Detected: %s %s | GPU: %s\n\n" "$OS" "$ARCH" "$GPU_NAME"
  fi

  check_prerequisites
  setup_ollama
  configure_database
  configure_core
  configure_services
  write_env
  build_and_start
  setup_tunnel
  show_summary
}

main
