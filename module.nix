{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nix-ai-setup;
  python = pkgs.python3.withPackages (p: [ p.aiohttp ]);
  endpoint = "http://127.0.0.1:11435";
  aliases = {
    local-coder = "qwen3.5:9b";
    local-fast = "qwen3.5:4b";
    local-deepseek-coder = "deepseek-coder-v2:16b";
    local-qwen-coder = "qwen2.5-coder:14b";
    local-starcoder = "starcoder2:instruct";
    local-granite-code = "granite-code:8b";
    local-gemma4-e2b = "gemma4:e2b";
    local-gemma4-e4b = "gemma4:e4b";
    local-gemma4-12b = "gemma4:12b";
  };
  modelContexts = {
    local-coder = 262144;
    local-fast = 262144;
    local-deepseek-coder = 163840;
    local-qwen-coder = 32768;
    local-starcoder = 16384;
    local-granite-code = 131072;
    local-gemma4-e2b = 131072;
    local-gemma4-e4b = 131072;
    local-gemma4-12b = 262144;
  };
  toolCapableModels = [
    "local-coder:latest"
    "local-fast:latest"
    "local-qwen-coder:latest"
    "local-gemma4-e2b:latest"
    "local-gemma4-e4b:latest"
    "local-gemma4-12b:latest"
  ];
  contextForModel =
    model:
    let
      localName = lib.removeSuffix ":latest" (lib.removePrefix "nix-local/" model);
    in
    modelContexts.${localName};
  modelfile =
    name: source:
    pkgs.writeText "${name}.Modelfile" ''
      FROM ${source}
      PARAMETER num_ctx ${toString modelContexts.${name}}
      PARAMETER num_predict ${toString cfg.maxTokens}
      PARAMETER temperature 0.7
      PARAMETER top_p 0.8
      PARAMETER top_k 20
      PARAMETER presence_penalty 1.5
      PARAMETER repeat_penalty 1.0
    '';
  installModel =
    name: source: "ollama pull ${source} && ollama create ${name} -f ${modelfile name source}";
  hermesConfigFor =
    name: model: skin:
    (pkgs.formats.yaml { }).generate "${name}.yaml" {
      model = {
        provider = "custom";
        default = model;
        base_url = "${endpoint}/v1";
        api_key = "ollama";
        context_length = contextForModel model;
      };
      agent = {
        max_turns = 12;
        api_max_retries = 1;
        reasoning_effort = "none";
      };
      platform_toolsets.cli = [
        "terminal"
        "file"
      ];
      terminal = {
        backend = "local";
        timeout = 60;
      };
      compression = {
        enabled = true;
        threshold = 0.65;
      };
      auxiliary = lib.genAttrs [ "compression" "title_generation" "tool_selection" ] (_: {
        provider = "main";
      });
      fallback_providers = [ ];
      display.skin = skin;
    };
  hermesConfig = hermesConfigFor "hermes-local" "local-coder:latest" "durandal-marathon";
  openCodeConfigFor = model: {
    "$schema" = "https://opencode.ai/config.json";
    inherit model;
    small_model = "nix-local/local-fast:latest";
    enabled_providers = [ "nix-local" ];
    plugin = [
      "opencode-mem"
      "@nick-vi/opencode-type-inject@latest"
      "@mohak34/opencode-notifier@latest"
      [
        "@prevalentware/opencode-goal-plugin"
        {
          auto_continue = true;
          defer_while_tasks_active = true;
          max_auto_turns = 8;
          min_continue_interval_seconds = 3;
          max_turn_time = 180;
          max_task_block_seconds = 600;
          max_prompt_failures = 2;
          max_goal_duration_seconds = 900;
          no_progress_token_threshold = 50;
          max_no_progress_turns = 2;
          restricted_agents = [ "plan" ];
          allow_goal_execution_from_plan = false;
        }
      ]
      # DCP stays last so its context transforms run after the other plugins.
      "@tarquinen/opencode-dcp@latest"
    ];
    autoupdate = false;
    share = "disabled";
    provider.nix-local = {
      npm = "@ai-sdk/openai-compatible";
      name = "Local GPU (bounded)";
      options = {
        baseURL = "${endpoint}/v1";
        apiKey = "ollama";
        timeout = (cfg.requestTimeout + 10) * 1000;
        headerTimeout = (cfg.requestTimeout + 10) * 1000;
        chunkTimeout = (cfg.requestTimeout + 10) * 1000;
      };
      models = lib.genAttrs toolCapableModels (name: {
        inherit name;
        limit = {
          context = contextForModel name;
          output = cfg.maxTokens;
        };
      });
    };
    agent = {
      build = {
        steps = 12;
        permission.task = "deny";
      };
      plan = {
        steps = 12;
        permission.task = "deny";
      };
    };
  };
  openCodeConfigJSON = builtins.toJSON (openCodeConfigFor "nix-local/local-coder:latest");
  openCodeConfig = pkgs.writeText "opencode-local.json" openCodeConfigJSON;
  openCodeLauncher =
    name: model:
    let
      runtimeConfig = pkgs.writeText "${name}.json" (builtins.toJSON (openCodeConfigFor model));
    in
    pkgs.writeShellScriptBin name ''
      # Inline config has higher precedence than project config, so a project
      # cannot silently switch this launcher back to a cloud provider.
      OPENCODE_CONFIG_CONTENT="$(< ${runtimeConfig})"
      export OPENCODE_CONFIG_CONTENT

      # Seed opencode-mem once. User edits are preserved on later launches.
      mem_config="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode-mem.jsonc"
      tui_config="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode/tui.json"
      if [ ! -e "$tui_config" ]; then
        mkdir -p "$(dirname "$tui_config")"
        cat >"$tui_config" <<'EOF'
{
  "plugin": [
    "@prevalentware/opencode-goal-plugin",
    "@tarquinen/opencode-dcp@latest"
  ]
}
EOF
      fi

      if [ ! -e "$mem_config" ]; then
        mkdir -p "$(dirname "$mem_config")"
        cat >"$mem_config" <<'EOF'
{
  "storagePath": "~/.opencode-mem/data",
  "webServerEnabled": true,
  "webServerHost": "127.0.0.1",
  "webServerPort": 4747,
  "autoCaptureEnabled": true,
  "opencodeProvider": "nix-local",
  "opencodeModel": "inherit",
  "showAutoCaptureToasts": true,
  "showUserProfileToasts": true,
  "showErrorToasts": true,
  "userProfileAnalysisInterval": 10,
  "maxMemories": 10,
  "compaction": {
    "enabled": true,
    "memoryLimit": 10
  },
  "chatMessage": {
    "enabled": true,
    "maxMemories": 3,
    "excludeCurrentSession": true,
    "injectOn": "first"
  }
}
EOF
      fi

      exec ${lib.getExe pkgs.opencode} "$@"
    '';
  hermesLauncher =
    name: model: persona: skin:
    let
      runtimeConfig = hermesConfigFor name model skin;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        hermes_system_home=/var/lib/hermes/.hermes
        persona_soul="$hermes_system_home/personas/${persona}/SOUL.md"
        persona_skin="$hermes_system_home/skins/${skin}.yaml"

        if [ ! -r "$persona_soul" ] || [ ! -r "$persona_skin" ]; then
          echo "nix-ai-setup: Hermes persona assets are missing for ${persona}." >&2
          echo "Expected $persona_soul and $persona_skin from modules/durandal-hermes-skin.nix." >&2
          exit 1
        fi

        export HERMES_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-ai-setup/hermes"
        mkdir -p "$HERMES_HOME/skins"
        cp ${runtimeConfig} "$HERMES_HOME/config.yaml"
        chmod 600 "$HERMES_HOME/config.yaml"

        # Persona assets remain declaratively owned by nixos-config.
        ln -sfn "$persona_soul" "$HERMES_HOME/SOUL.md"
        ln -sfn "$persona_skin" "$HERMES_HOME/skins/${skin}.yaml"

        export OPENAI_API_KEY=ollama
        export OPENAI_BASE_URL=${endpoint}/v1
        export HERMES_API_TIMEOUT=${toString cfg.requestTimeout}
        export HERMES_STREAM_READ_TIMEOUT=${toString cfg.requestTimeout}
        exec hermes "$@"
      '';
    };
  hermesDurandal = name: model: hermesLauncher name model "durandal" "durandal-marathon";
  hermesSpark = name: model: hermesLauncher name model "guilty-spark" "guilty-spark-forerunner";
  hermesRasputin = name: model: hermesLauncher name model "rasputin" "rasputin-ikelos";
  hermesLocal = hermesDurandal "hermes-local" "local-coder:latest";

  hermesSetup = pkgs.writeShellApplication {
    name = "hermes-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      if [ "''${EUID:-$(id -u)}" -ne 0 ]; then
        exec /run/wrappers/bin/sudo "$0" "$@"
      fi

      hermes_home=/var/lib/hermes/.hermes

      echo "Materializing Hermes persona assets from installed tmpfiles rules..."
      systemd-tmpfiles --create --prefix="$hermes_home"

      required=(
        "$hermes_home/SOUL.md"
        "$hermes_home/personas/durandal/SOUL.md"
        "$hermes_home/personas/guilty-spark/SOUL.md"
        "$hermes_home/personas/rasputin/SOUL.md"
        "$hermes_home/skins/durandal-marathon.yaml"
        "$hermes_home/skins/guilty-spark-forerunner.yaml"
        "$hermes_home/skins/rasputin-ikelos.yaml"
      )

      failed=0
      echo
      for path in "''${required[@]}"; do
        if [ -r "$path" ]; then
          printf '[ OK ] %s -> %s\n' "$path" "$(readlink -f "$path")"
        else
          printf '[FAIL] %s\n' "$path" >&2
          failed=1
        fi
      done

      if [ "$failed" -ne 0 ]; then
        cat >&2 <<'EOF'

Hermes persona setup is incomplete.
The repair command is installed correctly, but the declarative persona tmpfiles
rules are not present in the active NixOS generation.

Update/rebuild the nixos-config generation containing
modules/durandal-hermes-skin.nix, then run hermes-setup again.
EOF
        exit 1
      fi

      echo
      echo "Hermes persona assets are ready."
      echo "Try: spark"
      echo "Try: rasputin"
    '';
  };

  nixai = pkgs.writeShellApplication {
    name = "nixai";
    text = ''
      case "''${1:---help}" in
        -h|--help|help)
          cat <<'EOF'
