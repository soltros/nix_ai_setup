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
    local-coder = "qwen3.5:2b";
    local-fast = "qwen3.5:0.8b";
    local-qwen-coder = "qwen2.5-coder:3b";
    local-chat = "gemma3:1b";
  };
  modelContexts = {
    local-coder = 262144;
    local-fast = 262144;
    local-qwen-coder = 32768;
    local-chat = 32768;
  };
  runtimeContexts = {
    # Laptop profile: 8 GiB-class shared-memory system.
    # Hermes requires >=64K, so only the small Qwen3.5 models are exposed there.
    local-coder = 65536;
    local-fast = 65536;
    local-qwen-coder = 32768;
    local-chat = 32768;
  };
  toolCapableModels = [
    "local-coder:latest"
    "local-fast:latest"
    "local-qwen-coder:latest"
  ];

  contextForModel =
    model:
    let
      localName = lib.removeSuffix ":latest" (lib.removePrefix "nix-local/" model);
    in
    runtimeContexts.${localName};
  hermesContextForModel = model: contextForModel model;

  modelfile =
    name: source:
    pkgs.writeText "${name}.Modelfile" ''
      FROM ${source}
      PARAMETER num_ctx ${toString runtimeContexts.${name}}
      PARAMETER num_predict ${toString cfg.maxTokens}
      PARAMETER temperature 0.7
      PARAMETER top_p 0.8
      PARAMETER top_k 20
      PARAMETER presence_penalty 1.5
      PARAMETER repeat_penalty 1.0
    '';
  installModel =
    name: source: "ollama pull ${source} && ollama create ${name} -f ${modelfile name source}";
  ollamaSyncContexts = pkgs.writeShellApplication {
    name = "ollama-sync-contexts";
    runtimeInputs = [ pkgs.ollama-vulkan ];
    text = ''
      set -euo pipefail

      sync_one() {
        local name="$1"
        local source="$2"
        local modelfile="$3"
        local context="$4"

        if ollama show "$name:latest" >/dev/null 2>&1; then
          echo "Retuning $name:latest to runtime context $context..."
          ollama pull "$source"
          ollama create "$name" -f "$modelfile"
        else
          echo "Skipping $name:latest (not installed)"
        fi
      }

      sync_one local-coder qwen3.5:2b ${modelfile "local-coder" aliases.local-coder} 65536
      sync_one local-fast qwen3.5:0.8b ${modelfile "local-fast" aliases.local-fast} 65536
      sync_one local-qwen-coder qwen2.5-coder:3b ${modelfile "local-qwen-coder" aliases.local-qwen-coder} 32768
      sync_one local-chat gemma3:1b ${modelfile "local-chat" aliases.local-chat} 32768

      echo
      echo "Context synchronization complete."
      echo "Load a model, then run: ollama ps"
    '';
  };
  hermesConfigFor =
    name: model: skin:
    (pkgs.formats.yaml { }).generate "${name}.yaml" {
      model = {
        provider = "custom";
        default = model;
        base_url = "${endpoint}/v1";
        api_key = "ollama";
        context_length = hermesContextForModel model;
        ollama_num_ctx = hermesContextForModel model;
        max_tokens = cfg.hermesMaxTokens;
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
      ollamaSyncContexts
    ];
    text = ''
      set -euo pipefail

      if [ "''${EUID:-$(id -u)}" -ne 0 ]; then
        exec /run/wrappers/bin/sudo "$0" "$@"
      fi

      hermes_home=/var/lib/hermes/.hermes

      echo "Installing Hermes persona assets..."

      install -d -m 2770 -o hermes -g hermes "$hermes_home"
      install -d -m 2770 -o hermes -g hermes "$hermes_home/personas"
      install -d -m 2770 -o hermes -g hermes "$hermes_home/personas/durandal"
      install -d -m 2770 -o hermes -g hermes "$hermes_home/personas/guilty-spark"
      install -d -m 2770 -o hermes -g hermes "$hermes_home/personas/rasputin"
      install -d -m 2770 -o hermes -g hermes "$hermes_home/skins"

      install -m 0644 -o hermes -g hermes ${./personas/durandal/SOUL.md} "$hermes_home/personas/durandal/SOUL.md"
      install -m 0644 -o hermes -g hermes ${./personas/guilty-spark/SOUL.md} "$hermes_home/personas/guilty-spark/SOUL.md"
      install -m 0644 -o hermes -g hermes ${./personas/rasputin/SOUL.md} "$hermes_home/personas/rasputin/SOUL.md"

      install -m 0644 -o hermes -g hermes ${./skins/durandal-marathon.yaml} "$hermes_home/skins/durandal-marathon.yaml"
      install -m 0644 -o hermes -g hermes ${./skins/guilty-spark-forerunner.yaml} "$hermes_home/skins/guilty-spark-forerunner.yaml"
      install -m 0644 -o hermes -g hermes ${./skins/rasputin-ikelos.yaml} "$hermes_home/skins/rasputin-ikelos.yaml"

      # Normal Hermes uses Durandal by default.
      cp -f "$hermes_home/personas/durandal/SOUL.md" "$hermes_home/SOUL.md"
      chown hermes:hermes "$hermes_home/SOUL.md"
      chmod 0644 "$hermes_home/SOUL.md"

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
          printf '[ OK ] %s\n' "$path"
        else
          printf '[FAIL] %s\n' "$path" >&2
          failed=1
        fi
      done

      if [ "$failed" -ne 0 ]; then
        echo "Hermes persona setup failed verification." >&2
        exit 1
      fi

      echo
      echo "Synchronizing installed Ollama aliases..."
      ollama-sync-contexts

      echo
      echo "Hermes persona assets are ready."
      echo "Default persona: Durandal"
      echo "Default persona model: Qwen3.5 2B"
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
NIXAI — laptop local AI command reference

TARGET HARDWARE
CPU                      Intel Core i3-1315U
GPU                      Intel UHD integrated / shared memory
System RAM               8 GiB class
Profile                  low-memory, one model at a time

MODELS
Alias                     Source              Native   Runtime  Tools  Role
local-coder:latest        qwen3.5:2b          262144   65536    yes    Default Hermes/OpenCode model (~2.7 GB)
local-fast:latest         qwen3.5:0.8b        262144   65536    yes    Lightweight Hermes/OpenCode model (~1.0 GB)
local-qwen-coder:latest   qwen2.5-coder:3b    32768    32768    yes    Dedicated OpenCode/direct coding model (~1.9 GB)
local-chat:latest         gemma3:1b           32768    32768    no     Tiny direct-chat model (~815 MB)

MODEL PARAMETERS
OpenCode output budget   ${toString cfg.maxTokens}
Hermes output budget     ${toString cfg.hermesMaxTokens}
Gateway output ceiling   ${toString (lib.max cfg.maxTokens cfg.hermesMaxTokens)}
KV cache                 q8_0
Flash attention          enabled
Loaded models            1
Parallel generations     1
Queue limit              2
Keep alive               60s
Gateway                  http://127.0.0.1:11435
Raw Ollama               http://127.0.0.1:11434
Request timeout          ${toString cfg.requestTimeout}s
Thinking/reasoning       disabled by bounded gateway

HERMES
Hermes minimum context   64000
Hermes runtime context   65536
Default model            local-coder:latest / Qwen3.5 2B

durandal                 Qwen3.5 2B
durandal-fast            Qwen3.5 0.8B
spark                    Qwen3.5 2B
spark-fast               Qwen3.5 0.8B
rasputin                 Qwen3.5 2B
rasputin-fast            Qwen3.5 0.8B

OPENCODE
opencode-local            Qwen3.5 2B
opencode-local-fast       Qwen3.5 0.8B
opencode-local-qwen-coder Qwen2.5-Coder 3B

DIRECT CHAT
qwen-coder-chat           Qwen2.5-Coder 3B
gemma-chat                Gemma 3 1B

MODEL MANAGEMENT
ollama-get-coder          Install Qwen3.5 2B
ollama-get-fast           Install Qwen3.5 0.8B
ollama-get-qwen-coder     Install Qwen2.5-Coder 3B
ollama-get-chat           Install Gemma 3 1B
ollama-get-models         Install all laptop models
ollama-sync-contexts      Retune installed aliases to laptop runtime contexts
ollama list               Show installed models
ollama ps                 Show active model / residency

PERSONAS
Durandal                  durandal-marathon
343 Guilty Spark          guilty-spark-forerunner
Rasputin                  rasputin-ikelos

NOTES
Qwen2.5-Coder 3B and Gemma 3 1B are 32K models and are not exposed through Hermes.
The laptop profile intentionally avoids 4B+ defaults to reduce swap pressure on an 8 GiB shared-memory system.

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
    enable = lib.mkEnableOption "bounded local AI for an 8 GiB Intel-UHD laptop";
    contextLength = lib.mkOption {
      type = lib.types.ints.positive;
      default = 65536;
      description = "Ollama fallback runtime context. Tuned local aliases use explicit per-model runtime contexts.";
    };
    maxTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2048;
      description = "Laptop OpenCode/default bounded output-token limit.";
    };
    hermesMaxTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "Laptop Hermes output-token budget.";
    };
    requestTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 240;
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
        OLLAMA_MAX_QUEUE = "2";
        OLLAMA_KEEP_ALIVE = "60s";
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
      ollamaSyncContexts
      hermesSetup
      hermesLocal
      (hermesDurandal "hermes-local-fast" "local-fast:latest")

      (hermesSpark "hermes-guilty-spark" "local-coder:latest")
      (hermesSpark "hermes-guilty-spark-fast" "local-fast:latest")

      (hermesRasputin "hermes-rasputin" "local-coder:latest")
      (hermesRasputin "hermes-rasputin-fast" "local-fast:latest")

      (openCodeLauncher "opencode-local" "nix-local/local-coder:latest")
      (openCodeLauncher "opencode-local-fast" "nix-local/local-fast:latest")
      (openCodeLauncher "opencode-local-qwen-coder" "nix-local/local-qwen-coder:latest")
    ];
    environment.etc."nix-ai-setup/hermes.yaml".source = hermesConfig;
    environment.etc."nix-ai-setup/opencode.json".source = openCodeConfig;
    programs.zsh.shellAliases = {
      hermes-setup-personas = "hermes-setup";
      ollama-sync-model-contexts = "ollama-sync-contexts";

      durandal = "hermes-local";
      durandal-fast = "hermes-local-fast";
      hermes-coder = "hermes-local";
      hermes-fast = "hermes-local-fast";

      spark = "hermes-guilty-spark";
      spark-fast = "hermes-guilty-spark-fast";

      rasputin = "hermes-rasputin";
      rasputin-fast = "hermes-rasputin-fast";

      qwen-coder-chat = "ollama run local-qwen-coder:latest";
      gemma-chat = "ollama run local-chat:latest";

      ollama-models = "nixai --help";
      hermes-help = "nixai --help";

      ollama-get-coder = installModel "local-coder" aliases.local-coder;
      ollama-get-fast = installModel "local-fast" aliases.local-fast;
      ollama-get-qwen-coder = installModel "local-qwen-coder" aliases.local-qwen-coder;
      ollama-get-chat = installModel "local-chat" aliases.local-chat;
      ollama-get-models = lib.concatStringsSep " && " [
        (installModel "local-coder" aliases.local-coder)
        (installModel "local-fast" aliases.local-fast)
        (installModel "local-qwen-coder" aliases.local-qwen-coder)
        (installModel "local-chat" aliases.local-chat)
      ];
    };
    systemd.services.nix-ai-gateway = {
      description = "Bounded local AI endpoint for Alpaca and agents";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      requires = [ "ollama.service" ];
      environment = {
        AI_MAX_TOKENS = toString (lib.max cfg.maxTokens cfg.hermesMaxTokens);
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
