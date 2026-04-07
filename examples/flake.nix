{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cliproxyapi.url = "github:zeus-x99/CLIProxyAPI";
  };

  outputs =
    {
      nixpkgs,
      cliproxyapi,
      ...
    }:
    {
      nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          cliproxyapi.nixosModules.default
          (
            { ... }:
            {
              services.cliproxyapi = {
                enable = true;
                apiKeyFiles = [ "/run/keys/cliproxyapi-api-key" ];
                settings = {
                  "remote-management" = {
                    "allow-remote" = false;
                  };
                };
                environmentFile = "/run/keys/cliproxyapi.env";
              };

              system.stateVersion = "25.05";
            }
          )
        ];
      };
    };
}