NIXAI — local AI command reference

MODELS
Alias                          Source                    Context   Tools  Role
local-coder:latest             qwen3.5:9b                262144    yes    Default focused coding/tool model (~6.6 GB)
local-fast:latest              qwen3.5:4b                262144    yes    Faster fallback/small-task model
local-deepseek-coder:latest    deepseek-coder-v2:16b     163840    no     Coding/chat-only MoE model (~8.9 GB)
local-qwen-coder:latest        qwen2.5-coder:14b         32768     yes    Dedicated coding/refactor model (~9.0 GB)
local-starcoder:latest         starcoder2:instruct       16384     no     Coding/chat-only instruct model (~9.1 GB)
local-granite-code:latest      granite-code:8b           131072    no     Lightweight coding/chat-only model (~4.6 GB)
local-gemma4-e2b:latest        gemma4:e2b                131072    yes    Compact Gemma 4 (~7.2 GB)
local-gemma4-e4b:latest        gemma4:e4b                131072    yes    Mid-size Gemma 4 (~9.6 GB)
local-gemma4-12b:latest        gemma4:12b                262144    yes    Gemma 4 12B (~7.6 GB)

MODEL PARAMETERS
num_predict              ${toString cfg.maxTokens}
temperature              0.7
top_p                    0.8
top_k                    20
presence_penalty         1.5
repeat_penalty           1.0
KV cache                 q8_0
Flash attention          enabled
Loaded models            1
Parallel generations     1
Queue limit              4
Keep alive               5m
Gateway                  http://127.0.0.1:11435
Raw Ollama               http://127.0.0.1:11434
Request timeout          ${toString cfg.requestTimeout}s
OpenCode/Hermes max steps 12
Thinking/reasoning       disabled by bounded gateway

