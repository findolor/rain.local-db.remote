# rain.local-db.remote

This repository now owns the local DB pipeline through Nix and a local `raindex` submodule instead of downloading a prebuilt CLI artifact.

## Layout

- `lib/raindex`: git submodule containing the upstream Rust CLI and pipeline source
- `flake.nix`: flake entrypoints for building the local CLI, syncing, and uploading

## Setup

Bootstrap the repo and run the upstream raindex prep flow:

```bash
./prep.sh
```

Build the local CLI artifact explicitly. This writes `./rain-orderbook-cli` in the repository root:

```bash
nix run .#build-raindex-cli
```

Copy `.env.example` to `.env`, then fill in the values you need.

## Commands

Run the sync step:

```bash
nix run .#local-db-sync
```

Upload an existing `local-db` directory without re-running sync:

```bash
nix run .#local-db-upload
```

Create and upload an empty remote manifest:

```bash
nix run .#local-db-create-empty-manifest
```

Create and upload an empty remote manifest through GitHub Actions:

- Run `.github/workflows/create-empty-local-db-manifest.yaml`
- The workflow uploads `local-db-manifests/<epoch-ms>/manifest.yaml`
- It calls `nix run .#local-db-create-empty-manifest`
- It returns the public manifest URL in the workflow summary

The source still lives in the local submodule, and you can run it directly from there with:

```bash
nix develop -c cargo run --locked --manifest-path lib/raindex/Cargo.toml -p rain_orderbook_cli -- --help
```
