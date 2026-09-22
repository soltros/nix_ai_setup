#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT=/opt/ubuntu-ai
MODELS=none
SKIP_TOOLS=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--models none|core|all] [--skip-tools]

  --models none  Install configuration only (default)
  --models core  Also install Qwen3.5 9B and 4B
  --models all   Also install every configured model
  --skip-tools   Do not install Ollama, Hermes, or OpenCode
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models) MODELS="${2:-}"; shift 2 ;;
    --skip-tools) SKIP_TOOLS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ "$MODELS" =~ ^(none|core|all)$ ]] || { echo "Invalid --models value" >&2; exit 2; }

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify this Linux distribution." >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This installer targets Ubuntu. Detected: ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required." >&2
  exit 1
fi

echo "== Ubuntu AI setup =="
echo "User: $USER"
echo "Install root: $INSTALL_ROOT"

echo
echo "== NVIDIA validation =="
if ! command -v nvidia-smi >/dev/null 2>&1; then
  cat >&2 <<'EOF'
nvidia-smi is not available.
Install/enable the correct Ubuntu NVIDIA driver for the RTX 3060 first, reboot,
and rerun this installer. This setup deliberately does not replace GPU drivers.
EOF
  exit 1
fi
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

echo
echo "== Ubuntu dependencies =="
sudo apt-get update
sudo apt-get install -y curl git xz-utils ca-certificates python3 python3-aiohttp

if (( SKIP_TOOLS == 0 )); then
  echo
  echo "== Ollama =="
  if ! command -v ollama >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh | sh
  else
    echo "Ollama already installed: $(command -v ollama)"
  fi

  echo
  echo "== Hermes Agent =="
  if ! command -v hermes >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/hermes" ]]; then
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  else
    echo "Hermes already installed."
  fi

  echo
  echo "== OpenCode =="
  if ! command -v opencode >/dev/null 2>&1 && [[ ! -x "$HOME/.opencode/bin/opencode" ]]; then
    curl -fsSL https://opencode.ai/install | bash
  else
    echo "OpenCode already installed."
  fi
fi

echo
echo "== Installing Ubuntu AI files =="
sudo install -d -m 0755 "$INSTALL_ROOT"
sudo cp -a "$SCRIPT_DIR/." "$INSTALL_ROOT/"
sudo find "$INSTALL_ROOT/bin" -type f -exec chmod 0755 {} +
sudo chmod 0755 "$INSTALL_ROOT/install.sh" "$INSTALL_ROOT/uninstall.sh" 2>/dev/null || true

for cmd in ubuntu-ai-model ubuntu-ai-help ubuntu-ai-diagnose hermes-ubuntu opencode-ubuntu; do
  sudo ln -sfn "$INSTALL_ROOT/bin/$cmd" "/usr/local/bin/$cmd"
done

echo
echo "== Configuring Ollama for the RTX 3060 =="
sudo install -d -m 0755 /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/ubuntu-ai.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_MAX_QUEUE=4"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_NO_CLOUD=1"
EOF

sudo install -m 0644 "$INSTALL_ROOT/systemd/ubuntu-ai-gateway.service" /etc/systemd/system/ubuntu-ai-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable --now ollama
sudo systemctl restart ollama
sudo systemctl enable --now ubuntu-ai-gateway

echo
echo "== Bash integration =="
line='source /opt/ubuntu-ai/bash_aliases.sh'
touch "$HOME/.bashrc"
if ! grep -Fqx "$line" "$HOME/.bashrc"; then
  {
    echo
    echo '# Ubuntu local AI setup'
    echo "$line"
  } >> "$HOME/.bashrc"
fi

# Make user-installed tools visible in this shell when their installers used
# standard per-user locations.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

case "$MODELS" in
  core)
    ubuntu-ai-model install local-coder
    ubuntu-ai-model install local-fast
    ;;
  all)
    ubuntu-ai-model install-all
    ;;
esac

echo
echo "Installation complete."
echo "Run: source ~/.bashrc"
echo "Then: hermes-help"
echo "Diagnostics: ubuntu-ai-diagnose"
