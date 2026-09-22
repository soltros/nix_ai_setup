# Initial validation

Validated on 2026-09-21, before publishing the initial commit.

- `nix flake check`: NixOS module evaluation and eight gateway tests pass.
- `nix build .#alpaca`: succeeds (Nixpkgs Alpaca 9.2.5, binary cache).
- Vulkan Ollama package builds successfully (0.34.2, binary cache).
- Extending the existing `b450m-d3sh` NixOS configuration with this module and enabling it evaluates its complete system derivation successfully. No existing configuration file was edited and no rebuild was activated.
- Gateway tests cover native thinking suppression, OpenAI reasoning suppression, token-cap bypass attempts, smaller requested limits, tool payload preservation, streaming, HTTP timeouts, and refusal to forward model deletion.
- PCI/sysfs inspection confirms AMD Navi 22, 12 GiB VRAM; CPU/memory inspection confirms Ryzen 5 5600X and approximately 32 GB RAM.

Not yet verified: GPU inference speed or residency, either model's coding quality on this hardware, real inference through the gateway, Alpaca GUI connection, or a complete Hermes/OpenCode coding task. The sandbox had no `/dev/dri` devices. A temporary model download was stopped before completion when the handoff was requested. No model weights are included in Git.

The initial model choices are starting recommendations, not measured optimal settings. Run `bash diagnose.sh` and `python3 smoke.py` after activation and model downloads to begin triage.
