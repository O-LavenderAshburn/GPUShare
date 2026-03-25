# Changelog

All notable changes to GPUShare are documented here.

---

## [Unreleased]

### Features
- **One-click installers for Windows, macOS, and Linux** — completely rewritten `setup.sh` (macOS/Linux) and `setup.ps1` (Windows) with guided wizard and fully non-interactive mode. New `setup.bat` double-click launcher for Windows and `install.sh` curl one-liner (`curl -fsSL ... | bash`). Key additions:
  - **`--quick` / `-Quick` flag** — non-interactive install with sensible defaults, zero prompts
  - **GPU auto-detection** — auto-detects NVIDIA/AMD/Intel/Apple Silicon, VRAM, and recommends the right model size (4B for 4GB VRAM, 8B for 8GB, 14B for 16GB, 32B for 24GB+)
  - **Smart wattage defaults** — GPU wattage estimates scale with detected VRAM instead of requiring manual input
  - **Auto-installs dependencies** — Ollama via winget/Homebrew/official script; cloudflared via winget/Homebrew/apt
  - **Health checks** — verifies Docker, Git, and port availability before proceeding; confirms server is reachable after startup
  - **`--dry-run`** — preview what would happen without executing
  - **`.env.bak` backup** — existing config is backed up before overwrite
  - **OpenRouter** integrated into setup wizard as optional service
  - **Bootstrap token auto-generated** — no more manual `INITIAL_ADMIN_BOOTSTRAP_TOKEN` setup
- **GPU auto-detection** — automatic detection of GPU model, TDP (power limit), and VRAM at startup, eliminating manual wattage configuration. NVIDIA GPUs use `nvidia-smi power.limit` for accurate TDP; Apple Silicon and AMD GPUs use chip-family estimates. Both setup scripts (`setup.sh`, `setup.ps1`) and the Python backend config now auto-fill wattage defaults. Override anytime via `.env` variables.
- **OpenAI-compatible tool/function calling** — full passthrough of `tools`, `tool_choice`, `tool_calls`, and `tool_call_id` for both Ollama and OpenRouter backends, enabling structured JSON tool execution in clients like OpenCode

### Infrastructure & Deployment
- Added Cloudflared ingress config to fix 503 errors for all requests
- Added FastAPI healthcheck and made Cloudflared wait for healthy origin before routing traffic
- Refactored Docker Compose to support host Ollama with optional GPU override
- Added MIT License

### Integrations
- Added OpenCode integration with auto-routing model support

### Bug Fixes
- Fixed price breakdown pie chart showing incorrect local vs cloud inference costs. Cloud inference was being calculated from only the first 50 usage logs instead of the full backend total, misattributing costs when users had more than 50 entries. Backend now tracks `cloud_inference_usage` as a separate ledger type and returns `total_cloud_inference_cost_nzd` in the balance response.
- Fixed donut chart incorrectly showing render costs by deriving them from `totalUsed - inferenceCost` (which included non-usage negative ledger entries). Now uses per-type ledger sums queried from the backend, matching the admin dashboard approach.
- Fixed CORS policy errors from `gpu-share.vercel.app`
- Fixed models outputting raw XML `<tool_call>` tags instead of using native JSON function calling

---

## Core Features

### AI Model Support
- **OpenRouter integration** — access to cloud AI models with optional billing
- **Ollama (local models)** — local model loading with indicator pill, message queue, and friendly offline error messages
- **OpenClaw integration** — custom provider config with lobster logo
- **Multi-step model picker wizard** — live backend recommendations with fallback to static data, pricing display weighted 3:1 input/output tokens for realistic cost estimates
- **Vision/multimodal support** — file attachment support for images and text files; models tagged with `vision_support` flag to filter attachments by capability

### Chat Interface
- Markdown rendering for assistant messages with syntax highlighting
- Collapsible desktop sidebar with localStorage persistence
- Improved mobile chat header with title display and fixed input positioning
- Replaced mobile bottom tab bar with cleaner sidebar navigation
- Mobile sidebar replaced with dropdown menu in header
- Friendly error messages for OpenRouter API failures (status-specific guidance)
- Friendly error shown when server is offline

### Themes & UI
- Theme switcher with default/light/dark palettes, persisted to backend
- Radix UI component library added
- PWA support with mobile-optimized UI and haptic feedback
- Fixed horizontal overflow and improved mobile layout responsiveness
- Disabled mobile zoom

### Authentication & Users
- Bootstrap token required for initial admin signup
- Hardened signup invite enforcement
- Guest/demo mode with limited access to free cloud models only
- Profile editing and password reset functionality
- Password reset token and expiry fields added via Alembic migration
- Proper Pydantic schemas for profile update and password reset endpoints

### Billing & Payments
- Stripe integration for payment method management (modal dialog UI)
- Postpaid billing support with debt tracking and negative balance handling
- Postpaid billing info section with invoice schedule
- Billing gated behind both billing and Stripe flags being enabled
- Total balance display and billing fixes

### Invite & Access Control
- Invite system with API key generation
- OpenAI-compatible endpoints

### Admin & Server Management
- `gpushare-admin` skill for server management through OpenClaw
- Admin endpoint updates
- Rate limiting on server

### Monitoring & Integrations
- Server status monitoring and integration health dashboard
- Tapo P110 smart plug integration for real-time energy monitoring

### Developer Experience
- `pnpm` workspace configuration with comprehensive script commands
- npm scripts for syncing Alembic migrations from Docker to local filesystem
- Dynamic CSP generation based on `API_URL` environment variable
- Content Security Policy for Stripe integration
- Rewritten setup scripts (`setup.sh`, `setup.ps1`) as full one-click installers with GPU auto-detection, smart defaults, progress indicators, and `--quick` mode; added `setup.bat` (Windows double-click launcher) and `install.sh` (curl one-liner bootstrap)
- Comprehensive `.env.example` with inline comments
- Loading cards and skeleton states
- Stripe conditionally loaded only when publishable key is present
- localStorage image data stripped with quota-exceeded fallback

---

## Refactoring & Maintenance
- Simplified Alembic `env.py` to use `DATABASE_URL` directly with initial migration
- Replaced PEP 604 union syntax with explicit `Optional`/`List` type hints for broader Python compatibility
- Added `future` annotations import across Python modules
- Reformatted `ModelPickerModal`, `api.ts`, and `account.tsx` for consistent code style
- Removed unused imports and simplified type casting
- Comprehensive `.gitignore` entries for `node_modules` in pnpm workspaces
- Replaced unicode escape sequences with literal characters
