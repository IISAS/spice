#!/usr/bin/env bash

CWD="$(pwd)"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

set -a
source ../.env
source .env
set +a

KAFKA_HOME=${SCRIPT_DIR}

CLIENTS_HOME="${KAFKA_HOME}/clients"
CA_HOME="$(realpath -s "${KAFKA_HOME}/ca")"
export CA_HOME=${CA_HOME}
KAFKA_CA_CONFIG_FILE="${CA_HOME}/${KAFKA_CA_CONFIG_FILE}"
echo "KAFKA_CA_CONFIG_FILE: ${KAFKA_CA_CONFIG_FILE}"
ca_cert_file="${CA_HOME}/cacert.pem"


###############################################################################

function rmdir_if_empty() {
  dir=$1
  if [ ! -d "$dir" ]; then
    return
  fi  
  if [ -z "$(find "$dir" -mindepth 1 -maxdepth 1)" ]; then
    rmdir -v $dir
  else
    echo "❌ $dir is not empty"
  fi  
}

# CA -->
"${CA_HOME}/clean.sh"
# <-- CA

for i in `seq ${KAFKA_NUM_BROKERS}`; do

  node_name="${DOCKER_NAMESPACE}${KAFKA_BROKER_PREFIX}${i}"
  node_dir="${KAFKA_HOME}/volumes/${node_name}"
  secrets_dir="${node_dir}/secrets"
  keystore_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_FILENAME}"
  keystore_password_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_CREDENTIALS}"
  keystore_ssl_key_file="${secrets_dir}/${KAFKA_SSL_KEY_CREDENTIALS}"
  truststore_file="${secrets_dir}/${KAFKA_SSL_TRUSTSTORE_FILENAME}"
  truststore_password_file="${secrets_dir}/${KAFKA_SSL_TRUSTSTORE_CREDENTIALS}"
  private_key_csr_file="${secrets_dir}/csr.pem"
  signed_private_key_cert_file="${secrets_dir}/cert.pem"
  private_key_validity_days=3650
  private_key_cert_validity_days=3650

  rm -rfv "${keystore_file}"
  rm -rfv "${keystore_password_file}"
  rm -rfv "${keystore_ssl_key_file}"
  rm -rfv "${truststore_file}"
  rm -rfv "${truststore_password_file}"
  rm -rfv "${private_key_csr_file}"
  rm -rfv "${signed_private_key_cert_file}"

  rmdir_if_empty "${secrets_dir}"
  rmdir_if_empty "${node_dir}"

done

rm -rfv ${KAFKA_SSL_TRUSTSTORE_FILENAME}
rm -rfv ${KAFKA_SSL_TRUSTSTORE_CREDENTIALS}

"${CLIENTS_HOME}/clean.sh"
