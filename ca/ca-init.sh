#/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

. ./envars.sh

CA_COMMON_NAME=${CA_COMMON_NAME:-'CA'}
CN="${1:-$CA_COMMON_NAME}"

echo "🛈  CN=${CN}"

./ca.sh openssl req -x509 -newkey rsa:4096 -sha256 -nodes -out cacert.pem -outform PEM -subj "/CN=${CN}"
