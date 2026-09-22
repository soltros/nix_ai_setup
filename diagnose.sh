#!/usr/bin/env bash
set -u
printf '\nLocal AI services\n'
systemctl --no-pager --full status ollama nix-ai-gateway nix-ai-models || true
printf '\nGPU devices\n'
ls -l /dev/dri || true
for path in /sys/class/drm/card*/device/mem_info_vram_total; do
  [ -f "$path" ] || continue
  printf '%s: %s bytes\n' "$path" "$(cat "$path")"
done
printf '\nModels and processor placement\n'
ollama list
ollama ps
printf '\nRecent logs\n'
journalctl -u ollama -u nix-ai-gateway -u nix-ai-models -b --no-pager -n 60
