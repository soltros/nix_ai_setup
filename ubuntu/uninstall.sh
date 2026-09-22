#!/usr/bin/env bash
set -euo pipefail
INSTALL_ROOT=/opt/ubuntu-ai

echo "Removing Ubuntu AI integration. Ollama models and upstream tools are left intact."

sudo systemctl disable --now ubuntu-ai-gateway.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ubuntu-ai-gateway.service
sudo rm -f /etc/systemd/system/ollama.service.d/ubuntu-ai.conf
sudo rmdir /etc/systemd/system/ollama.service.d 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl restart ollama 2>/dev/null || true

for cmd in ubuntu-ai-model ubuntu-ai-help ubuntu-ai-diagnose hermes-ubuntu opencode-ubuntu; do
  sudo rm -f "/usr/local/bin/$cmd"
done

if [[ -f "$HOME/.bashrc" ]]; then
  sed -i '\|^# Ubuntu local AI setup$|d;\|^source /opt/ubuntu-ai/bash_aliases.sh$|d' "$HOME/.bashrc"
fi

sudo rm -rf "$INSTALL_ROOT"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-ai"

echo "Removed Ubuntu AI integration."
echo "Ollama, Hermes, OpenCode, NVIDIA drivers, and downloaded Ollama models were not removed."
