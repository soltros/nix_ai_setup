# Ensure user-installed Hermes/OpenCode launchers are visible.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# shellcheck shell=bash
# Bash command layer for the standalone Ubuntu AI setup.

alias ollama-models='nixai --help'
alias hermes-help='nixai --help'

alias ollama-get-coder='ubuntu-ai-model install local-coder'
alias ollama-get-fast='ubuntu-ai-model install local-fast'
alias ollama-get-deepseek-coder='ubuntu-ai-model install local-deepseek-coder'
alias ollama-get-qwen-coder='ubuntu-ai-model install local-qwen-coder'
alias ollama-get-starcoder='ubuntu-ai-model install local-starcoder'
alias ollama-get-granite-code='ubuntu-ai-model install local-granite-code'
alias ollama-get-gemma4-e2b='ubuntu-ai-model install local-gemma4-e2b'
alias ollama-get-gemma4-e4b='ubuntu-ai-model install local-gemma4-e4b'
alias ollama-get-gemma4-12b='ubuntu-ai-model install local-gemma4-12b'
alias ollama-get-models='ubuntu-ai-model install-all'
alias ollama-sync-contexts='ubuntu-ai-model sync'
alias ollama-sync-model-contexts='ubuntu-ai-model sync'

# Durandal
alias durandal='hermes-ubuntu durandal local-gemma4-12b'
alias durandal-fast='hermes-ubuntu durandal local-fast'
alias durandal-gemma4-e2b='hermes-ubuntu durandal local-gemma4-e2b'
alias durandal-gemma4-e4b='hermes-ubuntu durandal local-gemma4-e4b'
alias durandal-gemma4-12b='hermes-ubuntu durandal local-gemma4-12b'

# Backward-compatible Durandal aliases
alias hermes-coder='hermes-ubuntu durandal local-coder'
alias hermes-fast='hermes-ubuntu durandal local-fast'
alias hermes-gemma4-e2b='hermes-ubuntu durandal local-gemma4-e2b'
alias hermes-gemma4-e4b='hermes-ubuntu durandal local-gemma4-e4b'
alias hermes-gemma4-12b='hermes-ubuntu durandal local-gemma4-12b'

# 343 Guilty Spark
alias spark='hermes-ubuntu guilty-spark local-gemma4-12b'
alias spark-fast='hermes-ubuntu guilty-spark local-fast'
alias spark-gemma4-e2b='hermes-ubuntu guilty-spark local-gemma4-e2b'
alias spark-gemma4-e4b='hermes-ubuntu guilty-spark local-gemma4-e4b'
alias spark-gemma4-12b='hermes-ubuntu guilty-spark local-gemma4-12b'

# Rasputin
alias rasputin='hermes-ubuntu rasputin local-gemma4-12b'
alias rasputin-fast='hermes-ubuntu rasputin local-fast'
alias rasputin-gemma4-e2b='hermes-ubuntu rasputin local-gemma4-e2b'
alias rasputin-gemma4-e4b='hermes-ubuntu rasputin local-gemma4-e4b'
alias rasputin-gemma4-12b='hermes-ubuntu rasputin local-gemma4-12b'

# OpenCode
alias opencode-local='opencode-ubuntu local-coder'
alias opencode-local-fast='opencode-ubuntu local-fast'
alias opencode-local-qwen-coder='opencode-ubuntu local-qwen-coder'
alias opencode-local-gemma4-e2b='opencode-ubuntu local-gemma4-e2b'
alias opencode-local-gemma4-e4b='opencode-ubuntu local-gemma4-e4b'
alias opencode-local-gemma4-12b='opencode-ubuntu local-gemma4-12b'

# Direct coding/chat aliases for models not exposed through Hermes.
alias qwen-coder-chat='ollama run local-qwen-coder:latest'
alias deepseek-chat='ollama run local-deepseek-coder:latest'
alias starcoder-chat='ollama run local-starcoder:latest'
alias granite-chat='ollama run local-granite-code:latest'
