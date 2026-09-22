# Ubuntu Local AI Setup

Standalone Ubuntu edition of `nix_ai_setup`, intended for Nicole's Ubuntu desktop with an **NVIDIA GeForce RTX 3060 12 GB**.

This setup recreates the same local-AI workflow as the NixOS version without requiring Nix:

- Ollama with NVIDIA/CUDA acceleration
- one bounded localhost gateway on `127.0.0.1:11435`
- the same tuned local model aliases
- per-model native context windows for Hermes/OpenCode
- Hermes Agent launchers
- OpenCode launchers
- Durandal, 343 Guilty Spark, and Rasputin Hermes personas
- Bash aliases and terminal help
- systemd services
- diagnostics and uninstall support
- optional Alpaca GUI

The setup deliberately **does not install or replace NVIDIA drivers**. The correct Ubuntu NVIDIA driver must already be working.

## Requirements

- Ubuntu
- NVIDIA GeForce RTX 3060 12 GB
- working proprietary NVIDIA driver
- `nvidia-smi` must work
- sudo access
- internet access for initial package/tool/model installation
- Bash

Verify the GPU first:

```bash
nvidia-smi
```

The installer exits if NVIDIA userspace is not working.

## Install

Clone the repository:

```bash
git clone https://github.com/soltros/nix_ai_setup.git
cd nix_ai_setup/ubuntu
```

Install the integration but do not download models yet:

```bash
bash install.sh
```

Install the integration plus the two default Qwen models:

```bash
bash install.sh --models core
```

Install everything, including every configured model:

```bash
bash install.sh --models all
```

Optionally install the Alpaca Flatpak GUI too:

```bash
bash install.sh --models core --with-alpaca
```

If Ollama, Hermes Agent, and OpenCode are already installed and you only want this repository's integration layer:

```bash
bash install.sh --skip-tools
```

After installation:

```bash
source ~/.bashrc
nixai --help
```

The installer uses the official Linux installers for Ollama, Hermes Agent, and OpenCode.

## What gets installed

Repository files are copied to:

```text
/opt/ubuntu-ai
```

Command entry points are symlinked into:

```text
/usr/local/bin
```

The bounded gateway is installed as:

```text
ubuntu-ai-gateway.service
```

Ollama remains the normal upstream:

```text
ollama.service
```

The setup adds an Ollama systemd drop-in at:

```text
/etc/systemd/system/ollama.service.d/ubuntu-ai.conf
```

The raw Ollama API remains available only on:

```text
http://127.0.0.1:11434
```

The bounded AI endpoint used by Hermes and OpenCode is:

```text
http://127.0.0.1:11435
```

## RTX 3060 Ollama settings

The installer configures Ollama for one local model at a time:

```text
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_MAX_QUEUE=4
OLLAMA_KEEP_ALIVE=5m
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KV_CACHE_TYPE=q8_0
OLLAMA_NO_CLOUD=1
```

The model aliases themselves define their correct native context windows.

This is important for Hermes: Hermes receives the same context length that the tuned Ollama alias uses.

## Models

| Model alias | Source | Native context | Tools | Role |
| --- | --- | ---: | :---: | --- |
| `local-coder:latest` | `qwen3.5:9b` | 262,144 | yes | Default focused coding/tool model; ~6.6 GB |
| `local-fast:latest` | `qwen3.5:4b` | 262,144 | yes | Faster small-task model |
| `local-deepseek-coder:latest` | `deepseek-coder-v2:16b` | 163,840 | no | Larger coding-focused MoE model; ~8.9 GB |
| `local-qwen-coder:latest` | `qwen2.5-coder:14b` | 32,768 | yes | Dedicated code/refactor model; ~9.0 GB |
| `local-starcoder:latest` | `starcoder2:instruct` | 16,384 | no | Interactive StarCoder2; ~9.1 GB |
| `local-granite-code:latest` | `granite-code:8b` | 131,072 | no | Lightweight IBM code model; ~4.6 GB |
| `local-gemma4-e2b:latest` | `gemma4:e2b` | 131,072 | yes | Compact Gemma 4; ~7.2 GB |
| `local-gemma4-e4b:latest` | `gemma4:e4b` | 131,072 | yes | Mid-size Gemma 4; ~9.6 GB |
| `local-gemma4-12b:latest` | `gemma4:12b` | 262,144 | yes | Gemma 4 12B; ~7.6 GB |

Only one model is configured to stay loaded at once.

Large context windows are model capability limits, not a promise that a 12 GB GPU can fill the entire window without memory pressure. KV cache usage grows with active context.

## Model management

Install one model:

