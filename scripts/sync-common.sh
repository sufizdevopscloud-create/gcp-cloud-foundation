#!/usr/bin/env bash
# Copies variables-common.tf into every stage folder so each stage declares the same shared variables.
set -euo pipefail
cd "$(dirname "$0")/.."
for d in 0*/; do cp variables-common.tf "$d/variables-common.tf"; done
echo "synced variables-common.tf into: $(ls -d 0*/ | tr '\n' ' ')"
