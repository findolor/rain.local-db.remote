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
for var in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ACCOUNT_ID R2_BUCKET; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Missing required environment variable: $var"
    exit 1
  fi
done

aws configure set aws_access_key_id "$R2_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$R2_SECRET_ACCESS_KEY"
aws configure set default.region auto

R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
LOCAL_DIR="$PROJECT_ROOT/local-db"

echo "🚀 Uploading dump files and manifest from $LOCAL_DIR to R2 bucket: $R2_BUCKET"
echo "   Using endpoint: $R2_ENDPOINT"
echo

# --- Upload manifest.yaml if present ---
if [ -f "$LOCAL_DIR/manifest.yaml" ]; then
  echo "📄 Uploading manifest.yaml..."
  aws s3 cp "$LOCAL_DIR/manifest.yaml" "s3://$R2_BUCKET/manifest.yaml" \
    --endpoint-url "$R2_ENDPOINT" \
    --acl public-read
fi

# --- Find and upload matching dump files ---
echo "🗂️ Uploading SQL dump files (flattened to bucket root)..."
find "$LOCAL_DIR" -type f -iname "*-0x*.sql.gz" | while read -r file; do
  filename="$(basename "$file")"
  echo "→ Uploading: $filename"
  aws s3 cp "$file" "s3://$R2_BUCKET/$filename" \
    --endpoint-url "$R2_ENDPOINT" \
    --acl public-read
done

echo
echo "✅ Upload complete!"