```bash
ollama-get-coder
ollama-get-fast
ollama-get-deepseek-coder
ollama-get-qwen-coder
ollama-get-starcoder
ollama-get-granite-code
ollama-get-gemma4-e2b
ollama-get-gemma4-e4b
ollama-get-gemma4-12b
```

Install all configured models:

```bash
ollama-get-models
```

Direct model-manager interface:

```bash
ubuntu-ai-model list
ubuntu-ai-model install local-coder
ubuntu-ai-model install-all
ubuntu-ai-model remove local-coder
```

The install process first pulls the upstream Ollama model and then creates the tuned local alias with the appropriate `num_ctx`.

## Terminal help

The primary help command is:

```bash
nixai --help
```

It prints all configured models, sources, context windows, tool support, sampling parameters, Ollama/gateway limits, OpenCode aliases, Hermes aliases, direct chat-only aliases, model-management commands, and persona/skin mappings.

These compatibility aliases show the same output:

```bash
ollama-models
hermes-help
```

## Hermes personas

Three personas are included.

| Persona | Default Bash alias | Skin |
| --- | --- | --- |
| Durandal | `hermes-coder` | `durandal-marathon` |
| 343 Guilty Spark | `spark` | `guilty-spark-forerunner` |
| Rasputin | `rasputin` | `rasputin-ikelos` |

The Ubuntu SOUL files are adapted specifically for **Nicole + Ubuntu**. They preserve the character/style layer from the NixOS setup but replace NixOS-specific operating rules with Ubuntu, apt, systemd, NVIDIA, and `/opt/ubuntu-ai` behavior.

Runtime Hermes state lives under:

```text
~/.local/state/ubuntu-ai/hermes
```

The launcher regenerates `config.yaml` for every run, symlinks the selected SOUL and skin, and sets the correct native model context.

Hermes and OpenCode agent launchers are intentionally limited to models that advertise native tool calling in Ollama. DeepSeek Coder V2, StarCoder2, and Granite Code remain available for direct coding/chat through:

```bash
deepseek-chat
starcoder-chat
granite-chat
```

The generic `hermes-ubuntu` and `opencode-ubuntu` launchers reject those non-tool models with a clear error instead of allowing an agent client to fail mid-request.

### Durandal aliases

```bash
hermes-coder
hermes-fast
hermes-qwen-coder
hermes-gemma4-e2b
hermes-gemma4-e4b
hermes-gemma4-12b
```

### 343 Guilty Spark aliases

```bash
spark
spark-fast
spark-qwen-coder
spark-gemma4-e2b
spark-gemma4-e4b
spark-gemma4-12b
```

### Rasputin aliases

```bash
rasputin
rasputin-fast
rasputin-qwen-coder
rasputin-gemma4-e2b
rasputin-gemma4-e4b
rasputin-gemma4-12b
```

You can also bypass aliases:

```bash
hermes-ubuntu durandal local-coder
hermes-ubuntu guilty-spark local-gemma4-12b
hermes-ubuntu rasputin local-deepseek-coder
```

Any extra arguments are passed to Hermes.

## OpenCode

