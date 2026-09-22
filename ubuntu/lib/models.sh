#!/usr/bin/env bash
# Shared model metadata for the standalone Ubuntu/NVIDIA setup.
# Format: alias|source|native_context|role
UBUNTU_AI_MODELS=(
  "local-coder|qwen3.5:9b|262144|Default for focused coding and tool use; approximately 6.6 GB weights"
  "local-fast|qwen3.5:4b|262144|Faster small tasks and a fallback if 9B is too slow"
  "local-deepseek-coder|deepseek-coder-v2:16b|163840|Larger coding-focused MoE model; about 8.9 GB"
  "local-qwen-coder|qwen2.5-coder:14b|32768|Dedicated code model for refactoring, explanation, and generation; about 9.0 GB"
  "local-starcoder|starcoder2:instruct|16384|Instruct-tuned StarCoder2 for interactive programming; about 9.1 GB"
  "local-granite-code|granite-code:8b|131072|Lightweight IBM code model; about 4.6 GB"
  "local-gemma4-e2b|gemma4:e2b|131072|Compact Gemma 4 variant; about 7.2 GB"
  "local-gemma4-e4b|gemma4:e4b|131072|Mid-size Gemma 4 variant; about 9.6 GB"
  "local-gemma4-12b|gemma4:12b|262144|Dense Gemma 4 12B model; about 7.6 GB"
)

model_field() {
  local wanted="$1" field="$2" row alias source context role
  for row in "${UBUNTU_AI_MODELS[@]}"; do
    IFS='|' read -r alias source context role <<<"$row"
    if [[ "$alias" == "$wanted" ]]; then
      case "$field" in
        source) printf '%s\n' "$source" ;;
        context) printf '%s\n' "$context" ;;
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
