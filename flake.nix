{
  description = "Secure NVMe erase utility";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          tinfoil-wiper = pkgs.callPackage ./package.nix { };
          default = tinfoil-wiper;
        }
      );

      apps = forAllSystems (
        system:
        let
          package = self.packages.${system}.default;
          app = {
            type = "app";
            program = nixpkgs.lib.getExe package;
            meta.description = package.meta.description;
          };
        in
        {
          tinfoil-wiper = app;
          default = app;
        }
      );

      overlays.default = final: _previous: {
        tinfoil-wiper = final.callPackage ./package.nix { };
      };

      nixosModules = rec {
        tinfoil-wiper = import ./nixos-module.nix;
        default = tinfoil-wiper;
      };

      checks = forAllSystems (
        system:
        let
          lib = nixpkgs.lib;
          pkgs = pkgsFor system;
          package = self.packages.${system}.default;
          evaluated = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                programs.tinfoil-wiper.enable = true;
                system.stateVersion = "25.11";
              }
            ];
          };
          modulePackage = evaluated.config.programs.tinfoil-wiper.package;
        in
        {
          inherit package;

          module =
            assert lib.elem modulePackage evaluated.config.environment.systemPackages;
            pkgs.runCommand "tinfoil-wiper-module-check" { nativeBuildInputs = [ modulePackage ]; } ''
              test "$(tinfoil_wiper --version)" = "tinfoil_wiper ${package.version}"
              touch "$out"
            '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          package = self.packages.${system}.default;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = package.runtimeInputs ++ [
              pkgs.bash
              pkgs.gawk
              pkgs.nixfmt-tree
              pkgs.shellcheck
            ];
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
