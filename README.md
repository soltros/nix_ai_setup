# nix_ai_setup

NixOS flake module providing Nixpkgs **Alpaca**, Vulkan-accelerated **Ollama**, and a bounded local endpoint for **Hermes**, **OpenCode**, and other OpenAI-compatible coding tools.

## Hardware and model choice

Prepared for a Ryzen 5 5600X (6 cores / 12 threads), 32 GB RAM, and a **12 GiB AMD Navi 22 GPU**. PCI device `1002:73df`, subsystem `148c:2410`; the exact retail card name was not established. Vulkan avoids depending on an unsupported ROCm GPU override.

| Model alias | Source | Role |
| --- | --- | --- |
| `local-coder:latest` | `qwen3.5:9b` | Default for focused coding and tool use; approximately 6.6 GB weights |
| `local-fast:latest` | `qwen3.5:4b` | Faster small tasks and a fallback if 9B is too slow |
| `local-deepseek-coder:latest` | `deepseek-coder-v2:16b` | Larger coding-focused MoE model; about 8.9 GB |
| `local-qwen-coder:latest` | `qwen2.5-coder:14b` | Dedicated code model for refactoring, explanation, and generation; about 9.0 GB |
| `local-starcoder:latest` | `starcoder2:instruct` | Instruct-tuned StarCoder2 for interactive programming; about 9.1 GB |
| `local-granite-code:latest` | `granite-code:8b` | Lightweight IBM code model; about 4.6 GB |

These are hardware-informed starting choices, **not benchmarked winners**. The complete set requires substantially more than 11 GB of disk space, although only one model is loaded into memory at a time. A 16,384-token context and Q8 KV cache leave room for desktop graphics and runtime buffers. Actual GPU residency must be checked after activation. Larger 27B/30B models risk substantial CPU offload on this card; they are not included by default.

Small local models will still make mistakes on complex repository tasks. Disabling thinking trades some difficult reasoning performance for direct responses. Start with one focused edit, inspect the diff, and run its relevant test.

## Add to your existing flake

```nix
inputs.nix-ai-setup = {
  url = "github:soltros/nix_ai_setup";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Your existing `outputs = { ... }@inputs:` already exposes the input. Add these entries to the host's `modules` list:

```nix
inputs.nix-ai-setup.nixosModules.default
{ services.nix-ai-setup.enable = true; }
```

Then run your usual `nixos-rebuild switch --flake ...`. This repository does not change or activate your existing system flake. It uses recent nixos-unstable options, notably `pkgs.ollama-vulkan`; the lock is pinned to the same Nixpkgs revision inspected on your machine. `follows` makes your parent flake's pin authoritative.

If cloning a private repository, use `git+ssh://git@github.com/soltros/nix_ai_setup` as the input URL, or clone it with `gh repo clone soltros/nix_ai_setup` and use a local `path:` input. An authenticated GitHub fetcher can also use the GitHub URL above.

## First startup

Model downloads are explicit so rebuilding never starts a large network transfer. After activation, open a new Zsh session and choose one of these aliases:

```sh
ollama-get-coder            # Qwen3.5 9B
ollama-get-fast             # Qwen3.5 4B
ollama-get-deepseek-coder   # DeepSeek Coder V2 16B
ollama-get-qwen-coder       # Qwen2.5-Coder 14B
ollama-get-starcoder        # StarCoder2 Instruct
ollama-get-granite-code     # Granite Code 8B
ollama-get-models           # install every configured model, sequentially
ollama list
```

The aliases first pull the upstream model and then create the tuned local alias used by Hermes and OpenCode. They are safe to run again after an interrupted download. Existing unrelated models are never deleted. Upstream model tags can change; `flake.lock` pins Nix packages, not downloaded model weights. Record `ollama list` IDs when comparing results.

## Connect your tools

**Alpaca:** open Preferences / connection settings, add an **external Ollama** connection to `http://127.0.0.1:11435`, then select `local-coder:latest`. Use this shared connection rather than starting Alpaca's own managed Ollama. Model management is done with the `ollama` command, since the bounded endpoint intentionally exposes only generation and read-only discovery.

**Hermes CLI:** run `hermes-local`. Hermes must already be installed (it is on the inspected system). This starts a separate local configuration under `${XDG_STATE_HOME:-$HOME/.local/state}/nix-ai-setup/hermes`, with file and terminal tools, 12 model iterations, one API retry, no cloud fallback, and thinking disabled. Existing Hermes profiles and credentials are not copied or changed. The generated local config is refreshed each launch; persist custom settings in this module instead.

