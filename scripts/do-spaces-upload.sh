#!/usr/bin/env bash
set -euo pipefail

# --- Locate project root and .env ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/.env" ]; then
  echo "📦 Loading environment variables from $PROJECT_ROOT/.env"
  export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

# --- Validate required vars ---
for var in SPACES_ACCESS_KEY SPACES_SECRET_KEY SPACES_REGION SPACES_BUCKET SPACES_ENDPOINT; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Missing required environment variable: $var"
    exit 1
  fi
done

# --- Configure AWS CLI for DigitalOcean Spaces ---
aws configure set aws_access_key_id "$SPACES_ACCESS_KEY"
aws configure set aws_secret_access_key "$SPACES_SECRET_KEY"
aws configure set default.region "$SPACES_REGION"

LOCAL_DIR="$PROJECT_ROOT/local-db"

echo "🚀 Uploading dump files and manifest from $LOCAL_DIR to Spaces bucket: $SPACES_BUCKET"
echo "   Using endpoint: $SPACES_ENDPOINT"
echo

# --- Upload manifest.yaml if present ---
if [ -f "$LOCAL_DIR/manifest.yaml" ]; then
  echo "📄 Uploading manifest.yaml..."
  aws s3 cp "$LOCAL_DIR/manifest.yaml" "s3://$SPACES_BUCKET/manifest.yaml" \
    --endpoint-url "$SPACES_ENDPOINT" \
    --acl public-read \
    --content-type "text/yaml"
fi

# --- Find and upload matching dump files ---
echo "🗂️ Uploading SQL dump files (flattened to bucket root)..."
find "$LOCAL_DIR" -type f -iname "*-0x*.sql.gz" | while read -r file; do
  filename="$(basename "$file")"
  echo "→ Uploading: $filename"
  aws s3 cp "$file" "s3://$SPACES_BUCKET/$filename" \
    --endpoint-url "$SPACES_ENDPOINT" \
    --acl public-read \
    --content-type "application/gzip"
done

echo
echo "✅ Upload complete!"
