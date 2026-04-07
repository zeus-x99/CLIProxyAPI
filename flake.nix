{
  description = "CLIProxyAPI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      rawRef =
        if self ? sourceInfo && self.sourceInfo ? ref then
          self.sourceInfo.ref
        else if self ? ref then
          self.ref
        else
          "";

      tagRef =
        if lib.hasPrefix "refs/tags/" rawRef then
          builtins.substring 10 (builtins.stringLength rawRef - 10) rawRef
        else
          "";

      revision = self.rev or null;
      shortRevision =
        if self ? shortRev then
          self.shortRev
        else if revision != null then
          builtins.substring 0 7 revision
        else
          null;

      version =
        if tagRef != "" then
          lib.removePrefix "v" tagRef
        else if shortRevision != null then
          "unstable-${shortRevision}"
        else
          "dev";

      sourceTimestamp = self.lastModifiedDate or "19700101000000";
      buildDate =
        "${builtins.substring 0 4 sourceTimestamp}-"
        + "${builtins.substring 4 2 sourceTimestamp}-"
        + "${builtins.substring 6 2 sourceTimestamp}T"
        + "${builtins.substring 8 2 sourceTimestamp}:"
        + "${builtins.substring 10 2 sourceTimestamp}:"
        + "${builtins.substring 12 2 sourceTimestamp}Z";

      module = import ./module.nix { inherit self; };
    in
    {
      lib = {
        inherit version buildDate;
        source = builtins.toString self;
        revision = revision;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          cliproxyapi = pkgs.callPackage ./package.nix {
            inherit version buildDate revision;
          };
        in
        {
          inherit cliproxyapi;
          default = cliproxyapi;
        }
      );

      overlays.default = final: prev: {
        cliproxyapi = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };

      nixosModules = {
        default = module;
        cliproxyapi = module;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          evaluated = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              module
              (
                { ... }:
                {
                  services.cliproxyapi = {
                    enable = true;
                    apiKeys = [ "test-key" ];
                  };

                  system.stateVersion = "25.05";
                }
              )
            ];
          };
        in
        {
          package = self.packages.${system}.default;
          module-eval = pkgs.runCommand "cliproxyapi-module-eval" { } ''
            test -n "${evaluated.config.systemd.services.cliproxyapi.serviceConfig.ExecStart}"
            touch "$out"
          '';
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