**Hermes Desktop / another Hermes profile:** select a custom OpenAI-compatible provider with the settings below. `/etc/nix-ai-setup/hermes.yaml` contains the complete example, including `agent.max_turns = 12`. Selecting just the endpoint does not apply the profile's step limit.

**OpenCode:** installed by this module. Run `opencode-local` for Qwen3.5 9B, `opencode-local-fast` for Qwen3.5 4B, `opencode-local-deepseek` for DeepSeek Coder V2 16B, `opencode-local-qwen-coder` for Qwen2.5-Coder 14B, `opencode-local-starcoder` for StarCoder2 Instruct, or `opencode-local-granite` for Granite Code 8B. All six launchers force the bounded local provider even when a repository contains its own OpenCode configuration, cap build/plan agents at 12 steps, disable task delegation, disable sharing, and leave automatic package updates to Nix. Normal `opencode` retains your normal configuration and providers.

For a one-shot task, use either launcher exactly like regular OpenCode:

```sh
opencode-local run "Inspect this repository and explain the failing test"
opencode-local-fast run "Summarize the current diff"
```

The generated configuration remains available at `/etc/nix-ai-setup/opencode.json` for inspection and for tools that accept a configuration path.

**Other tools** (for example an editor's OpenAI-compatible provider):

| Setting | Value |
| --- | --- |
| API base URL | `http://127.0.0.1:11435/v1` |
| API key, if required | `ollama` (placeholder; no cloud key needed) |
| Model | Any configured local alias, such as `local-coder:latest`, `local-deepseek-coder:latest`, or `local-granite-code:latest` |
| Context window | `16384` |
| Maximum output | `4096` |

Use Chat Completions. The gateway does not implement the Responses or Anthropic APIs. Set a finite iteration limit in each additional agent; a server cannot stop a client from sending unlimited separate requests.

## What prevents runaway generation

- The gateway enforces `think: false` for Ollama and `reasoning_effort: none` for OpenAI chat requests, even when the client requests thinking.
- Each response is capped at 4,096 output tokens and 180 seconds including upstream queueing. Smaller client token limits are preserved. Timeout during streaming closes the connection; callers may report an interrupted response.
- Hermes and OpenCode configurations cap their agent loops at 12 steps. These are per-run limits, not a total session time limit.
- Ollama loads one model and processes one generation at a time. A short queue limits contention.
- Both ports bind only to localhost. The raw backend on **11434** is for model management; clients using it bypass the gateway limits.

This bounds work; it does not guarantee correct answers or eliminate every repeated action. Other agents need their own retry/step limits. Avoid launching several coding agents on one 12 GiB GPU.

Optional tuning in your host configuration:

```nix
services.nix-ai-setup = {
  enable = true;
  contextLength = 16384;
  maxTokens = 4096;
  requestTimeout = 180;
};
```

If long outputs truncate, raise `maxTokens` modestly. If prefill times out, first reduce the enabled tools or task size. Raising context increases memory use; check GPU residency before doing so.

## Triage together

From a checkout, after the model download completes:

```sh
bash diagnose.sh
python3 smoke.py
ollama ps
```

The smoke test checks native generation, OpenAI generation, and an actual structured tool call without executing model-generated commands. It prints timing and fails if thinking appears, tool calling fails, or Ollama reports CPU offload. GPU checks must run on the real desktop.

For logs:

```sh
journalctl -u ollama -u nix-ai-gateway -b --no-pager -n 100
```

## Validation and limitations

See `VALIDATION.md` for checks performed before the initial commit. The authoring sandbox exposes sysfs hardware information but no `/dev/dri` GPU devices. GPU throughput, full residency, GUI interaction, and an end-to-end Hermes coding task therefore remain to be tested after activation. No system rebuild was applied.

## Sources

- [Qwen3.5 9B model and size](https://ollama.com/library/qwen3.5:9b)
- [DeepSeek Coder V2](https://ollama.com/library/deepseek-coder-v2)
- [Qwen2.5-Coder](https://ollama.com/library/qwen2.5-coder)
- [StarCoder2](https://ollama.com/library/starcoder2)
- [Granite Code](https://ollama.com/library/granite-code)
- [Qwen3.5 model card and non-thinking sampling guidance](https://huggingface.co/Qwen/Qwen3.5-9B)
- [Ollama Vulkan support](https://docs.ollama.com/gpu)
- [Ollama OpenAI-compatible API](https://docs.ollama.com/api/openai-compatibility)
- [Hermes local Ollama setup](https://hermes-agent.nousresearch.com/docs/guides/local-ollama-setup)
- [OpenCode providers](https://opencode.ai/docs/providers/) and [agent step limits](https://opencode.ai/docs/agents/)
