{
  inputs = {
    nixpkgs.follows = "haskell-nix/nixpkgs";
    flake-utils.follows = "haskell-nix/flake-utils";
    haskell-nix = {
      url = "github:input-output-hk/haskell.nix";
      inputs.hackage.follows = "hackage-nix";
    };
    hackage-nix = {
      url = "github:input-output-hk/hackage.nix";
      flake = false;
    };
    CHaP = {
      url = "github:input-output-hk/cardano-haskell-packages?ref=repo";
      flake = false;
    };
    iohk-nix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, haskell-nix, CHaP, iohk-nix, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ]
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            inherit (haskell-nix) config;
            overlays = [
              haskell-nix.overlay
              iohk-nix.overlays.crypto
            ];
          };

          inherit (pkgs) lib;

          compiler-list = [ "ghc8107" "ghc925" ];

          # TODO revisit when foliage outputs metadata
          chap-package-list =
            let entries = builtins.readDir "${CHaP}/package";
            in builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);

          build-chap-package =
            { compiler-nix-name
            , package-id
            }:

            let
              package-name = (builtins.parseDrvName package-id).name;

              project = pkgs.haskell-nix.cabalProject' {
                inherit compiler-nix-name;
                src = ./empty;

                inputMap = {
                  "https://input-output-hk.github.io/cardano-haskell-packages" = CHaP;
                };

                cabalProject = ''
                  repository cardano-haskell-packages
                    url: https://input-output-hk.github.io/cardano-haskell-packages
                    secure: True

                  extra-packages: ${package-id}
                '';

                modules = [{
                  packages = {
                    cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf pkgs.secp256k1 ] ];
                    cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf pkgs.secp256k1 ] ];
                  };
                }];

              };

            in
            pkgs.releaseTools.aggregate {
              name = package-id;
              constituents = lib.collect lib.isDerivation project.hsPkgs.${package-name}.components;
            };

          all-packages = compiler-nix-name:
            lib.attrsets.mapAttrs' (name: lib.attrsets.nameValuePair (builtins.replaceStrings [ "." ] [ "-" ] name)) (
              lib.attrsets.genAttrs chap-package-list (package-id: build-chap-package { inherit compiler-nix-name package-id; })
            );

        in
        {
          hydraJobs = lib.attrsets.genAttrs compiler-list all-packages;
        });

  nixConfig = {
    allow-import-from-derivation = true;
    extra-substituters = [
      "https://cache.iog.io"
      "https://cache.zw3rk.com"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk="
    ];
  };
}
