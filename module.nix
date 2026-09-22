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
  hermesConfig = (pkgs.formats.yaml { }).generate "hermes-local.yaml" {
    model = {
      provider = "custom";
      default = "local-coder:latest";
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
  };
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
  hermesLocal = pkgs.writeShellApplication {
    name = "hermes-local";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export HERMES_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-ai-setup/hermes"
      mkdir -p "$HERMES_HOME"
      cp ${hermesConfig} "$HERMES_HOME/config.yaml"
      chmod 600 "$HERMES_HOME/config.yaml"
      export OPENAI_API_KEY=ollama
      export OPENAI_BASE_URL=${endpoint}/v1
      export HERMES_API_TIMEOUT=${toString cfg.requestTimeout}
      export HERMES_STREAM_READ_TIMEOUT=${toString cfg.requestTimeout}
      exec hermes "$@"
    '';
  };
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
      (openCodeLauncher "opencode-local" "nix-local/local-coder:latest")
      (openCodeLauncher "opencode-local-fast" "nix-local/local-fast:latest")
      (openCodeLauncher "opencode-local-deepseek" "nix-local/local-deepseek-coder:latest")
      (openCodeLauncher "opencode-local-qwen-coder" "nix-local/local-qwen-coder:latest")
      (openCodeLauncher "opencode-local-starcoder" "nix-local/local-starcoder:latest")
      (openCodeLauncher "opencode-local-granite" "nix-local/local-granite-code:latest")
    ];
    environment.etc."nix-ai-setup/hermes.yaml".source = hermesConfig;
    environment.etc."nix-ai-setup/opencode.json".source = openCodeConfig;
    programs.zsh.shellAliases = {
      ollama-get-coder = installModel "local-coder" aliases.local-coder;
      ollama-get-fast = installModel "local-fast" aliases.local-fast;
      ollama-get-deepseek-coder = installModel "local-deepseek-coder" aliases.local-deepseek-coder;
      ollama-get-qwen-coder = installModel "local-qwen-coder" aliases.local-qwen-coder;
      ollama-get-starcoder = installModel "local-starcoder" aliases.local-starcoder;
      ollama-get-granite-code = installModel "local-granite-code" aliases.local-granite-code;
      ollama-get-models = lib.concatStringsSep " && " [
        (installModel "local-coder" aliases.local-coder)
        (installModel "local-fast" aliases.local-fast)
        (installModel "local-deepseek-coder" aliases.local-deepseek-coder)
        (installModel "local-qwen-coder" aliases.local-qwen-coder)
        (installModel "local-starcoder" aliases.local-starcoder)
        (installModel "local-granite-code" aliases.local-granite-code)
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
