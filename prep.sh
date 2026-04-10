#!/usr/bin/env bash

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

cd "$repo_root"

echo "Updating git submodules..."
git submodule update --init --recursive

export COMMIT_SHA=$(git -C lib/raindex rev-parse HEAD)

echo "Running raindex prep-all.sh..."
cd "$repo_root/lib/raindex"
exec ./prep-all.sh
