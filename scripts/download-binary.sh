#!/usr/bin/env bash
set -euo pipefail

# --- Locate project root and .env ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  echo "📦 Loading environment variables from $ENV_FILE"
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# --- Resolve CLI URL ---
if [ -z "${CLI_URL:-}" ]; then
  if [ -z "${ORDERBOOK_CLI_BINARY_URL:-}" ]; then
    echo "❌ Missing ORDERBOOK_CLI_BINARY_URL (and CLI_URL override not provided)"
    exit 1
  fi
  CLI_URL="$ORDERBOOK_CLI_BINARY_URL"
fi

ARCHIVE_PATH="${ARCHIVE_PATH:-$PROJECT_ROOT/rain-orderbook-cli.tar.gz}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT}"

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$OUTPUT_DIR"

echo "⬇️  Downloading $CLI_URL -> $ARCHIVE_PATH"
curl -fsSL "$CLI_URL" -o "$ARCHIVE_PATH"

echo "📦 Extracting archive into $OUTPUT_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$OUTPUT_DIR"

BIN_PATH=$(find "$OUTPUT_DIR" -type f -name rain-orderbook-cli -print -quit)
chmod +x "$BIN_PATH"
echo "✅ Binary ready at $BIN_PATH"
