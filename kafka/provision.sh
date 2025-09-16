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
CA_HOME="$(realpath -s './ca')"
export CA_HOME=${CA_HOME}
KAFKA_CA_CONFIG_FILE="${CA_HOME}/${KAFKA_CA_CONFIG_FILE}"
echo "KAFKA_CA_CONFIG_FILE: ${KAFKA_CA_CONFIG_FILE}"
ca_cert_file="${CA_HOME}/cacert.pem"


###############################################################################


function import_cert() {

  keystore=$1
  file=$2
  alias=$3
  storepass=$4
  keypass=${5:-}  # Default to empty string if no 5th argument

  cmd=(keytool \
    -importcert \
    -keystore "${keystore}" \
    -file "${file}" \
    -alias ${alias} \
    -storepass "${storepass}" \
    -noprompt)

  # Add -keypass only if provided (non-empty)
  if [[ -n $keypass ]]; then
    cmd+=(-keypass "$keypass")
  fi

  "${cmd[@]}"
  (( $? != 0 )) && { echo "❌ cert ${file} not imported into ${keystore}"; return 1; }

  return 0
}


function create_csr() {

  keystore=$1
  file=$2
  alias=$3
  storepass=$4
  keypass=$5

  if [ -f "$file" ]; then
    echo "⚠️  CSR already exists: $file"
    return 0
  fi

  keytool \
    -certreq \
    -keystore "${keystore}" \
    -file "${file}" \
    -alias "${alias}" \
    -storepass "${storepass}" \
    -keypass "${keypass}" \
    -storetype PKCS12

  if [ -f "$file" ]; then
    echo "✅ CSR created: $file"
  else
    echo "❌ could not create CSR: $file"
    return 1
  fi

  return 0
}
  

function sign_csr() {
  
  config=$1
  csr=$2
  out=$3
  days=$4
  
  if [ -f "$out" ]; then
    echo "⚠️  certificate already exists: $out"
    return 0
  fi

  openssl ca -batch -config "${config}" -policy signing_policy -extensions signing_req -days ${days} -in "${csr}" -out "${out}"

  if [ -f "${out}" ]; then
    echo "✅ certificate signed: ${out}"
    return 0
  fi
    
  [ ! -f "${out}" ] && { echo "❌ signed certificate not found after signing CSR: ${out}"; return 1; }

  return 0
}


###############################################################################

"${CA_HOME}/create.sh"

./docker-compose.yml.sh > docker-compose.yml

truststores=()
common_truststore_filename="${KAFKA_HOME}/${KAFKA_SSL_TRUSTSTORE_FILENAME}"
common_truststore_password_file="${KAFKA_HOME}/${KAFKA_SSL_TRUSTSTORE_CREDENTIALS}"
 
# store truststore password in a file
if [ ! -f "${common_truststore_password_file}" ]; then
  echo ${KAFKA_SSL_TRUSTSTORE_PASSWORD} > "${common_truststore_password_file}"
else
  echo "⚠️  truststore password file already exists: ${common_truststore_password_file}"
fi

# reload passwords from the disk
read -r KAFKA_SSL_TRUSTSTORE_PASSWORD < "$common_truststore_password_file"

# add CARoot cert into the global truststore
import_cert "${common_truststore_filename}" "${ca_cert_file}" 'CARoot' "${KAFKA_SSL_TRUSTSTORE_PASSWORD}"

# generate keystores for brokers
for i in `seq ${KAFKA_NUM_BROKERS}`; do

  node_name="${DOCKER_NAMESPACE}${KAFKA_BROKER_PREFIX}${i}"

  echo -e "\n### ${node_name} ###\n"
  
  secrets_dir="${KAFKA_HOME}/volumes/${node_name}/secrets"
  keystore_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_FILENAME}"
  keystore_password_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_CREDENTIALS}"
  keystore_ssl_key_file="${secrets_dir}/${KAFKA_SSL_KEY_CREDENTIALS}"
  truststore_file="${secrets_dir}/${KAFKA_SSL_TRUSTSTORE_FILENAME}"
  private_key_csr_file="${secrets_dir}/csr.pem"
  signed_private_key_cert_file="${secrets_dir}/cert.pem"
  private_key_validity_days=3650
  private_key_cert_validity_days=3650
 
  # create broker's secrets dir to store keystore and truststore
  mkdir -p "${secrets_dir}"

  # store keystore password in a file
  if [ ! -f "${keystore_password_file}" ]; then
    echo ${KAFKA_SSL_KEYSTORE_PASSWORD} > "${keystore_password_file}"
  else
    echo "⚠️  keystore password file already exists: ${keystore_password_file}"
  fi

  # store SSL key in a file
  if [ ! -f "${keystore_sll_key_file}" ]; then
    echo ${KAFKA_SSL_KEY_PASSWORD} > "${keystore_ssl_key_file}"
  else
    echo "⚠️  keystore ssl key file already exists: ${keystore_ssl_key_file}"
  fi

  # reload passwords from the disk
  read -r KAFKA_SSL_KEYSTORE_PASSWORD < "$keystore_password_file"
  read -r KAFKA_SSL_KEY_PASSWORD < "$keystore_ssl_key_file"

  # create keystore with a private key
  if [ ! -f "${keystore_file}" ]; then
    keytool\
      -keystore "${keystore_file}" \
      -alias "${node_name}" \
      -validity ${private_key_validity_days} \
      -genkey \
      -keyalg RSA \
      -storetype pkcs12 \
      -storepass "${KAFKA_SSL_KEYSTORE_PASSWORD}" \
      -keypass "${KAFKA_SSL_KEY_PASSWORD}" \
      -dname "CN=${node_name}, OU=, O=, L=, ST=, C="
      [[ $? ]] || { echo "✅ keystore created: ${keystore_file}"; }
  else
    echo "⚠️  keystore already exists: ${keystore_file}"
  fi

  # obtain certificate for the private key
  # create private key CSR
  create_csr "${keystore_file}" "${private_key_csr_file}" "${node_name}" "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # sign private key CSR
  sign_csr "${KAFKA_CA_CONFIG_FILE}" "${private_key_csr_file}" "${signed_private_key_cert_file}" ${private_key_cert_validity_days}
  # import CA into the keystore
  import_cert "${keystore_file}" "${ca_cert_file}" 'CARoot' "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # import signed private key certificate
  import_cert "${keystore_file}" "${signed_private_key_cert_file}" "${node_name}" "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # import signed private key certificate into the common truststore
  import_cert "${common_truststore_filename}" "${signed_private_key_cert_file}" "${node_name}" "${KAFKA_SSL_TRUSTSTORE_PASSWORD}"
  # copy common truststore credentials
  cp -v "${common_truststore_password_file}" "${secrets_dir}"
  truststores+=("${truststore_file}")

done

echo "copying trustore to Kafka nodes..."

for truststore in "${truststores[@]}"; do
  cp -v "${common_truststore_filename}" "${truststore}"
done

"${CLIENTS_HOME}/provision.sh"
