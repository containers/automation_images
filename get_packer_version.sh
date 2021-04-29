

# This script is intended to be executed from the Makefile.
# It allows the .cirrus.yml definition of PACKER_VERSION to
# act as the single source of truth for this value.

cd $(dirname "${BASH_SOURCE[0]}") || exit
YML_LINE=$(grep -Em1 '^\s+PACKER_VERSION:' .cirrus.yml)
VER_VAL=$(awk '{print $3}' <<<"$YML_LINE" | tr -d "\"'[:space:]")
echo -n "$VER_VAL"
