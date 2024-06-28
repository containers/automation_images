#!/bin/bash
#
# 2024-01-25 esm
# 2024-06-28 cevich
#
# This script is intended to be used by the `pre-commit` utility, or it may
# be manually copied (or symlinked) as local `.git/hooks/pre-push` file.
# It's purpose is to keep track of image-suffix values which have already
# been pushed, to avoid them being immediately rejected by CI validation.
# To use it with the `pre-commit` utility, simply add something like this
# to your `.pre-commit-config.yaml`:
#
# ---
# repos:
#   - repo: https://github.com/containers/automation_images.git
#     rev: <tag or commit sha>
#     hooks:
#       - id: check-imgsfx

set -eo pipefail

# Ensure CWD is the repo root
cd $(dirname "${BASH_SOURCE[0]}")
imgsfx=$(<IMG_SFX)

imgsfx_history=".git/hooks/imgsfx.history"

if [[ -e $imgsfx_history ]]; then
    if grep -q "$imgsfx" $imgsfx_history; then
        echo "FATAL: $imgsfx has already been used" >&2
        echo "Please rerun 'make IMG_SFX'" >&2
        exit 1
    fi
fi

echo $imgsfx >>$imgsfx_history
