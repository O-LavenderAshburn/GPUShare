#Requires -Version 5.1
<#
.SYNOPSIS
    GPUShare — One-Click Installer for Windows

.DESCRIPTION
    Interactive wizard or one-flag silent install for Windows.
    Detects GPU, installs prerequisites, configures the node, and starts services.

.PARAMETER Quick
    Non-interactive mode — use all defaults, skip prompts.

.PARAMETER SkipOllama
    Skip Ollama installation and model pull.

.PARAMETER SkipTunnel
    Skip Cloudflare tunnel setup.

.PARAMETER DryRun
    Show what would be done without executing.

.EXAMPLE
    .\setup.ps1              # interactive wizard
    .\setup.ps1 -Quick       # one-click, all defaults
    .\setup.ps1 -Quick -SkipOllama
#>
param(
    [switch]$Quick,
    [switch]$SkipOllama,
    [switch]$SkipTunnel,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Script:VERSION = "2.0.0"

# ─── Helper Functions ─────────────────────────────────────────────────────────

function Write-Info  ([string]$m) { Write-Host "  " -NoNewline; Write-Host "[i] " -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Write-OK    ([string]$m) { Write-Host "  " -NoNewline; Write-Host "[+] " -ForegroundColor Green -NoNewline; Write-Host $m }
function Write-Warn  ([string]$m) { Write-Host "  " -NoNewline; Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Write-Fail  ([string]$m) { Write-Host "  " -NoNewline; Write-Host "[x] " -ForegroundColor Red -NoNewline; Write-Host $m; exit 1 }
function Write-Header([string]$m) { Write-Host ""; Write-Host "  >> $m" -ForegroundColor White -BackgroundColor DarkCyan; Write-Host "" }

function Read-Default([string]$prompt, [string]$default) {
    if ($Quick) { return $default }
    $value = Read-Host "  $prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $default }
    return $value.Trim()
}

function Confirm([string]$prompt, [string]$default = "n") {
    if ($Quick) { return ($default -eq "y") }
    if ($default -eq "y") {
        $answer = Read-Host "  $prompt [Y/n]"
        return ($answer -ne 'n' -and $answer -ne 'N')
    } else {
        $answer = Read-Host "  $prompt (y/N)"
        return ($answer -eq 'y' -or $answer -eq 'Y')
    }
}

# ─── GPU Detection ────────────────────────────────────────────────────────────

function Get-GPUInfo {
    $script:GPUVendor = "unknown"
    $script:GPUName   = "unknown"
    $script:GPUVRAMMB = 0

    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        if ($gpus) {
            $gpu = $gpus | Sort-Object AdapterRAM -Descending | Select-Object -First 1
            $script:GPUName = $gpu.Name
            $script:GPUVRAMMB = [math]::Round($gpu.AdapterRAM / 1MB)

            if ($gpu.Name -match 'NVIDIA') {
                $script:GPUVendor = "nvidia"
            } elseif ($gpu.Name -match 'AMD|Radeon') {
                $script:GPUVendor = "amd"
            } elseif ($gpu.Name -match 'Intel') {
                $script:GPUVendor = "intel"
            }
        }
    } catch { }

    # Fallback for nvidia-smi
    if ($script:GPUVendor -eq "unknown" -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        try {
            $info = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>&1
            if ($info -match '(.+),\s*(\d+)\s*MiB') {
                $script:GPUName = $Matches[1].Trim()
                $script:GPUVRAMMB = [int]$Matches[2]
                $script:GPUVendor = "nvidia"
            }
        } catch { }
    }
}

function Get-RecommendedModel {
    $vram_gb = [math]::Floor($GPUVRAMMB / 1024)
    if ($vram_gb -ge 24)     { return "qwen2.5:32b",  "24GB+ VRAM — you can run larger models" }
    elseif ($vram_gb -ge 16) { return "qwen2.5:14b",  "16GB VRAM — good for 14B models" }
    elseif ($vram_gb -ge 8)  { return "llama3.1:8b",  "8GB VRAM — 8B models recommended" }
    elseif ($vram_gb -ge 4)  { return "qwen2.5:4b",   "4GB VRAM — use smaller models" }
    else                     { return "qwen2.5:1.5b", "Low/no GPU — tiny model only" }
}

# ─── Prerequisites ────────────────────────────────────────────────────────────

function Test-Prerequisites {
    Write-Header "Checking prerequisites"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail "Docker is not installed."
        Write-Info "Download Docker Desktop: https://docker.com/products/docker-desktop"
        Write-Info "Or run: winget install Docker.DockerDesktop"
    }

    try {
        $ver = docker compose version 2>&1
        Write-OK "Docker $(docker --version -replace 'Docker version ','' -replace ',','') ready"
    } catch {
        Write-Fail "Docker Compose v2 required. Update Docker Desktop."
    }

    try { docker info *> $null; Write-OK "Docker daemon is running" }
    catch { Write-Fail "Docker daemon not running. Start Docker Desktop and retry." }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Fail "Git is required. Install: winget install Git.Git"
    }
    Write-OK "Git ready"

    $listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Warn "Port 8000 is in use."
        if (-not $Quick -and -not (Confirm "Continue anyway?")) {
            Write-Fail "Aborted."
        }
    }
}

