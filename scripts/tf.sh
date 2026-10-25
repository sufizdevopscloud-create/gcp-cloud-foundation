#!/usr/bin/env bash
# Runs Terraform in one stage with the shared variable files and the shared state bucket.
#   scripts/tf.sh 01-hierarchy init|plan|apply|destroy
set -euo pipefail
cd "$(dirname "$0")/.."
stage="${1:?usage: scripts/tf.sh STAGE init|plan|apply|destroy}"; cmd="${2:?usage: scripts/tf.sh STAGE init|plan|apply|destroy}"
cd "$stage"
# Each stage also loads its own terraform.tfvars (if it exists) automatically.
vars=(-var-file=../terraform.tfvars)
[ -f ../generated.tfvars ] && vars+=(-var-file=../generated.tfvars)
case "$cmd" in
  init)    terraform init -backend-config=../backend.hcl ;;
  plan)    terraform plan "${vars[@]}" ;;
  apply)   terraform apply "${vars[@]}" ;;
  destroy) terraform destroy "${vars[@]}" ;;
  *) echo "unknown command: $cmd"; exit 1 ;;
esac
