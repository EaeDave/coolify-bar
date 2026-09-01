#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
notification_log="$tmp/notifications.log"
sound_log="$tmp/sounds.log"

mkdir -p "$tmp/omarchy/bin" "$tmp/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "$COOLIFY_NOTIFICATION_TEST_LOG"' >"$tmp/omarchy/bin/omarchy-notification-send"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "$COOLIFY_SOUND_TEST_LOG"' >"$tmp/bin/pw-play"
chmod +x "$tmp/omarchy/bin/omarchy-notification-send" "$tmp/bin/pw-play"
test_qml="$tmp/NotificationTest.qml"
sed "s|@ROOT@|$root|g" "$root/tests/NotificationTest.qml.in" >"$test_qml"

PATH="$tmp/bin:$PATH" \
OMARCHY_PATH="$tmp/omarchy" \
COOLIFY_NOTIFICATION_TEST_LOG="$notification_log" \
COOLIFY_SOUND_TEST_LOG="$sound_log" \
quickshell --no-color --path "$test_qml"

mapfile -t notifications <"$notification_log"
mapfile -t sounds <"$sound_log"
test "${#notifications[@]}" = "3"

[[ "${notifications[0]}" == *"Deploy in progress"* ]]
[[ "${notifications[1]}" == *"Deploy succeeded"* ]]
[[ "${notifications[2]}" == *"Deploy in progress"* ]]
test "${#sounds[@]}" = "2"
[[ "${sounds[0]}" == *"$root/coolify-notification.wav"* ]]
[[ "${sounds[1]}" == *"$root/coolify-notification.wav"* ]]

echo "notification-test: ok"
