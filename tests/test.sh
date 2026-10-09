#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/parser_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/filetype_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/setenv_config_spec.lua"
# The practice fixture is spelled *.BAT, so a hard-coded lowercase path would
# never match and the integration specs would silently skip.  Discover it
# case-insensitively instead.
fixture_dir=/home/tetsuya/development/night-batch-lab/windows-batch
fixture=""
if [[ -d $fixture_dir ]]; then
  for candidate in "$fixture_dir"/*.[bB][aA][tT]; do
    if [[ -f $candidate ]]; then
      fixture=$candidate
      break
    fi
  done
fi

if [[ -n $fixture ]]; then
  BATCH_NVIM_FIXTURE=$fixture \
    nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/night_batch_spec.lua"
  BATCH_NVIM_FIXTURE=$fixture \
    nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/peek_spec.lua"
else
  nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/night_batch_spec.lua"
  nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/peek_spec.lua"
fi
nvim --headless -u NONE -c "set rtp^=$root" -c "set rtp^=/home/tetsuya/.local/share/nvim/lazy/aerial.nvim" -l "$root/tests/aerial_spec.lua"
