#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /private/tmp/soundshelf-project-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cp Sources/Workspace.swift "$TEST_DIR/Workspace.swift"
cp Tests/auto-basket.swift "$TEST_DIR/main.swift"
swiftc -swift-version 5 -module-cache-path /private/tmp/soundshelf-module-cache "$TEST_DIR/Workspace.swift" "$TEST_DIR/main.swift" -o "$TEST_DIR/run"
"$TEST_DIR/run"
