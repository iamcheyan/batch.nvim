#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/parser_spec.lua"
if [[ -f /home/tetsuya/development/night-batch-lab/windows-batch/csv2xls-upload.bat ]]; then
  BATCH_NVIM_FIXTURE=/home/tetsuya/development/night-batch-lab/windows-batch/csv2xls-upload.bat \
    nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/night_batch_spec.lua"
else
  nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/night_batch_spec.lua"
fi