# ─── Ollama Setup ─────────────────────────────────────────────────────────────

function Setup-Ollama {
    if ($SkipOllama) { Write-Info "Skipping Ollama (-SkipOllama)"; return }

    Write-Header "Setting up Ollama"

    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Warn "Ollama not installed. Installing..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements --silent
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
        } else {
            Write-Info "Downloading Ollama installer..."
            Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile "$env:TEMP\OllamaSetup.exe"
            Write-Info "Running Ollama installer..."
            Start-Process "$env:TEMP\OllamaSetup.exe" -Wait
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
        }
    }

    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Fail "Ollama installation failed. Install manually from https://ollama.com"
    }
    Write-OK "Ollama found"

    # Check Ollama is running
    try {
        Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 | Out-Null
        Write-OK "Ollama is running on port 11434"
    } catch {
        Write-Warn "Ollama not responding."
        Write-Info "Starting Ollama..."
        Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep 5

        try {
            Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 | Out-Null
            Write-OK "Ollama is now running"
        } catch {
            Write-Fail "Cannot reach Ollama. Start it manually and re-run."
        }
    }

    # Pull model
    $recModel, $recNote = Get-RecommendedModel
    Write-Header "Pulling AI model"
    Write-Info $recNote
    $Script:MODEL = Read-Default "Model to pull" $recModel

    Write-Info "Downloading $MODEL (may take several minutes)..."
    if ($DryRun) {
        Write-Info "[dry-run] Would run: ollama pull $MODEL"
    } else {
        ollama pull $MODEL
        if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to pull model '$MODEL'" }
        Write-OK "Model '$MODEL' is ready"
    }
}

# ─── Database ─────────────────────────────────────────────────────────────────

function Configure-Database {
    Write-Header "Database configuration"

    if ($Quick) {
        $Script:DATABASE_URL = "postgresql+asyncpg://user:pass@localhost:5432/gpushare"
        Write-Warn "Using placeholder DATABASE_URL — update .env before first run"
        return
    }

    Write-Info "You need a PostgreSQL database. Free options:"
    Write-Info "  * Supabase (supabase.com) — create project -> Settings -> Database -> URI"
    Write-Info "  * Neon (neon.tech)        — create project -> copy connection string"
    Write-Host "  The URL must start with: postgresql+asyncpg://" -ForegroundColor DarkGray
    Write-Host ""

    $Script:DATABASE_URL = Read-Host "  DATABASE_URL"
    if ([string]::IsNullOrWhiteSpace($DATABASE_URL)) {
        $Script:DATABASE_URL = "postgresql+asyncpg://user:pass@localhost:5432/gpushare"
        Write-Warn "Empty URL — using placeholder. Update .env before starting."
    }
    Write-OK "Database URL configured"
}

# ─── Core Config ──────────────────────────────────────────────────────────────