OPENCODE PLUGINS (OpenCode 1.x compatible)
opencode-mem                         Persistent local vector memory + profile learning
@nick-vi/opencode-type-inject       TypeScript/Svelte type context and diagnostics
@mohak34/opencode-notifier          Desktop/sound notifications
@prevalentware/opencode-goal-plugin Persistent /goal workflow; bounded to 8 auto turns / 15 min
@tarquinen/opencode-dcp             Dynamic context pruning; loaded last

OPENCODE-MEM SETTINGS
Storage                  ~/.opencode-mem/data
Web UI                   http://127.0.0.1:4747
Auto-capture             enabled
Capture provider         nix-local
Capture model            inherit active tool-capable model
Config                   ~/.config/opencode/opencode-mem.jsonc
Note                     Seeded once; user edits are preserved.

PLUGIN RUNTIME
Desktop notifications    notify-send via libnotify
Goal max auto turns      8
Goal max duration        900s
DCP load order           last
TUI config seed          ~/.config/opencode/tui.json (only if absent)

OPENCODE AGENT ALIASES
opencode-local             Qwen3.5 9B
opencode-local-fast        Qwen3.5 4B
opencode-local-qwen-coder  Qwen2.5-Coder 14B
opencode-local-gemma4-e2b  Gemma 4 E2B
opencode-local-gemma4-e4b  Gemma 4 E4B
opencode-local-gemma4-12b  Gemma 4 12B

