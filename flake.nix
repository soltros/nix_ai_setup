{
  description = "Alpaca and bounded Vulkan local AI for Hermes and coding agents";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      testSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ({ ... }: {
            services.nix-ai-setup.enable = true;
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };
            system.stateVersion = "26.05";
          })
        ];
      };
      openCodeLaunchers = builtins.filter (
        package: nixpkgs.lib.hasPrefix "opencode-local" (nixpkgs.lib.getName package)
      ) testSystem.config.environment.systemPackages;
    in
    {
      nixosModules.default = import ./module.nix;
      packages.${system} = {
        default = pkgs.alpaca;
        alpaca = pkgs.alpaca;
        ollama = pkgs.ollama-vulkan;
        opencode = pkgs.opencode;
      };
      checks.${system} = {
        module = pkgs.writeText "nix-ai-module-check" (
          builtins.unsafeDiscardStringContext testSystem.config.system.build.toplevel.drvPath
        );
        launchers =
          assert builtins.length openCodeLaunchers == 2;
          pkgs.symlinkJoin {
            name = "nix-ai-opencode-launchers-check";
            paths = openCodeLaunchers;
          };
        gateway =
          pkgs.runCommand "nix-ai-gateway-tests"
            {
              nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.aiohttp ])) ];
            }
            ''
              cp ${./gateway.py} gateway.py
              cp ${./test_gateway.py} test_gateway.py
              python -m unittest -v test_gateway
              touch $out
            '';
      };
      formatter.${system} = pkgs.nixfmt;
    };
}
