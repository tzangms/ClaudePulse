#!/bin/bash
# Regenerates ClaudePulse.xcodeproj from project.yml.
# The project is generated, not committed — edit project.yml, never the project.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "==> Open with: open ClaudePulse.xcodeproj"
