#!/usr/bin/env bash
set -euo pipefail

node_version=26.12.1
case "$(uname -m)" in
  x86_64)
    node_arch=x64
    node_sha256=6170b2d474e1c626f43cff3adc118df9fe3b573258a4fc3d850c8dbc6b079bbd
    ;;
  aarch64|arm64)
    node_arch=arm64
    node_sha256=42aa04922591ee5d4dbc7740d452621acf28508239daa512f5ee8c47ee224fdb
    ;;
  *) echo 'Unsupported Node.js architecture.' >&2; exit 1 ;;
esac

node_root="${HOME}/.local/node-${node_version}"
if [[ ! -x "$node_root/bin/node" ]]; then
  node_stage=$(mktemp -d)
  trap 'rm -r -- "$node_stage"' EXIT
  curl --fail --location --silent --show-error \
    "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${node_arch}.tar.xz" \
    --output "$node_stage/node.tar.xz"
  echo "$node_sha256  $node_stage/node.tar.xz" | sha256sum --check --status
  tar -xJf "$node_stage/node.tar.xz" -C "$node_stage"
  mkdir -p "${HOME}/.local"
  mv -- "$node_stage/node-v${node_version}-linux-${node_arch}" "$node_root"
fi
"$node_root/bin/node" --version
