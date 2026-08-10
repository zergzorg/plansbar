#!/bin/bash
set -euo pipefail

repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
checker_dir="$repository_dir/.build/fixture-verifier"
checker="$checker_dir/verify-fixtures"

mkdir -p "$checker_dir"
xcrun swiftc -parse-as-library -O \
    "$repository_dir"/Sources/PlansCore/*.swift \
    "$repository_dir/Scripts/verify-fixtures.swift" \
    -o "$checker"

"$checker" "$repository_dir/Tests/PlansCoreTests/Fixtures"
