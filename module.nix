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
  modelfile =
    name: source:
    pkgs.writeText "${name}.Modelfile" ''
      FROM ${source}
      PARAMETER num_ctx ${toString cfg.contextLength}
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
        context_length = cfg.contextLength;
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
      models = lib.genAttrs [
        "local-coder:latest"
        "local-fast:latest"
        "local-deepseek-coder:latest"
        "local-qwen-coder:latest"
        "local-starcoder:latest"
        "local-granite-code:latest"
        "local-gemma4-e2b:latest"
        "local-gemma4-e4b:latest"
        "local-gemma4-12b:latest"
      ] (name: {
        inherit name;
        limit = {
          context = cfg.contextLength;
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
in
{
  options.services.nix-ai-setup = {
    enable = lib.mkEnableOption "Alpaca and bounded local AI for a 12 GiB AMD GPU";
    contextLength = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16384;
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
        assertion = cfg.maxTokens < cfg.contextLength;
        message = "nix-ai-setup: maxTokens must be smaller than contextLength.";
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
      hermesLocal
      (hermesDurandal "hermes-local-fast" "local-fast:latest")
      (hermesDurandal "hermes-local-deepseek" "local-deepseek-coder:latest")
      (hermesDurandal "hermes-local-qwen-coder" "local-qwen-coder:latest")
      (hermesDurandal "hermes-local-starcoder" "local-starcoder:latest")
      (hermesDurandal "hermes-local-granite" "local-granite-code:latest")
      (hermesDurandal "hermes-local-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesDurandal "hermes-local-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesDurandal "hermes-local-gemma4-12b" "local-gemma4-12b:latest")

      (hermesSpark "hermes-guilty-spark" "local-coder:latest")
      (hermesSpark "hermes-guilty-spark-fast" "local-fast:latest")
      (hermesSpark "hermes-guilty-spark-deepseek" "local-deepseek-coder:latest")
      (hermesSpark "hermes-guilty-spark-qwen-coder" "local-qwen-coder:latest")
      (hermesSpark "hermes-guilty-spark-starcoder" "local-starcoder:latest")
      (hermesSpark "hermes-guilty-spark-granite" "local-granite-code:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesSpark "hermes-guilty-spark-gemma4-12b" "local-gemma4-12b:latest")

      (hermesRasputin "hermes-rasputin" "local-coder:latest")
      (hermesRasputin "hermes-rasputin-fast" "local-fast:latest")
      (hermesRasputin "hermes-rasputin-deepseek" "local-deepseek-coder:latest")
      (hermesRasputin "hermes-rasputin-qwen-coder" "local-qwen-coder:latest")
      (hermesRasputin "hermes-rasputin-starcoder" "local-starcoder:latest")
      (hermesRasputin "hermes-rasputin-granite" "local-granite-code:latest")
      (hermesRasputin "hermes-rasputin-gemma4-e2b" "local-gemma4-e2b:latest")
      (hermesRasputin "hermes-rasputin-gemma4-e4b" "local-gemma4-e4b:latest")
      (hermesRasputin "hermes-rasputin-gemma4-12b" "local-gemma4-12b:latest")
      (openCodeLauncher "opencode-local" "nix-local/local-coder:latest")
      (openCodeLauncher "opencode-local-fast" "nix-local/local-fast:latest")
      (openCodeLauncher "opencode-local-deepseek" "nix-local/local-deepseek-coder:latest")
      (openCodeLauncher "opencode-local-qwen-coder" "nix-local/local-qwen-coder:latest")
      (openCodeLauncher "opencode-local-starcoder" "nix-local/local-starcoder:latest")
      (openCodeLauncher "opencode-local-granite" "nix-local/local-granite-code:latest")
      (openCodeLauncher "opencode-local-gemma4-e2b" "nix-local/local-gemma4-e2b:latest")
      (openCodeLauncher "opencode-local-gemma4-e4b" "nix-local/local-gemma4-e4b:latest")
      (openCodeLauncher "opencode-local-gemma4-12b" "nix-local/local-gemma4-12b:latest")
    ];
    environment.etc."nix-ai-setup/hermes.yaml".source = hermesConfig;
    environment.etc."nix-ai-setup/opencode.json".source = openCodeConfig;
    programs.zsh.shellAliases = {
      hermes-coder = "hermes-local";
      hermes-fast = "hermes-local-fast";
      hermes-deepseek = "hermes-local-deepseek";
      hermes-qwen-coder = "hermes-local-qwen-coder";
      hermes-starcoder = "hermes-local-starcoder";
      hermes-granite = "hermes-local-granite";
      hermes-gemma4-e2b = "hermes-local-gemma4-e2b";
      hermes-gemma4-e4b = "hermes-local-gemma4-e4b";
      hermes-gemma4-12b = "hermes-local-gemma4-12b";

      spark = "hermes-guilty-spark";
      spark-fast = "hermes-guilty-spark-fast";
      spark-deepseek = "hermes-guilty-spark-deepseek";
      spark-qwen-coder = "hermes-guilty-spark-qwen-coder";
      spark-starcoder = "hermes-guilty-spark-starcoder";
      spark-granite = "hermes-guilty-spark-granite";
      spark-gemma4-e2b = "hermes-guilty-spark-gemma4-e2b";
      spark-gemma4-e4b = "hermes-guilty-spark-gemma4-e4b";
      spark-gemma4-12b = "hermes-guilty-spark-gemma4-12b";

      rasputin = "hermes-rasputin";
      rasputin-fast = "hermes-rasputin-fast";
      rasputin-deepseek = "hermes-rasputin-deepseek";
      rasputin-qwen-coder = "hermes-rasputin-qwen-coder";
      rasputin-starcoder = "hermes-rasputin-starcoder";
      rasputin-granite = "hermes-rasputin-granite";
      rasputin-gemma4-e2b = "hermes-rasputin-gemma4-e2b";
      rasputin-gemma4-e4b = "hermes-rasputin-gemma4-e4b";
      rasputin-gemma4-12b = "hermes-rasputin-gemma4-12b";
      ollama-models = ''printf '%s\n' "Model alias                     Source                    Role" "local-coder:latest              qwen3.5:9b                Default for focused coding and tool use; approximately 6.6 GB weights" "local-fast:latest               qwen3.5:4b                Faster small tasks and a fallback if 9B is too slow" "local-deepseek-coder:latest     deepseek-coder-v2:16b     Larger coding-focused MoE model; about 8.9 GB" "local-qwen-coder:latest         qwen2.5-coder:14b         Dedicated code model for refactoring, explanation, and generation; about 9.0 GB" "local-starcoder:latest          starcoder2:instruct       Instruct-tuned StarCoder2 for interactive programming; about 9.1 GB" "local-granite-code:latest       granite-code:8b           Lightweight IBM code model; about 4.6 GB" "local-gemma4-e2b:latest         gemma4:e2b                Compact Gemma 4 variant; about 7.2 GB" "local-gemma4-e4b:latest         gemma4:e4b                Mid-size Gemma 4 variant; about 9.6 GB" "local-gemma4-12b:latest         gemma4:12b                Dense Gemma 4 12B model; about 7.6 GB"'';
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