Every local OpenCode launcher enables [`opencode-mem`](https://github.com/tickernelz/opencode-mem) through OpenCode's native v2 `plugins` list. The published plugin package is downloaded automatically by OpenCode on first startup.

The launcher seeds this file only if it does not already exist:

```text
~/.config/opencode/opencode-mem.jsonc
```

The seeded defaults keep storage local at `~/.opencode-mem/data`, expose the web UI only on `127.0.0.1:4747`, enable auto-capture, and use `ubuntu-local` with `opencodeModel: "inherit"`. Existing user edits are never overwritten on later launches. Manual memory search/add/list operations remain usable even if automatic capture cannot obtain structured output.

The tool-capable local models are exposed through OpenCode:

```bash
opencode-local
opencode-local-fast
opencode-local-qwen-coder
opencode-local-gemma4-e2b
opencode-local-gemma4-e4b
opencode-local-gemma4-12b
```

The generic form is:

```bash
opencode-ubuntu local-coder
```

OpenCode is forced to the local `ubuntu-local` provider and the bounded localhost endpoint.

The launcher sets:

- the selected model
- its native context limit
- 4,096 maximum output tokens
- the local-fast model for small-model work
- 12 build/plan steps
- task delegation disabled
- sharing disabled
- automatic updates disabled inside OpenCode

## Bounded gateway

The gateway intentionally limits generation behavior while leaving model management on the raw Ollama port.

It:

- binds to localhost only
- permits generation and read-only model discovery routes
- caps output at 4,096 tokens
- applies a 180-second generation deadline
- disables thinking/reasoning requests
- permits one response at a time through the Ollama configuration
- does **not** override model context; the tuned Ollama aliases own context

Use port `11434` for `ollama pull`, `ollama create`, and other management operations.

Use port `11435` for Hermes, OpenCode, and other OpenAI-compatible clients.

## Alpaca

Install with:

```bash
bash install.sh --with-alpaca
```

The installer adds Flatpak/Flathub if necessary and installs:

```text
com.jeffser.Alpaca
```

Configure Alpaca to use an external Ollama/OpenAI-compatible connection through the local services rather than launching a separate competing backend.

## Validation

A repository CI workflow at `.github/workflows/ubuntu-validate.yml` validates the Ubuntu tree on `ubuntu-latest` with:

- `bash -n` for every Bash script
- ShellCheck
- Python bytecode compilation
- the bounded-gateway unit test suite

The installer also runs the gateway unit tests locally before it enables `ubuntu-ai-gateway.service`.

Manual unit-test run:

```bash
cd /opt/ubuntu-ai
python3 -m unittest -v test_gateway.py
```

After `local-coder` has been installed, run the live end-to-end test:

```bash
cd /opt/ubuntu-ai
python3 smoke.py
```

The smoke test checks native Ollama generation through the bounded gateway, OpenAI-compatible generation, structured tool calls, disabled reasoning, and reported GPU residency.

CI cannot verify the real RTX 3060, NVIDIA driver, CUDA execution, full VRAM residency, or an actual interactive Hermes/OpenCode session. Those checks must be done on Nicole's Ubuntu machine.

## Diagnostics

Run:

```bash
ubuntu-ai-diagnose
```

It checks:

- NVIDIA GPU visibility and VRAM
- NVIDIA driver version
- `ollama.service`
- `ubuntu-ai-gateway.service`
- raw Ollama API
- bounded gateway API
- Ollama/Hermes/OpenCode commands
- local model inventory
- active model residency via `ollama ps`

Useful manual checks:

```bash
nvidia-smi
ollama list
ollama ps
systemctl status ollama
systemctl status ubuntu-ai-gateway
journalctl -u ollama -b --no-pager -n 100
journalctl -u ubuntu-ai-gateway -b --no-pager -n 100
```

For a loaded model, `ollama ps` is the quickest way to see whether the model is fully on the GPU or partially offloaded.

## Bash integration

The installer adds one line to Nicole's `~/.bashrc`:

```bash
source /opt/ubuntu-ai/bash_aliases.sh
```

The alias file also places the normal per-user Hermes and OpenCode install directories on `PATH`:

```text
~/.local/bin
~/.opencode/bin
```

No Zsh configuration is required.

## Updating

From the repository checkout:

```bash
git pull
cd ubuntu
bash install.sh --skip-tools
source ~/.bashrc
```

This refreshes the scripts, aliases, gateway, personas, skins, and systemd configuration without reinstalling upstream tools or models.

## Uninstall

Run:

```bash
bash /opt/ubuntu-ai/uninstall.sh
```

The uninstaller removes:

- `/opt/ubuntu-ai`
- local command symlinks
- Bash integration line
- bounded gateway systemd unit
- Ollama systemd drop-in
- generated local Hermes runtime state

It intentionally **does not remove**:

- NVIDIA drivers
- Ollama itself
- Hermes Agent itself
- OpenCode itself
- downloaded Ollama models

This avoids destructive cleanup of software or model data Nicole may still want.

## Upstream installation sources

- Ollama Linux: https://ollama.com/download/linux
- Hermes Agent: https://hermes-agent.nousresearch.com/docs/getting-started/installation
- OpenCode: https://opencode.ai/docs/
- Alpaca: https://flathub.org/apps/com.jeffser.Alpaca

## Layout

```text
ubuntu/
├── README.md
├── install.sh
├── uninstall.sh
├── bash_aliases.sh
├── gateway.py
├── bin/
│   ├── hermes-ubuntu
│   ├── opencode-ubuntu
│   ├── nixai
│   ├── ubuntu-ai-diagnose
│   ├── ubuntu-ai-help
│   └── ubuntu-ai-model
├── lib/
│   └── models.sh
├── personas/
│   ├── durandal/SOUL.md
│   ├── guilty-spark/SOUL.md
│   └── rasputin/SOUL.md
├── skins/
│   ├── durandal-marathon.yaml
│   ├── guilty-spark-forerunner.yaml
│   └── rasputin-ikelos.yaml
└── systemd/
    └── ubuntu-ai-gateway.service
```