function Configure-Core {
    Write-Header "Node configuration"

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $Script:JWT_SECRET = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    Write-OK "Generated JWT secret"

    $Script:NODE_NAME            = Read-Default "Node name"                    "My GPU Share"
    $Script:ADMIN_EMAIL          = Read-Default "Admin email"                  "admin@localhost"
    $Script:ELECTRICITY_RATE_KWH = Read-Default "Electricity rate per kWh"     "0.346"
    $Script:CURRENCY             = Read-Default "Currency (ISO code)"          "NZD"

    $defaultInf = 150; $defaultRnd = 300; $defaultSys = 80
    $vram_gb = [math]::Floor($GPUVRAMMB / 1024)
    if ($GPUVendor -eq "nvidia" -and $vram_gb -ge 24) {
        $defaultInf = 350; $defaultRnd = 400
    } elseif ($GPUVendor -eq "nvidia" -and $vram_gb -ge 16) {
        $defaultInf = 250; $defaultRnd = 320
    } elseif ($GPUVendor -eq "nvidia" -and $vram_gb -ge 8) {
        $defaultInf = 150; $defaultRnd = 200
    }

    $Script:GPU_INFERENCE_WATTS = Read-Default "GPU inference wattage"  $defaultInf
    $Script:GPU_RENDER_WATTS    = Read-Default "GPU render wattage"     $defaultRnd
    $Script:SYSTEM_WATTS        = Read-Default "System idle wattage"    $defaultSys

    Write-OK "Core configuration complete"
}

# ─── Optional Services ────────────────────────────────────────────────────────

function Configure-Services {
    Write-Header "Optional services"

    $Script:SERVICES_ENABLED      = "inference"
    $Script:BILLING_ENABLED       = "false"
    $Script:STRIPE_SECRET_KEY     = ""
    $Script:STRIPE_WEBHOOK_SECRET = ""
    $Script:R2_ACCOUNT_ID         = ""
    $Script:R2_ACCESS_KEY_ID      = ""
    $Script:R2_SECRET_ACCESS_KEY  = ""
    $Script:RESEND_API_KEY        = ""
    $Script:OPENROUTER_API_KEY    = ""

    if (Confirm "Enable Stripe billing (card payments)?") {
        $Script:BILLING_ENABLED = "true"
        $Script:STRIPE_SECRET_KEY   = Read-Host "  STRIPE_SECRET_KEY"
        $Script:STRIPE_WEBHOOK_SECRET = Read-Host "  STRIPE_WEBHOOK_SECRET"
        Write-OK "Stripe billing enabled"
    }

    if (Confirm "Enable OpenRouter (cloud AI models like GPT-4o, Claude)?") {
        $Script:OPENROUTER_API_KEY = Read-Host "  OPENROUTER_API_KEY"
        Write-OK "OpenRouter enabled"
    }

    if (Confirm "Enable 3D rendering (Blender)?") {
        $Script:SERVICES_ENABLED = "inference,render"
        Write-Info "Render requires Cloudflare R2 for file storage"
        $Script:R2_ACCOUNT_ID        = Read-Host "  CLOUDFLARE_R2_ACCOUNT_ID"
        $Script:R2_ACCESS_KEY_ID     = Read-Host "  CLOUDFLARE_R2_ACCESS_KEY_ID"
        $Script:R2_SECRET_ACCESS_KEY = Read-Host "  CLOUDFLARE_R2_SECRET_ACCESS_KEY"
        Write-OK "3D rendering enabled"
    }

    if (Confirm "Enable email notifications (Resend)?") {
        $Script:RESEND_API_KEY = Read-Host "  RESEND_API_KEY"
        Write-OK "Email notifications enabled"
    }

    $Script:INVITE_ONLY = Read-Default "Invite-only signups? (true/false)" "true"
}

# ─── Write .env ───────────────────────────────────────────────────────────────

function Write-EnvFile {
    Write-Header "Writing configuration"

    $envPath = Join-Path $PSScriptRoot ".env"

    if (Test-Path $envPath) {
        if (-not $Quick -and -not (Confirm "Overwrite existing .env?")) {
            Write-Fail "Aborted — rename or remove .env and re-run."
        }
        Copy-Item $envPath "$envPath.bak" -Force
        Write-Info "Backed up existing .env to .env.bak"
    }

    $ollamaHost = "http://host.docker.internal:11434"
    $bootstrapToken = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})

    $content = @"
