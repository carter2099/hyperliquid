#!/usr/bin/env bash
# Regenerate every Python-SDK parity fixture into OUTDIR, using the same relative paths as spec/fixtures/parity/.
#   tools/parity/regenerate.sh OUTDIR
# Venv: $HL_PARITY_VENV (default: <repo>/tmp/parity-venv), created on first use and (re)installed from
# requirements.txt whenever that file changes. Needs python3 and network access on first install.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 OUTDIR" >&2
  exit 64
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
mkdir -p "$1/legacy"
outdir="$(cd "$1" && pwd)"
venv="${HL_PARITY_VENV:-$repo/tmp/parity-venv}"
stamp="$venv/.requirements.sha256"
want="$(sha256sum "$here/requirements.txt" | cut -d' ' -f1)"

if [[ ! -x "$venv/bin/python" ]]; then
  python3 -m venv "$venv"
fi
if [[ "$(cat "$stamp" 2>/dev/null || true)" != "$want" ]]; then
  "$venv/bin/pip" install --quiet --disable-pip-version-check -r "$here/requirements.txt"
  echo "$want" >"$stamp"
fi

cd "$here"
export PYTHONHASHSEED=0 PYTHONDONTWRITEBYTECODE=1

# Machine-readable fixtures consumed by the specs (each script writes its own JSON file under OUTDIR).
for script in \
  capture_l1_signing_vectors.py \
  capture_eip712_user_signed_vectors.py \
  capture_l1_wire_golden.py \
  capture_numerics.py; do
  "$venv/bin/python" "$script" "$outdir"
done

# Legacy capture scripts print their vectors; the transcripts are the audit trail for the literals in the
# specs that cite them. capture_fast_asset_ctxs_frames.py is a live WebSocket probe and is not run here.
for script in \
  capture_multi_sig_signatures.py \
  capture_outcome_deploy_signatures.py \
  capture_perp_deploy_signatures.py \
  capture_send_to_evm_with_data_signatures.py \
  capture_spot_deploy_signatures.py \
  capture_star_signatures.py \
  capture_validator_action_signatures.py; do
  "$venv/bin/python" "$script" >"$outdir/legacy/${script%.py}.txt"
done
