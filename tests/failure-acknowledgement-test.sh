#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

test_qml="$tmp/FailureAcknowledgementTest.qml"
sed "s|@ROOT@|$root|g" "$root/tests/FailureAcknowledgementTest.qml.in" >"$test_qml"

output="$(quickshell --no-color --path "$test_qml" 2>&1)"
[[ "$output" == *"failure-acknowledgement-test: ok"* ]]
printf '%s\n' 'failure-acknowledgement-test: ok'
