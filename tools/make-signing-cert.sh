#!/bin/zsh
# Creates a self-signed code signing identity "Unscrew Local Signing" in the login keychain.
# build.sh signs with it when present, so macOS permissions survive rebuilds.
set -e
name="Unscrew Local Signing"
security find-certificate -c "$name" >/dev/null 2>&1 && { echo "$name already exists"; exit 0; }
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
cat > "$dir/cs.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
# System LibreSSL + SHA1/3DES: macOS `security import` cannot read OpenSSL 3's default PKCS12 format.
ssl=/usr/bin/openssl
$ssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cs.cnf" -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
pass=$($ssl rand -hex 12)
$ssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" -out "$dir/id.p12" -passout "pass:$pass"
security import "$dir/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
echo "created $name"
