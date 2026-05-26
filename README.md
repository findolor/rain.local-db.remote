# rain.local-db.remote

This repository now owns the local DB pipeline through Nix and a local `raindex` submodule instead of downloading a prebuilt CLI artifact. It also contains the Terraform, NixOS, and GitHub workflow pieces needed to deploy the remote sync host.

## Layout

- `lib/raindex`: git submodule containing the upstream Rust CLI and pipeline source
- `flake.nix`: flake entrypoints for building the local CLI, syncing, and uploading
- `infra/`: Terraform configuration and helper tasks for the deployment host
- `os.nix`: NixOS definition for the deployed sync machine
- `.github/workflows/deploy.yaml`: manual deployment workflow
- `.github/workflows/list-deployments.yaml`: manual deployment status workflow
- `.github/workflows/provision-host.yaml`: manual provisioning workflow
- `.github/workflows/sunset-deployment.yaml`: manual deployment sunset workflow

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

## Deployment

Provision infrastructure:

```bash
nix run .#tf-edit-vars
nix run .#tf-init
nix run .#tf-plan
nix run .#tf-apply
```

Bootstrap the fresh host to NixOS:

```bash
nix run .#bootstrap-nixos
```

Or do the same from GitHub Actions:

- Run `.github/workflows/provision-host.yaml`
- Run it from `main`
- Set `bootstrap_nixos=true` only when you want to install or reinstall NixOS on the droplet
- Re-running the workflow without `bootstrap_nixos` is safe for normal Terraform reconciliation
- Re-running with `bootstrap_nixos=true` is not a no-op; it will re-bootstrap the machine

Resolve the currently provisioned host:

```bash
nix run .#resolve-ip
```

Deploy the latest code and runtime config through GitHub Actions:

- Run `.github/workflows/deploy.yaml`
- Provide the `deployment_id` and `settings_url` inputs
- The workflow runs `./prep.sh`, builds `./rain-orderbook-cli`, deploys the host config, uploads the binary and runtime env file for that deployment, and starts `local-db-sync@<deployment_id>.service`
- Each deployed instance runs `local-db-sync@<deployment_id>.timer` every five minutes with no overlapping runs for the same deployment
- Different deployment IDs can run side by side on the same host

Deployment IDs must contain only letters, numbers, dots, underscores, and dashes.
The settings YAML remains responsible for selecting the manifest URL that the deployment publishes.

List active deployments through GitHub Actions:

- Run `.github/workflows/list-deployments.yaml`
- The workflow reports each deployment ID, timer status, service status, settings URL, last service start, next timer run, and work directory size

Sunset a deployment through GitHub Actions:

- Run `.github/workflows/sunset-deployment.yaml`
- Provide the `deployment_id` input
- Leave `delete_state=false` to stop and disable the deployment while keeping its env, binary, and work directory for rollback
- Set `delete_state=true` only when you want to remove that deployment's host-side state
