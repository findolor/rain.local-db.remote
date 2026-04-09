{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainlanguage/rainix";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.follows = "rainix/nixpkgs";
  };

  outputs = { self, flake-utils, rainix, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        baseDevShells = rainix.devShells.${system};
        addAwsCli = shell:
          shell.overrideAttrs (old: {
            buildInputs = (old.buildInputs or []) ++ [ pkgs.awscli2 ];
          });

        repoRootSetup = ''
          repo_root="''${LOCAL_DB_REPO_ROOT:-$(pwd -P)}"
        '';

        raindexSetup = ''
          ${repoRootSetup}
          raindex_root="$repo_root/lib/raindex"
          raindex_manifest="$raindex_root/Cargo.toml"

          if [ ! -f "$raindex_manifest" ]; then
            echo "❌ Raindex submodule not found at $raindex_manifest"
            echo "   Run: git submodule update --init --recursive"
            exit 1
          fi
        '';

        envSetup = ''
          env_file="$repo_root/.env"

          load_env_file() {
            if [ "''${LOCAL_DB_ENV_LOADED:-0}" = "1" ]; then
              return 0
            fi

            if [ -f "$env_file" ]; then
              echo "📦 Loading environment variables from $env_file"
              set -a
              # shellcheck disable=SC1090
              source "$env_file"
              set +a
            else
              echo "⚠️  No .env file found at $env_file; relying on current environment"
            fi

            export LOCAL_DB_ENV_LOADED=1
          }
        '';

        shellHelpers = ''
          require_var() {
            local name="$1"
            if [ -z "''${!name:-}" ]; then
              echo "❌ Missing required environment variable: $name"
              exit 1
            fi
          }
        '';

        buildRaindexCliCommand = pkgs.writeShellApplication {
          name = "build-raindex-cli";
          runtimeInputs = with pkgs; [
            cargo
            coreutils
            gmp
            gnused
            gnutar
            openssl
            pkg-config
            rustc
            sqlite
          ];
          text = ''
            set -euo pipefail
            ${raindexSetup}

            export CPATH="${pkgs.gmp.dev}/include''${CPATH:+:$CPATH}"
            export LIBRARY_PATH="${pkgs.gmp}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
            export PKG_CONFIG_PATH="${pkgs.gmp.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
            export RUSTFLAGS="-L native=${pkgs.gmp}/lib ''${RUSTFLAGS:-}"

            target_triple="$(rustc -vV | sed -n 's/^host: //p')"

            case "$target_triple" in
              aarch64-apple-darwin|x86_64-apple-darwin|x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu)
                ;;
              *)
                echo "❌ Unsupported host target: $target_triple"
                exit 1
                ;;
            esac

            output_dir="$repo_root"
            binary_name="rain-orderbook-cli"
            binary_source="$raindex_root/target/$target_triple/release/rain_orderbook_cli"

            echo "Building local raindex CLI artifact..."
            cargo build --release --manifest-path "$raindex_manifest" -p rain_orderbook_cli --target "$target_triple"

            mkdir -p "$output_dir"
            cp "$binary_source" "$output_dir/$binary_name"
            chmod 755 "$output_dir/$binary_name"
            strip "$output_dir/$binary_name" || true

            echo "Setup complete!"
          '';
        };

        localDbSyncCommand = pkgs.writeShellApplication {
          name = "local-db-sync";
          runtimeInputs = with pkgs; [
            coreutils
            curl
          ];
          text = ''
            set -euo pipefail
            ${raindexSetup}
            ${envSetup}
            ${shellHelpers}

            load_env_file

            require_var SETTINGS_YAML_URL
            require_var HYPER_RPC_API_TOKEN
            require_var DUMP_BASE_URL

            dump_base_url="$DUMP_BASE_URL"

            cli_bin="$repo_root/rain-orderbook-cli"
            if [ ! -x "$cli_bin" ]; then
              echo "❌ Local CLI artifact missing at $cli_bin"
              echo "   Run: nix run .#build-raindex-cli"
              exit 1
            fi

            out_root="$repo_root/local-db"

            echo "🌐 Fetching settings YAML from $SETTINGS_YAML_URL"
            settings_yaml="$(curl -fsSL "$SETTINGS_YAML_URL")"

            echo "🚀 Running local-db sync via $cli_bin"
            "$cli_bin" local-db sync \
              --settings-yaml "$settings_yaml" \
              --api-token "$HYPER_RPC_API_TOKEN" \
              --release-base-url "$dump_base_url" \
              --out-root "$out_root" \
              --debug-status
          '';
        };

        localDbUploadCommand = pkgs.writeShellApplication {
          name = "local-db-upload";
          runtimeInputs = with pkgs; [
            awscli2
            coreutils
            findutils
          ];
          text = ''
            set -euo pipefail
            ${repoRootSetup}
            ${envSetup}
            ${shellHelpers}

            load_env_file

            require_var SPACES_ACCESS_KEY
            require_var SPACES_SECRET_KEY
            require_var SPACES_REGION
            require_var SPACES_BUCKET
            require_var SPACES_ENDPOINT

            export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY"
            export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"
            export AWS_DEFAULT_REGION="$SPACES_REGION"

            local_dir="$repo_root/local-db"

            if [ ! -d "$local_dir" ]; then
              echo "❌ Local DB directory not found at $local_dir"
              exit 1
            fi

            echo "🚀 Uploading dump files and manifest from $local_dir to Spaces bucket: $SPACES_BUCKET"
            echo "   Using endpoint: $SPACES_ENDPOINT"
            echo

            if [ -f "$local_dir/manifest.yaml" ]; then
              echo "📄 Uploading manifest.yaml..."
              aws s3 cp "$local_dir/manifest.yaml" "s3://$SPACES_BUCKET/manifest.yaml" \
                --endpoint-url "$SPACES_ENDPOINT" \
                --acl public-read \
                --content-type "text/yaml"
            fi

            echo "🗂️ Uploading SQL dump files (flattened to bucket root)..."
            find "$local_dir" -type f -iname "*-0x*.sql.gz" | while IFS= read -r file; do
              filename="$(basename "$file")"
              echo "→ Uploading: $filename"
              aws s3 cp "$file" "s3://$SPACES_BUCKET/$filename" \
                --endpoint-url "$SPACES_ENDPOINT" \
                --acl public-read \
                --content-type "application/gzip"
            done

            echo
            echo "✅ Upload complete!"
          '';
        };

        localDbCreateEmptyManifestCommand = pkgs.writeShellApplication {
          name = "local-db-create-empty-manifest";
          runtimeInputs = with pkgs; [
            awscli2
            coreutils
            gnused
          ];
          text = ''
            set -euo pipefail
            ${raindexSetup}
            ${envSetup}
            ${shellHelpers}

            load_env_file

            require_var SPACES_ACCESS_KEY
            require_var SPACES_SECRET_KEY
            require_var SPACES_REGION
            require_var SPACES_BUCKET
            require_var SPACES_ENDPOINT

            export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY"
            export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"
            export AWS_DEFAULT_REGION="$SPACES_REGION"

            manifest_schema_file="$raindex_root/crates/settings/src/local_db_manifest.rs"
            if [ ! -f "$manifest_schema_file" ]; then
              echo "❌ Manifest schema file not found at $manifest_schema_file" >&2
              exit 1
            fi

            manifest_version="$(sed -nE 's/^pub const MANIFEST_VERSION: u32 = ([0-9]+);$/\1/p' "$manifest_schema_file")"
            db_schema_version="$(sed -nE 's/^pub const DB_SCHEMA_VERSION: u32 = ([0-9]+);$/\1/p' "$manifest_schema_file")"

            if [ -z "$manifest_version" ] || [ -z "$db_schema_version" ]; then
              echo "❌ Failed to read manifest schema versions from $manifest_schema_file" >&2
              exit 1
            fi

            epoch_ms="$(date +%s%3N)"
            object_key="local-db-manifests/$epoch_ms/manifest.yaml"
            manifest_path="$(mktemp)"
            trap 'rm -f "$manifest_path"' EXIT

            printf 'manifest-version: %s\ndb-schema-version: %s\nnetworks: {}\n' \
              "$manifest_version" \
              "$db_schema_version" >"$manifest_path"

            echo "🚀 Uploading empty local DB manifest to Spaces..." >&2
            echo "   Object key: $object_key" >&2

            aws s3 cp "$manifest_path" "s3://$SPACES_BUCKET/$object_key" \
              --endpoint-url "$SPACES_ENDPOINT" \
              --acl public-read \
              --content-type "text/yaml" >&2

            endpoint_host="${SPACES_ENDPOINT#https://}"
            endpoint_host="${endpoint_host#http://}"
            endpoint_host="${endpoint_host%%/*}"

            if [ -z "$endpoint_host" ]; then
              echo "❌ Failed to derive endpoint host from SPACES_ENDPOINT=$SPACES_ENDPOINT" >&2
              exit 1
            fi

            case "$endpoint_host" in
              "$SPACES_BUCKET".*)
                manifest_url="https://$endpoint_host/$object_key"
                ;;
              *)
                manifest_url="https://$SPACES_BUCKET.$endpoint_host/$object_key"
                ;;
            esac

            echo "✅ Empty manifest uploaded." >&2
            echo "   Manifest URL: $manifest_url" >&2

            printf '%s\n' "$manifest_url"
          '';
        };

      in {
        packages = {
          build-raindex-cli = buildRaindexCliCommand;
          local-db-create-empty-manifest = localDbCreateEmptyManifestCommand;
          local-db-sync = localDbSyncCommand;
          local-db-upload = localDbUploadCommand;
        } // rainix.packages.${system};

        devShells = builtins.mapAttrs (_: addAwsCli) baseDevShells;
      });
}
