# Ensure user-installed Hermes/OpenCode launchers are visible.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# shellcheck shell=bash
# Bash command layer for the standalone Ubuntu AI setup.

alias ollama-models='ubuntu-ai-help'
alias hermes-help='ubuntu-ai-help'

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

# Durandal
alias hermes-coder='hermes-ubuntu durandal local-coder'
alias hermes-fast='hermes-ubuntu durandal local-fast'
alias hermes-deepseek='hermes-ubuntu durandal local-deepseek-coder'
alias hermes-qwen-coder='hermes-ubuntu durandal local-qwen-coder'
alias hermes-starcoder='hermes-ubuntu durandal local-starcoder'
alias hermes-granite='hermes-ubuntu durandal local-granite-code'
alias hermes-gemma4-e2b='hermes-ubuntu durandal local-gemma4-e2b'
alias hermes-gemma4-e4b='hermes-ubuntu durandal local-gemma4-e4b'
alias hermes-gemma4-12b='hermes-ubuntu durandal local-gemma4-12b'

# 343 Guilty Spark
alias spark='hermes-ubuntu guilty-spark local-coder'
alias spark-fast='hermes-ubuntu guilty-spark local-fast'
alias spark-deepseek='hermes-ubuntu guilty-spark local-deepseek-coder'
alias spark-qwen-coder='hermes-ubuntu guilty-spark local-qwen-coder'
alias spark-starcoder='hermes-ubuntu guilty-spark local-starcoder'
alias spark-granite='hermes-ubuntu guilty-spark local-granite-code'
alias spark-gemma4-e2b='hermes-ubuntu guilty-spark local-gemma4-e2b'
alias spark-gemma4-e4b='hermes-ubuntu guilty-spark local-gemma4-e4b'
alias spark-gemma4-12b='hermes-ubuntu guilty-spark local-gemma4-12b'

# Rasputin
alias rasputin='hermes-ubuntu rasputin local-coder'
alias rasputin-fast='hermes-ubuntu rasputin local-fast'
alias rasputin-deepseek='hermes-ubuntu rasputin local-deepseek-coder'
alias rasputin-qwen-coder='hermes-ubuntu rasputin local-qwen-coder'
alias rasputin-starcoder='hermes-ubuntu rasputin local-starcoder'
alias rasputin-granite='hermes-ubuntu rasputin local-granite-code'
alias rasputin-gemma4-e2b='hermes-ubuntu rasputin local-gemma4-e2b'
alias rasputin-gemma4-e4b='hermes-ubuntu rasputin local-gemma4-e4b'
alias rasputin-gemma4-12b='hermes-ubuntu rasputin local-gemma4-12b'

# OpenCode
alias opencode-local='opencode-ubuntu local-coder'
alias opencode-local-fast='opencode-ubuntu local-fast'
alias opencode-local-deepseek='opencode-ubuntu local-deepseek-coder'
alias opencode-local-qwen-coder='opencode-ubuntu local-qwen-coder'
alias opencode-local-starcoder='opencode-ubuntu local-starcoder'
alias opencode-local-granite='opencode-ubuntu local-granite-code'
alias opencode-local-gemma4-e2b='opencode-ubuntu local-gemma4-e2b'
alias opencode-local-gemma4-e4b='opencode-ubuntu local-gemma4-e4b'
alias opencode-local-gemma4-12b='opencode-ubuntu local-gemma4-12b'
