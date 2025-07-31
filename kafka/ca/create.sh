#!/usr/bin/env bash

CWD="$(pwd)"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

set -a
source .env
set +a

NAME=${NAME:-spice}

openssl req -x509 -config "${KAFKA_CA_CONFIG_FILE}" -newkey rsa:4096 -sha256 -nodes -out cacert.pem -outform PEM -subj "/CN=${NAME}"

cd "$CWD"
