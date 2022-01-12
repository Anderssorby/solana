{
  description = "Solana";
  inputs = {
    nixpkgs.url = github:nixos/nixpkgs;
    flake-utils = {
      url = github:numtide/flake-utils;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = github:nix-community/naersk;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    utils = {
      url = github:yatima-inc/nix-utils;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.naersk.follows = "naersk";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , utils
    , naersk
    }:
    utils.lib.eachDefaultSystem (system:
    let
      # Contains nixpkgs.lib, flake-utils.lib and custom functions
      lib = utils.lib.${system};
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (lib) buildRustProject testRustProject getRust filterRustProject;
      llvmPackages = pkgs.llvmPackages_13;
      # Load a nightly rust. The hash takes precedence over the date so remember to set it to
      # something like `lib.fakeSha256` when changing the date.
      rustNightly = getRust { date = "2021-12-01"; sha256 = "DhIP1w63/hMbWlgElJGBumEK/ExFWCdLaeBV5F8uWHc="; };
      crateName = "solana";
      root = ./.;
      env = {
        LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib/";
        PROTOC = "${pkgs.protobuf}/bin/protoc";
        ROCKSDB = "${pkgs.rocksdb}/lib/librocksdb.so";
        C_INCLUDE_PATH = lib.concatStringsSep ":"
          [ "${llvmPackages.libclang.lib}/lib/clang/13.0.0/include"
          ];
        PKG_CONFIG_PATH = lib.concatStringsSep ":"
          [ "${pkgs.libudev.dev}/lib/pkgconfig"
            "${pkgs.hidapi}/lib"
            "${pkgs.openssl.out}/lib"
            "${pkgs.openssl.dev}/lib/pkgconfig"
          ];
      };
      # This is a wrapper around naersk build
      # Remember to add Cargo.lock to git for naersk to work
      project = buildRustProject ({
        rust = rustNightly;
        copySources = [ "sdk" "frozen-abi" "transaction-status" "account-decoder" "program-runtime" ];
        inherit root;
        buildInputs = with pkgs;
          [ pkg-config libudev protobuf openssl perl rocksdb llvmPackages.libclang llvmPackages.libclang.dev ];
      } // env);
    in
    {
      packages.${crateName} = project;
      checks.${crateName} = testRustProject { inherit root; };

      defaultPackage = self.packages.${system}.${crateName};

      # To run with `nix run`
      apps.${crateName} = flake-utils.lib.mkApp {
        drv = project;
      };

      # `nix develop`
      devShell = pkgs.mkShell ({
        inputsFrom = builtins.attrValues self.packages.${system};
        nativeBuildInputs = [ rustNightly ];
        buildInputs = with pkgs; [
          libudev
          rust-analyzer
          clippy
          rustfmt
        ];
      } // env);
    });
}