OPENCODE BEHAVIOR
Installed by               nix_ai_setup
Provider                   nix-local
Endpoint                   http://127.0.0.1:11435/v1
Provider enforcement       forced by OPENCODE_CONFIG_CONTENT
Project config override    cannot silently switch these launchers to cloud
Build agent max steps      12
Plan agent max steps       12
Task delegation            disabled
Sharing                    disabled
OpenCode autoupdate        disabled; package updates come from Nix
Small model                local-fast:latest / Qwen3.5 4B
Normal opencode command    untouched; keeps normal user providers/config
Plugin suite               enabled on every local OpenCode launcher

Only models with native Ollama tool calling are exposed as OpenCode agents.
DeepSeek Coder V2, StarCoder2, and Granite Code remain available through:
  deepseek-chat
  starcoder-chat
  granite-chat

HERMES — DURANDAL
hermes-coder               Qwen3.5 9B
hermes-fast                Qwen3.5 4B
hermes-qwen-coder          Qwen2.5-Coder 14B
hermes-gemma4-e2b          Gemma 4 E2B
hermes-gemma4-e4b          Gemma 4 E4B
hermes-gemma4-12b          Gemma 4 12B

HERMES — 343 GUILTY SPARK
spark                      Qwen3.5 9B
spark-fast                 Qwen3.5 4B
spark-qwen-coder           Qwen2.5-Coder 14B
spark-gemma4-e2b           Gemma 4 E2B
spark-gemma4-e4b           Gemma 4 E4B
spark-gemma4-12b           Gemma 4 12B

HERMES — RASPUTIN
rasputin                   Qwen3.5 9B
rasputin-fast              Qwen3.5 4B
rasputin-qwen-coder        Qwen2.5-Coder 14B
rasputin-gemma4-e2b        Gemma 4 E2B
rasputin-gemma4-e4b        Gemma 4 E4B
rasputin-gemma4-12b        Gemma 4 12B

DIRECT CHAT / COMPLETION ONLY
deepseek-chat              DeepSeek Coder V2 16B
starcoder-chat             StarCoder2 Instruct
granite-chat               Granite Code 8B

