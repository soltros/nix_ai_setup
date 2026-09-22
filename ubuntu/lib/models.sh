#!/usr/bin/env bash
# Shared model metadata for the standalone Ubuntu/NVIDIA setup.
# Format: alias|source|native_context|runtime_context|supports_tools|role
UBUNTU_AI_MODELS=(
  "local-coder|qwen3.5:9b|262144|65536|yes|Focused coding/tool model; approximately 6.6 GB weights"
  "local-fast|qwen3.5:4b|262144|65536|yes|Faster small tasks and fallback"
  "local-deepseek-coder|deepseek-coder-v2:16b|163840|65536|no|Larger coding-focused MoE model; about 8.9 GB"
  "local-qwen-coder|qwen2.5-coder:14b|32768|32768|yes|OpenCode/direct coding model; below Hermes 64K minimum; about 9.0 GB"
  "local-starcoder|starcoder2:instruct|16384|16384|no|Interactive StarCoder2; about 9.1 GB"
  "local-granite-code|granite-code:8b|131072|65536|no|Lightweight IBM code model; about 4.6 GB"
  "local-gemma4-e2b|gemma4:e2b|131072|65536|yes|Compact Gemma 4 variant; about 7.2 GB"
  "local-gemma4-e4b|gemma4:e4b|131072|65536|yes|Mid-size Gemma 4 variant; about 9.6 GB"
  "local-gemma4-12b|gemma4:12b|262144|65536|yes|Default Hermes persona model; about 7.6 GB"
)

model_field() {
  local wanted="$1" field="$2" row alias source native_context runtime_context tools role
  for row in "${UBUNTU_AI_MODELS[@]}"; do
    IFS='|' read -r alias source native_context runtime_context tools role <<<"$row"
    if [[ "$alias" == "$wanted" ]]; then
      case "$field" in
        source) printf '%s\n' "$source" ;;
        native_context) printf '%s\n' "$native_context" ;;
        context|runtime_context) printf '%s\n' "$runtime_context" ;;
        tools) printf '%s\n' "$tools" ;;
        role) printf '%s\n' "$role" ;;
        *) return 2 ;;
      esac
      return 0
    fi
  done
  return 1
}

model_exists() {
  model_field "$1" source >/dev/null 2>&1
}
