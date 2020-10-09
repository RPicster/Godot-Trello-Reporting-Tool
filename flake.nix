{
  description = "Godot - Trello Reporting Tool";

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;
    systems = [ "x86_64-linux" ];
  in {
    packages = lib.genAttrs systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      mkGodotGut = isHeadless: let
        godot = if isHeadless then pkgs.godot-headless else pkgs.godot;
        godotCmd = if isHeadless then "godot-headless" else "godot";

        gutSrc = pkgs.stdenv.mkDerivation {
          pname = "gut";
          version = "7.0.0";

          src = pkgs.fetchFromGitHub {
            owner = "bitwes";
            repo = "Gut";
            rev = "v7.0.0";
            sha256 = "0zjz33hxay2w3qbgv7x24izcm93bj0f6x4mayxzz10kl0aa6w9rq";
          };

          postPatch = ''
            sed -i -e 's!res://addons/gut/fonts!'"$out/addons/gut/fonts"'!' \
              addons/gut/GutScene.gd
          '';

          installPhase = "cp -r . \"$out\"";
        };

        godotGut = godot.overrideAttrs (drv: {
          inherit gutSrc;

          sconsFlags = (drv.sconsFlags or "")
                     + " system_certs_path=/etc/ssl/certs/ca-certificates.crt";

          postPatch = (drv.postPatch or "") + ''
            # Use system certs if user did not override project settings.
            #
            # This essentially implements the patch from OpenSUSE at
            # https://bit.ly/2SKeYfi but without conflicts.
            #
            # The issue is tracked upstream at:
            # https://github.com/godotengine/godot/issues/22232
            sed -i -e '/^#include/ {
              a #include <string.h>
              :l; n
              /#ifdef BUILTIN_CERTS_ENABLED/ {
                i else if (strcmp(_SYSTEM_CERTS_PATH, "") != 0) \
                  default_certs->load(_SYSTEM_CERTS_PATH);
              }
              bl
            }' modules/mbedtls/crypto_mbedtls.cpp

            # Godot only has a single base path, where all resources are loaded
            # from. We could just copy over Gut into the source tree, but this
            # would also mean that we need to keep it updated and prevent
            # people from staging it in Git.
            #
            # Fortunately, there is an undocumented way to do path remapping,
            # but it relies on the path_remap/remapped_paths setting for the
            # project.
            #
            # So instead, we just patch the function that is responsible for
            # loading the path remaps and inject all files from Gat.
            find "$gutSrc" -path '*/addons/gut/*' \
              -printf 'path_remaps["res://%P"] = "%p";\n' \
              > core/io/path-remaps.h

            sed -i -e '/ResourceLoader::load_path_remaps.*{/ {
              a #include "path-remaps.h"
            }' core/io/resource_loader.cpp
          '';
        });
      in pkgs.writeScriptBin "godot-gut" ''
        #!${pkgs.stdenv.shell}
        exec ${godotGut}/bin/${godotCmd} --path "$PWD" \
          -s "${gutSrc}/addons/gut/gut_cmdln.gd" "$@"
      '';

    in {
      godot-gut = mkGodotGut false;
      godot-gut-headless = mkGodotGut true;

      godot-trello-reporting = pkgs.writeScriptBin "godot-trello-reporting" ''
        #!${pkgs.stdenv.shell}
        exec ${pkgs.godot}/bin/godot \
          ${lib.escapeShellArg "${self}/Trello_Reporting_Tool.tscn"} \
          "$@"
      '';
    });

    checks = lib.genAttrs systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.packages.${system}) godot-gut-headless;

      testRunner = pkgs.writeScriptBin "test-runner" ''
        #!${pkgs.stdenv.shell} -e
        cd ${lib.escapeShellArg self}
        exec ${godot-gut-headless}/bin/godot-gut -gtest=res://test.gd -gexit
      '';

    in {
      integration = import (nixpkgs + "/nixos/tests/make-test-python.nix") {
        name = "godot-trello-reporting";

        nodes = {
          client.environment.systemPackages = lib.singleton testRunner;
        };

        testScript = ''
          # fmt: off
          client.wait_for_unit('multi-user.target')
          client.succeed('test-runner')
        '';
      } { inherit system; };
    });

    defaultPackage = let
      getPackage = system: self.packages.${system}.godot-trello-reporting;
    in lib.genAttrs systems getPackage;

    devShell = lib.genAttrs systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.mkShell {
      nativeBuildInputs = [ pkgs.godot self.packages.${system}.godot-gut ];
    });
  };
}
