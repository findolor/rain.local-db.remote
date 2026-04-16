set -euo pipefail

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

cli_bin="/var/lib/local-db-remote/bin/rain-orderbook-cli"
state_root="/var/lib/local-db-remote/work"
out_root="$state_root/local-db"

cleanup() {
  rm -rf "$out_root"
}

trap cleanup EXIT

require_var SETTINGS_YAML_URL
require_var HYPER_RPC_API_TOKEN
require_var SPACES_ACCESS_KEY
require_var SPACES_SECRET_KEY
require_var SPACES_REGION
require_var SPACES_BUCKET
require_var SPACES_ENDPOINT

if [ ! -x "$cli_bin" ]; then
  echo "CLI binary not found at $cli_bin" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"
export AWS_DEFAULT_REGION="$SPACES_REGION"

# shellcheck disable=SC1090
source "${LOCAL_DB_PUBLISH_TARGET_HELPERS:?missing LOCAL_DB_PUBLISH_TARGET_HELPERS}"

mkdir -p "$state_root"

echo "Fetching settings YAML from $SETTINGS_YAML_URL"
settings_yaml="$(curl -fsSL "$SETTINGS_YAML_URL")"
resolve_publish_target
manifest_object_key="$(object_key_from_url "$manifest_url")"
publish_prefix_key="${manifest_object_key%/*}"

if [ "$publish_prefix_key" = "$manifest_object_key" ]; then
  publish_prefix_key=""
fi

echo "Running local-db sync via $cli_bin"
"$cli_bin" local-db sync \
  --settings-yaml "$settings_yaml" \
  --api-token "$HYPER_RPC_API_TOKEN" \
  --release-base-url "$manifest_dir_url" \
  --out-root "$out_root" \
  --debug-status

if [ ! -d "$out_root" ]; then
  echo "Expected sync output directory at $out_root" >&2
  exit 1
fi

echo "Uploading SQL dump files"
find "$out_root" -type f -iname "*-0x*.sql.gz" | while IFS= read -r file; do
  filename="$(basename "$file")"
  if [ -n "$publish_prefix_key" ]; then
    object_key="$publish_prefix_key/$filename"
  else
    object_key="$filename"
  fi
  echo "Uploading $filename"
  aws s3 cp "$file" "s3://$SPACES_BUCKET/$object_key" \
    --endpoint-url "$SPACES_ENDPOINT" \
    --acl public-read \
    --content-type "application/gzip"
done

if [ -f "$out_root/manifest.yaml" ]; then
  echo "Uploading manifest.yaml to $manifest_url"
  aws s3 cp "$out_root/manifest.yaml" "s3://$SPACES_BUCKET/$manifest_object_key" \
    --endpoint-url "$SPACES_ENDPOINT" \
    --acl public-read \
    --content-type "text/yaml"
fi

echo "Local DB remote sync completed"
