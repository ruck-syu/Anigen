#!/usr/bin/env bash
# Makes the self-signed certificate the release workflow signs the macOS app
# with. Run it once and keep the output safe: if the certificate changes,
# macOS treats the next release as a different app and asks users for
# keychain access again.
#
#   scripts/macos-signing-cert.sh [output dir]
#
# Then add two repository secrets (Settings → Secrets and variables → Actions):
#   MACOS_CERTIFICATE           contents of anigen-signing.p12.base64
#   MACOS_CERTIFICATE_PASSWORD  contents of password.txt
set -euo pipefail

out=${1:-anigen-signing}
name="Anigen Self-Signed"
umask 077
mkdir -p "$out"
cd "$out"
if [[ -e anigen-signing.p12 || -L anigen-signing.p12 ]]; then
  echo "$out/anigen-signing.p12 already exists; not replacing it" >&2
  exit 1
fi

# Keep the unencrypted key and config in a private directory. Clean it up on
# errors and interrupts without touching files already in the output directory.
work=$(mktemp -d .anigen-signing.XXXXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl rand -base64 24 | tr -d '\n' > "$work/password.txt"
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -sha256 \
  -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

# macOS's importer only reads the older PKCS#12 algorithms
legacy=()
if openssl version | grep -qE '^OpenSSL [3-9]'; then legacy=(-legacy); fi
openssl pkcs12 -export ${legacy[@]+"${legacy[@]}"} -name "$name" \
  -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/anigen-signing.p12" \
  -passout "file:$work/password.txt"
base64 < "$work/anigen-signing.p12" | tr -d '\n' > "$work/anigen-signing.p12.base64"

mv "$work/cert.pem" "$work/password.txt" "$work/anigen-signing.p12.base64" .
mv "$work/anigen-signing.p12" .

echo "Made $out/anigen-signing.p12 (\"$name\", valid 20 years)."
echo "Add these repository secrets, then keep $out somewhere safe and private:"
echo "  MACOS_CERTIFICATE           <- $out/anigen-signing.p12.base64"
echo "  MACOS_CERTIFICATE_PASSWORD  <- $out/password.txt"
