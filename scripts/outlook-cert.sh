#!/bin/sh
# Makes the HTTPS certificate SF Desk needs for the Outlook add-in (Outlook only loads add-ins over HTTPS):
# a small certificate authority of your own, and a certificate for "localhost" signed by it, in ./certs.
# Only the authority needs trusting, once:  sh scripts/outlook-cert.sh --trust  (asks for your Mac password).
# The authority can only vouch for localhost and 127.0.0.1 (a name constraint), and its private key is deleted
# once the localhost certificate is signed, so trusting it can't let anyone pass off another site as genuine.
# Uses the openssl that comes with macOS; nothing is downloaded.
set -eu
cd "$(dirname "$0")/.."
DIR="${SF_DESK_CERTS:-certs}"
mkdir -p "$DIR"
chmod 700 "$DIR"

RENEW=""
for a in "$@"; do [ "$a" = "--renew" ] && RENEW=1; done
# A certificate, key or authority that's missing or unreadable (e.g. left empty by an interrupted run) is
# made again, as with --renew.
valid() {
  openssl x509 -in "$DIR/localhost.pem" -noout 2>/dev/null && openssl pkey -in "$DIR/localhost-key.pem" -noout 2>/dev/null &&
    openssl x509 -in "$DIR/sf-desk-ca.pem" -noout 2>/dev/null
}
if [ -f "$DIR/localhost.pem" ] && [ -z "$RENEW" ] && ! valid; then
  echo "$DIR/localhost.pem (or its key or authority) can't be read; making a new one."
  RENEW=1
fi
# An authority made before the name constraint, or whose private key is still here, is replaced.
OLD_CA=""
if [ -f "$DIR/sf-desk-ca.pem" ]; then
  OLD_CA="$(openssl x509 -in "$DIR/sf-desk-ca.pem" -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//; s/://g')"
  if [ -z "$RENEW" ] && { [ -f "$DIR/sf-desk-ca-key.pem" ] || ! openssl x509 -in "$DIR/sf-desk-ca.pem" -noout -ext nameConstraints 2>/dev/null | grep -q localhost; }; then
    echo "The SF Desk certificate authority predates its localhost-only limit; making a new one."
    RENEW=1
  fi
fi

if [ ! -f "$DIR/localhost.pem" ] || [ -n "$RENEW" ]; then
  # Made in a scratch folder and moved in only when complete, so an interrupted run leaves no broken files.
  OUT="$DIR"
  DIR="$(mktemp -d "$OUT/.new.XXXXXX")"
  trap 'rm -rf "$DIR"' EXIT
  cat > "$DIR/leaf.ext" <<'EOF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
EOF
  cat > "$DIR/ca.ext" <<'EOF'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical, permitted;DNS:localhost, permitted;IP:127.0.0.1/255.255.255.255
EOF
  # The authority (valid 10 years) and the localhost certificate (825 days, the most macOS accepts).
  openssl genrsa -out "$DIR/sf-desk-ca-key.pem" 2048 2>/dev/null
  openssl req -new -key "$DIR/sf-desk-ca-key.pem" -subj "/CN=SF Desk local CA/O=SF Desk" -out "$DIR/ca.csr"
  openssl x509 -req -in "$DIR/ca.csr" -signkey "$DIR/sf-desk-ca-key.pem" -days 3650 -sha256 \
    -extfile "$DIR/ca.ext" -out "$DIR/sf-desk-ca.pem" 2>/dev/null
  openssl genrsa -out "$DIR/localhost-key.pem" 2048 2>/dev/null
  openssl req -new -key "$DIR/localhost-key.pem" -subj "/CN=localhost/O=SF Desk" -out "$DIR/localhost.csr"
  openssl x509 -req -in "$DIR/localhost.csr" -CA "$DIR/sf-desk-ca.pem" -CAkey "$DIR/sf-desk-ca-key.pem" \
    -CAcreateserial -days 825 -sha256 -extfile "$DIR/leaf.ext" -out "$DIR/localhost.pem" 2>/dev/null
  # The authority's key isn't needed again (a renewal makes a new authority), so it isn't kept.
  rm -f "$DIR"/*.csr "$DIR"/*.ext "$DIR"/*.srl "$DIR/sf-desk-ca-key.pem"
  chmod 600 "$DIR"/*-key.pem
  valid || { echo "openssl didn't make a usable certificate." >&2; exit 1; }
  for f in sf-desk-ca.pem localhost-key.pem localhost.pem; do mv -f "$DIR/$f" "$OUT/$f"; done
  rm -f "$OUT/sf-desk-ca-key.pem"
  rm -rf "$DIR"; trap - EXIT
  DIR="$OUT"
  echo "Made $DIR/localhost.pem, signed by $DIR/sf-desk-ca.pem."
else
  echo "$DIR/localhost.pem already exists (use --renew to make a new one)."
fi

TRUST=""
for a in "$@"; do [ "$a" = "--trust" ] && TRUST=1; done
if [ -n "$TRUST" ]; then
  # Trust the authority for your user only (login keychain), so Outlook and Safari accept https://localhost.
  # One it replaces is taken out of the keychain first.
  NEW_CA="$(openssl x509 -in "$DIR/sf-desk-ca.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
  if [ -n "$OLD_CA" ] && [ "$OLD_CA" != "$NEW_CA" ]; then
    security delete-certificate -t -Z "$OLD_CA" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 &&
      echo "Removed the old SF Desk certificate authority from your login keychain."
  fi
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$DIR/sf-desk-ca.pem"
  echo "Trusted \"SF Desk local CA\" in your login keychain."
else
  echo "Next: trust it once with   sh scripts/outlook-cert.sh --trust"
fi
echo "Then restart SF Desk; it also listens on https://localhost:${HTTPS_PORT:-3443}."
