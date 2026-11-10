#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cargo test --release --manifest-path "$repo/service/Cargo.toml"
cargo clippy --release --manifest-path "$repo/service/Cargo.toml" -- -D warnings