# ── GPUShare Configuration ──────────────────────────────────────────────────
# Generated by setup.ps1 v$($Script:VERSION) on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ────────────────────────────────────────────────────────────────────────────

# Required
DATABASE_URL=$DATABASE_URL
JWT_SECRET=$JWT_SECRET
ADMIN_EMAIL=$ADMIN_EMAIL

# Node
NODE_NAME=$NODE_NAME
ELECTRICITY_RATE_KWH=$ELECTRICITY_RATE_KWH
CURRENCY=$CURRENCY
GPU_INFERENCE_WATTS=$GPU_INFERENCE_WATTS
GPU_RENDER_WATTS=$GPU_RENDER_WATTS
SYSTEM_WATTS=$SYSTEM_WATTS

# Services
SERVICES_ENABLED=$SERVICES_ENABLED
MODELS=$($Script:MODEL)
OLLAMA_HOST=$ollamaHost
OLLAMA_KEEP_ALIVE=15m
BLENDER_PATH=/usr/bin/blender
BLENDER_MAX_CONCURRENT_JOBS=1

# Billing
BILLING_ENABLED=$BILLING_ENABLED
SOFT_LIMIT_WARN=-5.00
HARD_LIMIT_DEFAULT=-20.00
INVOICE_DAY=1

# Stripe
STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET=$STRIPE_WEBHOOK_SECRET

# OpenRouter
OPENROUTER_API_KEY=$OPENROUTER_API_KEY
OPENROUTER_MODELS=

# Cloudflare R2 (render file storage)
CLOUDFLARE_R2_ACCOUNT_ID=$R2_ACCOUNT_ID
CLOUDFLARE_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID
CLOUDFLARE_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
CLOUDFLARE_R2_BUCKET=gpushare-files

# Email (Resend)
RESEND_API_KEY=$RESEND_API_KEY

# Access control
INVITE_ONLY=$INVITE_ONLY
REQUIRE_APPROVAL=true
INITIAL_ADMIN_BOOTSTRAP_TOKEN=$bootstrapToken

# CORS
CORS_ORIGINS=
"@

    Set-Content -Path $envPath -Value $content -Encoding UTF8
    Write-OK ".env written"
}

# ─── Build & Start ────────────────────────────────────────────────────────────

function Build-And-Start {
    Write-Header "Building and starting services"

    Write-Info "Building Docker images (first time: 2-5 minutes)..."
    if ($DryRun) {
        Write-Info "[dry-run] Would run: docker compose build"
    } else {
        docker compose build
        if ($LASTEXITCODE -ne 0) { Write-Fail "Docker build failed" }
        Write-OK "Images built"
    }

    Write-Info "Running database migrations..."
    if ($DryRun) {
        Write-Info "[dry-run] Would run: docker compose run --rm fastapi alembic upgrade head"
    } else {
        docker compose run --rm fastapi alembic upgrade head
        if ($LASTEXITCODE -ne 0) { Write-Fail "Database migration failed" }
        Write-OK "Database migrated"
    }

    Write-Info "Starting services..."
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { Write-Fail "docker compose up failed" }

    Write-Info "Waiting for server to start..."
    $healthy = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 2 | Out-Null
            $healthy = $true
            break
        } catch { Start-Sleep -Seconds 1 }
    }

    if ($healthy) {
        Write-OK "GPUShare API is running on http://localhost:8000"
    } else {
        Write-Warn "Server may still be starting. Check: docker compose logs fastapi"
    }
}

# ─── Cloudflare Tunnel ────────────────────────────────────────────────────────

