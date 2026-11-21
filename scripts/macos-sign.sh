#!/usr/bin/env bash
# Signs the macOS app with the release certificate, so every release has the
# same signature and macOS keeps the user's keychain "Always Allow" across
# updates. Used by the release workflow.
#
#   MACOS_CERTIFICATE=<base64 .p12> MACOS_CERTIFICATE_PASSWORD=<password> \
#     scripts/macos-sign.sh path/to/Anigen.app
set -euo pipefail

app=$1
entitlements=${ENTITLEMENTS:-macos/Runner/Release.entitlements}
work=$(mktemp -d)
keychain="$work/signing.keychain-db"
search_list=()
search_list_changed=0

cleanup() {
  local status=$?
  if ((search_list_changed)); then
    security list-keychains -d user -s ${search_list[@]+"${search_list[@]}"} || status=1
  fi
  if [[ -e $keychain ]]; then
    security delete-keychain "$keychain" || status=1
  fi
  rm -rf "$work" || status=1
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

keychain_password=$(openssl rand -base64 24)
printf '%s' "$MACOS_CERTIFICATE" | base64 --decode > "$work/cert.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/cert.p12" -k "$keychain" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a prompt
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$keychain_password" "$keychain" >/dev/null
# Capture the command's exit status before changing the search list. Read one
# quoted path per line so paths with spaces survive.
original_search_list=$(security list-keychains -d user)
while IFS= read -r line; do
  line=${line#*\"}
  line=${line%\"*}
  if [[ -n $line ]]; then
    search_list+=("$line")
  fi
done <<< "$original_search_list"
# codesign only searches keychains in the search list
security list-keychains -d user -s "$keychain" ${search_list[@]+"${search_list[@]}"}
search_list_changed=1

# The certificate is self-signed, so it isn't "valid" to macOS; sign by its
# SHA-1 instead of by name
identity=$(security find-certificate -a -Z "$keychain" |
  awk '/SHA-1 hash:/ && !found { print $3; found = 1 }')
if [[ -z $identity ]]; then
  echo "no certificate in MACOS_CERTIFICATE" >&2
  exit 1
fi

# Innermost code first (-depth), then the app itself with its entitlements.
# Symlinks like Versions/Current point at code that's signed anyway.
find "$app/Contents" -depth ! -type l \( -name '*.framework' -o -name '*.dylib' \
  -o -name '*.app' -o -name '*.xpc' -o -name '*.bundle' \) -print0 |
  while IFS= read -r -d '' nested; do
    codesign --force --sign "$identity" --keychain "$keychain" "$nested"
  done
codesign --force --sign "$identity" --keychain "$keychain" \
  --entitlements "$entitlements" "$app"

codesign --verify --deep --strict "$app"
codesign -d -r- "$app"
