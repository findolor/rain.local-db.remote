{ pkgs, ragenix, rainix, system }:

let
  buildInputs =
    [ pkgs.terraform pkgs.rage pkgs.jq ragenix.packages.${system}.default ];

  tfState = "infra/terraform.tfstate";
  tfVars = "infra/terraform.tfvars";
  tfPlanFile = "infra/tfplan";

  parseIdentity = ''
    set -eo pipefail

    identity=~/.ssh/id_ed25519
    if [ "''${1:-}" = "-i" ]; then
      identity="$2"
      shift 2
    fi
  '';

  decryptState = ''
    if [ -f ${tfState}.age ]; then
      rage -d -i "$identity" ${tfState}.age > ${tfState}
    fi
  '';

  encryptState = ''
    if [ -f ${tfState} ]; then
      nix eval --raw --file ${
        ../keys.nix
      } roles.ssh --apply 'builtins.concatStringsSep "\n"' \
        | rage -e -R /dev/stdin -o ${tfState}.age ${tfState}
    fi
  '';

  cleanup = "rm -f ${tfState} ${tfState}.backup ${tfVars}";
  cleanupWithPlan = "${cleanup} ${tfPlanFile}";

  decryptVars = ''
    if [ -f ${tfVars}.age ]; then
      rage -d -i "$identity" ${tfVars}.age > ${tfVars}
    else
      cp ${tfVars}.example ${tfVars}
    fi
  '';

  encryptVars = ''
    nix eval --raw --file ${
      ../keys.nix
    } roles.infra --apply 'builtins.concatStringsSep "\n"' \
      | rage -e -R /dev/stdin -o ${tfVars}.age ${tfVars}
  '';

  preamble = ''
    ${parseIdentity}
    on_exit() { ${cleanup}; }
    trap on_exit EXIT
    ${decryptVars}
  '';

  preambleWithEncrypt = ''
    ${parseIdentity}
    on_exit() {
      ${encryptState}
      ${cleanupWithPlan}
    }
    trap on_exit EXIT
    ${decryptVars}
  '';

  resolveIp = ''
    ${parseIdentity}
    trap 'rm -f ${tfState}' EXIT
    ${decryptState}

    if [ ! -f ${tfState} ]; then
      echo "Terraform state not found. Run tf-apply first." >&2
      exit 1
    fi

    host_ip=$(jq -r '.outputs.reserved_ip.value // .outputs.droplet_ipv4.value // empty' ${tfState})
    if [ -z "$host_ip" ]; then
      echo "Failed to resolve host IP from Terraform state." >&2
      exit 1
    fi
  '';

  tfRekey = ''
    ${parseIdentity}
    on_exit() { ${cleanup}; }
    trap on_exit EXIT
    ${decryptState}
    ${encryptState}
    ${decryptVars}
    ${encryptVars}
  '';
in {
  inherit buildInputs parseIdentity resolveIp tfRekey;

  tfInit = rainix.mkTask.${system} {
    name = "tf-init";
    additionalBuildInputs = buildInputs;
    body = ''
      ${preamble}
      terraform -chdir=infra init "$@"
    '';
  };

  tfPlan = rainix.mkTask.${system} {
    name = "tf-plan";
    additionalBuildInputs = buildInputs;
    body = ''
      ${preamble}
      ${decryptState}
      terraform -chdir=infra plan -out=tfplan "$@"
    '';
  };

  tfApply = rainix.mkTask.${system} {
    name = "tf-apply";
    additionalBuildInputs = buildInputs;
    body = ''
      ${preambleWithEncrypt}
      ${decryptState}
      terraform -chdir=infra apply "$@" tfplan
    '';
  };

  tfDestroy = rainix.mkTask.${system} {
    name = "tf-destroy";
    additionalBuildInputs = buildInputs;
    body = ''
      ${preambleWithEncrypt}
      ${decryptState}
      terraform -chdir=infra destroy "$@"
    '';
  };

  tfEditVars = rainix.mkTask.${system} {
    name = "tf-edit-vars";
    additionalBuildInputs = buildInputs;
    body = ''
      ${parseIdentity}
      on_exit() { rm -f ${tfVars}; }
      trap on_exit EXIT

      ${decryptVars}
      ''${EDITOR:-vi} ${tfVars}
      ${encryptVars}
    '';
  };
}