function Setup-Tunnel {
    if ($SkipTunnel -or $DryRun) { return }

    Write-Header "Public access (Cloudflare Tunnel)"

    if (-not $Quick -and -not (Confirm "Start a public tunnel? (free, no account needed)")) {
        Write-Info "Skipping. Start later with: cloudflared tunnel --url http://localhost:8000"
        $Script:TUNNEL_URL = ""
        return
    }

    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
        Write-Info "Installing cloudflared..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements --silent
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
        }
    }

    if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
        Write-Info "Starting tunnel (takes ~10 seconds)..."
        $tunnelLog = Join-Path $env:TEMP "gpushare-tunnel.log"
        Start-Process cloudflared -ArgumentList "tunnel","--url","http://localhost:8000" `
            -RedirectStandardError $tunnelLog -NoNewWindow

        $Script:TUNNEL_URL = ""
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            if (Test-Path $tunnelLog) {
                $match = Select-String -Path $tunnelLog -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -SimpleMatch | Select-Object -First 1
                if ($match) {
                    $Script:TUNNEL_URL = $match.Line.Trim()
                    break
                }
            }
        }

        if ($TUNNEL_URL) {
            Write-OK "Public URL: $TUNNEL_URL"
        } else {
            Write-Warn "Tunnel started but URL not yet available. Check: $tunnelLog"
        }
    } else {
        Write-Warn "cloudflared not available. Install from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────

function Show-Summary {
    $servicesDisplay = $SERVICES_ENABLED -replace ',', ', '
    $billingDisplay = if ($BILLING_ENABLED -eq "true") { "enabled" } else { "disabled" }
    $publicUrl = if ($TUNNEL_URL) { $TUNNEL_URL } else { "http://localhost:8000" }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  GPUShare is running!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Info "Local URL:     http://localhost:8000"
    Write-Info "API docs:      http://localhost:8000/docs"
    if ($TUNNEL_URL) {
        Write-Info "Public URL:    $TUNNEL_URL"
        Write-Host "               (URL changes on restart — use a persistent tunnel for production)" -ForegroundColor DarkGray
    }
    Write-Info "Services:      $servicesDisplay"
    Write-Info "Model:         $Script:MODEL"
    Write-Info "Billing:       $billingDisplay"
    Write-Info "GPU:           $GPUName ($([math]::Floor($GPUVRAMMB/1024))GB)"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Deploy the frontend to Vercel:" -ForegroundColor White
    Write-Host "     -> Import this repo at https://vercel.com/new" -ForegroundColor DarkGray
    Write-Host "     -> Set root directory to: packages/frontend" -ForegroundColor DarkGray
    Write-Host "     -> Add env variable: VITE_API_URL = $publicUrl" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2. Create your admin account:" -ForegroundColor White
    Write-Host "     -> Open the frontend and sign up" -ForegroundColor DarkGray
    Write-Host "     -> First user automatically becomes admin" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3. Useful commands:" -ForegroundColor White
    Write-Host "     docker compose logs -f           # follow all logs"     -ForegroundColor DarkGray
    Write-Host "     docker compose restart           # restart services"    -ForegroundColor DarkGray
    Write-Host "     docker compose down              # stop everything"    -ForegroundColor DarkGray
    Write-Host "     docker compose up -d             # start everything"   -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

function Main {
    if (-not $Quick) {
        Write-Host ""
        Write-Host "   ██████  ██████  ██    ██     ███    ██  ██████  ██████  ███████" -ForegroundColor Cyan
        Write-Host "  ██       ██   ██ ██    ██     ████   ██ ██    ██ ██   ██ ██" -ForegroundColor Cyan
        Write-Host "  ██   ███ ██████  ██    ██     ██ ██  ██ ██    ██ ██   ██ █████" -ForegroundColor Cyan
        Write-Host "  ██    ██ ██      ██    ██     ██  ██ ██ ██    ██ ██   ██ ██" -ForegroundColor Cyan
        Write-Host "   ██████  ██       ██████      ██   ████  ██████  ██████  ███████" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  One-Click Installer v$VERSION" -ForegroundColor White
    }

    Get-GPUInfo
    $recModel, $recNote = Get-RecommendedModel
    if (-not $Quick) {
        Write-Host "  Detected: Windows $($env:PROCESSOR_ARCHITECTURE) | GPU: $GPUName" -ForegroundColor DarkGray
        Write-Host ""
    }

    Test-Prerequisites
    Setup-Ollama
    Configure-Database
    Configure-Core
    Configure-Services
    Write-EnvFile
    Build-And-Start
    Setup-Tunnel
    Show-Summary
}

Main
