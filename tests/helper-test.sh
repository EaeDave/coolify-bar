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
test "$(jq -r '.running[0].url' <<<"$payload")" = "https://coolify.example.com/project/proj-1/environment/env-1/application/app-stub/deployment/run-stub-1"
test "$(jq -r '.recent[] | select(.id=="fail-agent-1") | .url' <<<"$payload")" = "https://coolify.example.com/project/proj-1/environment/env-1/application/app-agent/deployment/fail-agent-1"
test "$(jq -r '.failures | length' <<<"$payload")" -ge "1"
test "$(jq -r '.failures[0].applicationName' <<<"$payload")" = "PR-Agent"
test "$(jq -r '.sources | length' <<<"$payload")" = "1"

multi="$(
  COOLIFY_FIXTURE_DIR="$fixtures" \
  COOLIFY_SOURCES='[{"id":"personal","name":"Personal","baseUrl":"https://a.example","token":"t"},{"id":"work","name":"Work","baseUrl":"https://b.example","token":"t"}]' \
  "$helper"
)"
test "$(jq -r '.sources | length' <<<"$multi")" = "2"
test "$(jq -r '.running | length' <<<"$multi")" = "2"
test "$(jq -r '[.running[].sourceName] | unique | sort | join(",")' <<<"$multi")" = "Personal,Work"

empty_team="$(
  COOLIFY_FIXTURE_DIR="$root/tests/fixtures-empty-team" \
  COOLIFY_BASE_URL="https://coolify.example.com" \
  COOLIFY_TOKEN="test-token" \
  "$helper"
)"
test "$(jq -r '.state' <<<"$empty_team")" = "ready"
test "$(jq -r '.recent | length' <<<"$empty_team")" = "0"
test "$(jq -r '.warnings | length' <<<"$empty_team")" -ge "1"
[[ "$(jq -r '.message' <<<"$empty_team")" == *"Personal Team"* ]]

echo "helper-test: ok"
