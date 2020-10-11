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

      minitrello = pkgs.runCommand "minitrello" rec {
        uwsgi = pkgs.uwsgi.override {
          plugins = [ "python3" ];
          withPAM = false;
          withSystemd = true;
        };
        nativeBuildInputs = [
          pkgs.python3Packages.flake8
          pkgs.python3Packages.mypy
        ];
        python3 = pkgs.python3.withPackages (p: lib.singleton p.flask);
        src = ./minitrello.py;
        cmdArgs = lib.escapeShellArgs [
          "${uwsgi}/bin/uwsgi" "--die-on-term" "--auto-procname"
          "--procname-prefix-spaced=[minitrello]"
          "--plugins" "python3" "--callable=app" "--enable-threads"
          "--pythonpath" "${python3}/${python3.sitePackages}"
        ];
      } ''
        flake8 "$src"
        mypy "$src"
        install -vD -m 0644 "$src" "$out/libexec/minitrello.py"
        mkdir -p "$out/bin"
        { echo ${lib.escapeShellArg "#!${pkgs.stdenv.shell}"}
          echo exec "$cmdArgs" --mount "=$out/libexec/minitrello.py" \
                               --http 127.0.0.1:4444
        } > "$out/bin/minitrello"
        chmod +x "$out/bin/minitrello"
      '';

      trello-reporting = pkgs.writeScriptBin "godot-trello-reporting" ''
        #!${pkgs.stdenv.shell}
        exec ${pkgs.godot}/bin/godot \
          ${lib.escapeShellArg "${self}/Trello_Reporting_Tool.tscn"} \
          "$@"
      '';

      proxy = pkgs.runCommand "godot-trello-proxy" {
        src = ./proxy.php;
        nativeBuildInputs = [ pkgs.php ];
        cmdArgs = lib.escapeShellArgs [
          "${pkgs.php}/bin/php"
          "-d" "error_reporting=E_ALL"
          "-d" "display_errors=Off"
          "-d" "log_errors=On"
          "-S" "127.0.0.1:3333"
          "-t" "${placeholder "out"}/libexec/godot-trello-proxy"
        ];
      } ''
        php -l "$src"
        install -vD -m 0644 "$src" "$out/libexec/godot-trello-proxy/proxy.php"
        mkdir -p "$out/bin"
        { echo ${lib.escapeShellArg "#!${pkgs.stdenv.shell}"}
          echo exec "$cmdArgs" '"$@"'
        } > "$out/bin/godot-trello-proxy"
        chmod +x "$out/bin/godot-trello-proxy"
      '';
    });

    checks = lib.genAttrs systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.packages.${system}) godot-gut;

      testRunner = pkgs.writeScriptBin "test-runner" ''
        #!${pkgs.stdenv.shell} -e
        cd ${lib.escapeShellArg self}
        exec ${godot-gut}/bin/godot-gut -gtest=res://test.gd -gexit
      '';

      mkSnakeoilCert = domain: pkgs.runCommand "snakeoil-cert" {
        nativeBuildInputs = [ pkgs.openssl ];
        OPENSSL_CONF = pkgs.writeText "snakeoil.cnf" ''
          [req]
          default_bits = 4096
          prompt = no
          default_md = sha256
          req_extensions = req_ext
          distinguished_name = dn
          [dn]
          CN = ${domain}
          [req_ext]
          subjectAltName = DNS:${domain}
        '';
      } ''
        mkdir -p "$out"
        openssl req -x509 -newkey rsa:2048 -nodes -keyout "$out/key.pem" \
        -out "$out/cert.pem" -days 36500
      '';

      certs.proxy = mkSnakeoilCert "proxy.example";
      certs.trello = mkSnakeoilCert "api.trello.com";

      commonConfig = { config, nodes, ... }: {
        networking.firewall.enable = false;
        networking.nameservers = lib.mkForce [
          nodes.resolver.config.networking.primaryIPAddress
        ];
        security.pki.certificateFiles = let
          getPubkey = drv: "${drv}/cert.pem";
        in lib.mapAttrsToList (lib.const getPubkey) certs;
        networking.extraHosts = let
          allVhosts = config.services.httpd.virtualHosts
                   // config.services.nginx.virtualHosts;
        in lib.concatMapStrings (domain: ''
          127.0.0.1 ${domain}
          ${config.networking.primaryIPAddress} ${domain}
        '') (lib.attrNames allVhosts);
      };

    in {
      integration = import (nixpkgs + "/nixos/tests/make-test-python.nix") {
        name = "godot-trello-reporting";

        nodes.resolver = nixpkgs + "/nixos/tests/common/resolver.nix";

        nodes.client = {
          imports = [ commonConfig (nixpkgs + "/nixos/tests/common/x11.nix") ];
          hardware.opengl.driSupport = true;
          virtualisation.memorySize = 1024;
          environment.systemPackages = lib.singleton testRunner;
          boot.kernelModules = [ "snd-dummy" ];
          sound.enable = true;
        };

        nodes.proxy = { config, ... }: {
          imports = [ commonConfig ];
          services.httpd.enable = true;
          services.httpd.enablePHP = true;
          services.httpd.adminAddr = "admin@proxy.example";
          services.httpd.virtualHosts."proxy.example" = {
            forceSSL = true;
            enableACME = false;
            sslServerCert = "${certs.proxy}/cert.pem";
            sslServerKey = "${certs.proxy}/key.pem";
            documentRoot = pkgs.runCommand "docroot" {
              src = let
                inherit (self.packages.${config.nixpkgs.system}) proxy;
              in "${proxy}/libexec/godot-trello-proxy/proxy.php";
              YOUR_TRELLO_API_KEY = "6686ab7c98c9478a858c7509cce4e567";
              YOUR_TRELLO_API_TOKEN = "903a96bcb0f2457986ed6f4e4d4d5016"
                                    + "04ea488a45034e57aea56a16ed59528a";
              YOUR_TRELLO_LIST_ID = "44b3a1b2db65488e8ba5a9df";
            } ''
              mkdir "$out"
              substitute "$src" "$out/proxy.php" \
                --subst-var YOUR_TRELLO_API_KEY \
                --subst-var YOUR_TRELLO_API_TOKEN \
                --subst-var YOUR_TRELLO_LIST_ID
            '';
          };
        };

        nodes.trello = { config, pkgs, ... }: {
          imports = [ commonConfig ];
          services.nginx.enable = true;
          services.nginx.virtualHosts."api.trello.com" = {
            forceSSL = true;
            enableACME = false;
            sslCertificate = "${certs.trello}/cert.pem";
            sslCertificateKey = "${certs.trello}/key.pem";
            locations."/".extraConfig = ''
              include ${config.services.nginx.package}/conf/uwsgi_params;
              uwsgi_intercept_errors on;
              uwsgi_ignore_client_abort on;
              uwsgi_pass unix:///run/minitrello.socket;
            '';
          };

          systemd.sockets.minitrello = {
            description = "Socket for minimal Trello API Server";
            wantedBy = [ "sockets.target" ];
            socketConfig.ListenStream = "/run/minitrello.socket";
            socketConfig.SocketUser = "root";
            socketConfig.SocketGroup = "nginx";
            socketConfig.SocketMode = "0660";
          };

          systemd.services.minitrello = {
            description = "Minimal Trello API Server";
            requiredBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            serviceConfig.Type = "notify";
            serviceConfig.DynamicUser = true;
            serviceConfig.ExecStart = let
              inherit (self.packages.${config.nixpkgs.system}) minitrello;
              extraArgs = lib.escapeShellArgs [
                "--mount" "=${minitrello}/libexec/minitrello.py"
                "--socket" "/run/minitrello.socket"
              ];
            in "${minitrello.cmdArgs} ${extraArgs}";
          };
        };

        testScript = ''
          # fmt: off
          start_all()
          resolver.wait_for_unit('bind.service')
          trello.wait_for_unit('nginx.service')
          trello.wait_for_open_port(443)
          proxy.wait_for_unit('httpd.service')
          proxy.wait_for_open_port(443)
          client.wait_for_x()

          client.succeed('ping -c1 proxy.example >&2')
          proxy.succeed('ping -c1 api.trello.com >&2')

          client.succeed('test-runner >&2')
        '';
      } { inherit system; };
    });

    defaultPackage = let
      getPackage = system: self.packages.${system}.trello-reporting;
    in lib.genAttrs systems getPackage;

    devShell = lib.genAttrs systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.godot
        self.packages.${system}.godot-gut
        self.packages.${system}.proxy
      ];
    });

    hydraJobs = {
      tests = self.checks.x86_64-linux;
      packages = removeAttrs self.packages.x86_64-linux [
        "godot-gut" "godot-gut-headless"
      ];
    };
  };
}