MODEL MANAGEMENT
ollama-get-coder
ollama-get-fast
ollama-get-deepseek-coder
ollama-get-qwen-coder
ollama-get-starcoder
ollama-get-granite-code
ollama-get-gemma4-e2b
ollama-get-gemma4-e4b
ollama-get-gemma4-12b
ollama-get-models           Install all configured models sequentially
ollama list                 Show installed Ollama models
ollama ps                   Show loaded model and GPU residency

PERSONAS
Durandal                    durandal-marathon
343 Guilty Spark            guilty-spark-forerunner
Rasputin                    rasputin-ikelos

HERMES PERSONA SETUP
hermes-setup                Materialize + verify Durandal/Spark/Rasputin assets
hermes-setup-personas       Alias for hermes-setup

COMPATIBILITY HELP ALIASES
hermes-help                 nixai --help
ollama-models               nixai --help
EOF
          ;;
        *)
          echo "Usage: nixai --help" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.services.nix-ai-setup = {
    enable = lib.mkEnableOption "Alpaca and bounded local AI for a 12 GiB AMD GPU";
    contextLength = lib.mkOption {
      type = lib.types.ints.positive;
      default = 262144;
      description = "Maximum Ollama fallback context. Configured local model aliases use their native per-model context windows.";
    };
    maxTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
    };
    requestTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.maxTokens < lib.foldl' lib.min 262144 (builtins.attrValues modelContexts);
        message = "nix-ai-setup: maxTokens must be smaller than the smallest configured model context window.";
      }
    ];
    hardware.graphics.enable = true;
    services.ollama = {
      enable = true;
      package = pkgs.ollama-vulkan;
      host = "127.0.0.1";
      port = 11434;
      openFirewall = false;
      environmentVariables = {
        OLLAMA_VULKAN = "1";
        OLLAMA_CONTEXT_LENGTH = toString cfg.contextLength;
        OLLAMA_NUM_PARALLEL = "1";
        OLLAMA_MAX_LOADED_MODELS = "1";
        OLLAMA_MAX_QUEUE = "4";
        OLLAMA_KEEP_ALIVE = "5m";
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
        OLLAMA_NO_CLOUD = "1";
      };
    };
    environment.systemPackages = [
      pkgs.alpaca
      pkgs.opencode
      pkgs.libnotify
      nixai
      hermesSetup
      hermesLocal
      (hermesDurandal "hermes-local-fast" "local-fast:latest")
      (hermesDurandal "hermes-local-qwen-coder" "local-qwen-coder:latest")
      (hermesDurandal "hermes-local-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesDurandal "hermes-local-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesDurandal "hermes-local-gemma4-12b" "local-gemma4-12b:latest")

      (hermesSpark "hermes-guilty-spark" "local-coder:latest")
      (hermesSpark "hermes-guilty-spark-fast" "local-fast:latest")
      (hermesSpark "hermes-guilty-spark-qwen-coder" "local-qwen-coder:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-12b" "local-gemma4-12b:latest")

      (hermesRasputin "hermes-rasputin" "local-coder:latest")
      (hermesRasputin "hermes-rasputin-fast" "local-fast:latest")
      (hermesRasputin "hermes-rasputin-qwen-coder" "local-qwen-coder:latest")
      (hermesRasputin "hermes-rasputin-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesRasputin "hermes-rasputin-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesRasputin "hermes-rasputin-gemma4-12b" "local-gemma4-12b:latest")
      (openCodeLauncher "opencode-local" "nix-local/local-coder:latest")
      (openCodeLauncher "opencode-local-fast" "nix-local/local-fast:latest")
      (openCodeLauncher "opencode-local-qwen-coder" "nix-local/local-qwen-coder:latest")
      (openCodeLauncher "opencode-local-gemma4-e2b" "nix-local/local-gemma4-e2b:latest")
      (openCodeLauncher "opencode-local-gemma4-e4b" "nix-local/local-gemma4-e4b:latest")
      (openCodeLauncher "opencode-local-gemma4-12b" "nix-local/local-gemma4-12b:latest")
    ];
    environment.etc."nix-ai-setup/hermes.yaml".source = hermesConfig;
    environment.etc."nix-ai-setup/opencode.json".source = openCodeConfig;
    programs.zsh.shellAliases = {
      hermes-setup-personas = "hermes-setup";
      hermes-coder = "hermes-local";
      hermes-fast = "hermes-local-fast";
      hermes-qwen-coder = "hermes-local-qwen-coder";
      hermes-gemma4-e2b = "hermes-local-gemma4-e2b";
      hermes-gemma4-e4b = "hermes-local-gemma4-e4b";
      hermes-gemma4-12b = "hermes-local-gemma4-12b";

      spark = "hermes-guilty-spark";
      spark-fast = "hermes-guilty-spark-fast";
      spark-qwen-coder = "hermes-guilty-spark-qwen-coder";
      spark-gemma4-e2b = "hermes-guilty-spark-gemma4-e2b";
      spark-gemma4-e4b = "hermes-guilty-spark-gemma4-e4b";
      spark-gemma4-12b = "hermes-guilty-spark-gemma4-12b";

      rasputin = "hermes-rasputin";
      rasputin-fast = "hermes-rasputin-fast";
      rasputin-qwen-coder = "hermes-rasputin-qwen-coder";
      rasputin-gemma4-e2b = "hermes-rasputin-gemma4-e2b";
      rasputin-gemma4-e4b = "hermes-rasputin-gemma4-e4b";
      rasputin-gemma4-12b = "hermes-rasputin-gemma4-12b";

      # These models are useful for direct coding/chat, but Ollama does not
      # advertise native tool calling for them, so they are intentionally not
      # exposed through Hermes or OpenCode agent launchers.
      deepseek-chat = "ollama run local-deepseek-coder:latest";
      starcoder-chat = "ollama run local-starcoder:latest";
      granite-chat = "ollama run local-granite-code:latest";
      ollama-models = "nixai --help";
      hermes-help = "nixai --help";
      ollama-get-coder = installModel "local-coder" aliases.local-coder;
      ollama-get-fast = installModel "local-fast" aliases.local-fast;
      ollama-get-deepseek-coder = installModel "local-deepseek-coder" aliases.local-deepseek-coder;
      ollama-get-qwen-coder = installModel "local-qwen-coder" aliases.local-qwen-coder;
      ollama-get-starcoder = installModel "local-starcoder" aliases.local-starcoder;
      ollama-get-granite-code = installModel "local-granite-code" aliases.local-granite-code;
      ollama-get-gemma4-e2b = installModel "local-gemma4-e2b" aliases.local-gemma4-e2b;
      ollama-get-gemma4-e4b = installModel "local-gemma4-e4b" aliases.local-gemma4-e4b;
      ollama-get-gemma4-12b = installModel "local-gemma4-12b" aliases.local-gemma4-12b;
      ollama-get-models = lib.concatStringsSep " && " [
        (installModel "local-coder" aliases.local-coder)
        (installModel "local-fast" aliases.local-fast)
        (installModel "local-deepseek-coder" aliases.local-deepseek-coder)
        (installModel "local-qwen-coder" aliases.local-qwen-coder)
        (installModel "local-starcoder" aliases.local-starcoder)
        (installModel "local-granite-code" aliases.local-granite-code)
        (installModel "local-gemma4-e2b" aliases.local-gemma4-e2b)
        (installModel "local-gemma4-e4b" aliases.local-gemma4-e4b)
        (installModel "local-gemma4-12b" aliases.local-gemma4-12b)
      ];
    };
    systemd.services.nix-ai-gateway = {
      description = "Bounded local AI endpoint for Alpaca and agents";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      requires = [ "ollama.service" ];
      environment = {
        AI_MAX_TOKENS = toString cfg.maxTokens;
        AI_CONTEXT = toString cfg.contextLength;
        AI_TIMEOUT = toString cfg.requestTimeout;
      };
      serviceConfig = {
        ExecStart = "${python}/bin/python ${./gateway.py}";
        Restart = "on-failure";
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
      };
    };
  };
}
