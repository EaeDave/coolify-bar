#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
helper="$root/omarchy-coolify-fetch"
fixtures="$root/tests/fixtures"

unconfigured="$(COOLIFY_BASE_URL="" COOLIFY_TOKEN="" "$helper")"
test "$(jq -r '.state' <<<"$unconfigured")" = "unconfigured"

payload="$(
  COOLIFY_FIXTURE_DIR="$fixtures" \
  COOLIFY_BASE_URL="https://coolify.example.com" \
  COOLIFY_TOKEN="test-token" \
  "$helper"
)"

test "$(jq -r '.state' <<<"$payload")" = "ready"
test "$(jq -r '.running | length' <<<"$payload")" = "1"
test "$(jq -r '.running[0].statusKind' <<<"$payload")" = "running"
test "$(jq -r '.running[0].commit' <<<"$payload")" = "814be4f"
test "$(jq -r '.failures | length' <<<"$payload")" -ge "1"
test "$(jq -r '.failures[0].applicationName' <<<"$payload")" = "PR-Agent"
test "$(jq -r '.sources | length' <<<"$payload")" = "1"

multi="$(
  COOLIFY_FIXTURE_DIR="$fixtures" \
  COOLIFY_SOURCES='[{"id":"pessoal","name":"Pessoal","baseUrl":"https://a.example","token":"t"},{"id":"empresa","name":"Empresa","baseUrl":"https://b.example","token":"t"}]' \
  "$helper"
)"
test "$(jq -r '.sources | length' <<<"$multi")" = "2"
test "$(jq -r '.running | length' <<<"$multi")" = "2"
test "$(jq -r '[.running[].sourceName] | unique | sort | join(",")' <<<"$multi")" = "Empresa,Pessoal"

echo "helper-test: ok"
