#!/usr/bin/env bash

CWD="$(pwd)"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

set -a
source .env
set +a

CLIENTS_HOME=${SCRIPT_DIR}
echo "CLIENTS_HOME: ${CLIENTS_HOME}"
KAFKA_HOME="${CLIENTS_HOME}/.."
echo "KAFKA_HOME: ${KAFKA_HOME}"
if [ -z "${CA_HOME}" ]; then
  CA_HOME="$(realpath -s "${KAFKA_HOME}/ca")"
  export CA_HOME=${CA_HOME}
fi
echo "CA_HOME: ${CA_HOME}"
KAFKA_CA_CONFIG_FILE="${CA_HOME}/${KAFKA_CA_CONFIG_FILE}"
echo "KAFKA_CA_CONFIG_FILE: ${KAFKA_CA_CONFIG_FILE}"
ca_cert_file="${CA_HOME}/cacert.pem"


###############################################################################


function mkdir_chck() {
  dir=$1
  if [ -d "${dir}" ]; then
    echo "⚠️  dir already exists: ${dir}"
  else
    mkdir -p "${dir}"
  fi
}


function create_credentials() {

  filename="$1"
  password="$2"

  if [ -f "${filename}" ]; then
    echo "⚠️  credentials already exist and will be reused: ${filename}"
    return 0
  fi
  
  echo "${password}" > "${filename}"
  if [ -f "${filename}" ]; then
    echo "✅ credentials created: ${filename}"
    return 0
  fi

  echo "❌ credentials not created: ${filename}"
  return 1
}


function create_keystore() {

  keystore="$1"
  keystore_credentials="$2"
  alias="$3"
  CN="$4"
  validity=$5

  if [ -f "${keystore}" ]; then
    echo "⚠️  keystore alredy exists: ${keystore}"
    return 0
  fi

  if [ ! -f "${keystore_credentials}" ]; then
    echo "❌ keystore credentials not found: ${keystore_credentials}"
  else
    read -r storepass < "${keystore_credentials}"
    echo "creating client keystore: ${keystore}"
    keytool \
      -keystore "${keystore}" \
      -alias "${alias}" \
      -validity ${validity} \
      -genkey \
      -keyalg RSA \
      -storetype pkcs12 \
      -storepass "${storepass}" \
      -dname "CN=${CN}, OU=, O=, L=, ST=, C="
    if [ -f "${keystore}" ]; then
      echo "✅ keystore created: ${keystore}"
      return 0
    fi
  fi

  echo "❌ keystore not created: ${keystore}"
  return 1
}


function create_csr() {

  keystore=$1
  keystore_credentials=$2
  file=$3
  alias=$4
  keypass=${5:-}

  if [ -f "$file" ]; then
    echo "⚠️  CSR already exists: $file"
    return 0
  fi

  if [ ! -f "${keystore_credentials}" ]; then
    echo "❌ keystore credentials not found: ${keystore_credentials}"
  else
    # read storepass from a file
    read -r storepass < "$keystore_credentials"

    cmd=(keytool \
      -certreq \
      -keystore "${keystore}" \
      -file "${file}" \
      -alias "${alias}" \
      -storepass "${storepass}" \
      -storetype PKCS12)

    # Add -keypass only if provided (non-empty)
    if [[ -n $keypass ]]; then
      cmd+=(-keypass "$keypass")
    fi

    "${cmd[@]}"

    if [ -f "$file" ]; then
      echo "✅ CSR created: $file"
      return 0
    fi
  fi
  
  echo "❌ could not create CSR: $file"
  return 1
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

  cd "${CA_HOME}"
  openssl \
    ca \
    -batch \
    -config "${config}" \
    -policy signing_policy \
    -extensions signing_req \
    -days ${days} \
    -in "${csr}" \
    -out "${out}"

  if [ -f "${out}" ]; then
    echo "✅ certificate signed: ${out}"
    return 0
  fi  
    
  echo "❌ signed certificate not found after signing CSR: ${out}"
  return 1
}


function generate_client_properties () {

  truststore_location="$1"
  truststore_credentials="$2"
  keystore_location="$3"
  keystore_credentials="$4"
  key_password="${5:-}"
  
  [ ! -f "${truststore_credentials}" ] && { echo "❌ truststore credentials found: ${truststore_credentials}"; return 1; }
  read -r truststore_password < "${truststore_credentials}"

  [ ! -f "${keystore_credentials}" ] && { echo "❌ keystore credentials found: ${keystore_credentials}"; return 1; }
  read -r keystore_password < "${keystore_credentials}"

  cat <<EOF
security.protocol=SSL
ssl.endpoint.identification.algorithm=
ssl.keystore.location=${keystore_location}
ssl.keystore.password=${keystore_password}
ssl.truststore.location=${truststore_location}
ssl.truststore.password=${truststore_password}
EOF

  if [ ! -z "${key_password}" ]; then
    echo "ssl.key.password=${key_password}"
  fi
}


function import_cert() {

  keystore=$1
  file=$2
  alias=$3
  keystore_credentials=$4
  keypass=${5:-}  # Default to empty string if no 5th argument
 
  if [ ! -f "${keystore_credentials}" ]; then
    echo "❌ keystore credentials found: ${keystore_credentials}"
  else
    read -r storepass < "${keystore_credentials}"

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
    if (( $? == 0 )); then
      echo "✅ cert ${file} imported into ${keystore}"
      return 0
    fi
  fi

  echo "❌ cert ${file} not imported into ${keystore}"
  return 1
}


function provision_client() {

  client_name="$1"  
  storepass="$2"
  validity="${3:-365}"
 
  client_name="${DOCKER_NAMESPACE}${KAFKA_CLIENT_PREFIX}${client_name}"
  client_dir="${CLIENTS_HOME}/${client_name}"
  secrets_dir="${client_dir}/secrets"

  keystore_file="${secrets_dir}/keystore.jks"
  keystore_credentials="${secrets_dir}/keystore_creds"
  csr_file="${secrets_dir}/csr.pem"
  signed_cert_file="${secrets_dir}/cert.pem"

  truststore_file="${secrets_dir}/truststore.jks"
  truststore_credentials="${secrets_dir}/truststore_creds"

  printf "\nprovisioning client: %s\n" "${client_name}"

  mkdir_chck "${client_dir}"
  mkdir_chck "${secrets_dir}"

  cd "${client_dir}"

  create_credentials "${keystore_credentials}" "${storepass}" || return 1
  create_keystore "${keystore_file}" "${keystore_credentials}" "${client_name}" "${client_name}" ${validity} || return 1
  create_csr "${keystore_file}" "${keystore_credentials}" "${csr_file}" "${client_name}" || return 1
  sign_csr "${KAFKA_CA_CONFIG_FILE}" "${csr_file}" "${signed_cert_file}" "${validity}" || return 1
  import_cert "${keystore_file}" "${ca_cert_file}" "CARoot" "${keystore_credentials}" || return 1
  import_cert "${keystore_file}" "${signed_cert_file}" "${client_name}" "${keystore_credentials}" || return 1

  cp -v "${KAFKA_HOME}/truststore_creds" "${secrets_dir}/"
  cp -v "${KAFKA_HOME}/truststore.jks" "${secrets_dir}/"

  generate_client_properties \
    "${truststore_file}" \
    "${truststore_credentials}" \
    "${keystore_file}" \
    "${keystore_credentials}" > "${client_dir}/client.properties"

  return 0
}


###############################################################################


if [ -p /dev/stdin ]; then
  # Input is coming from a pipe or redirection
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    provision_client "$client" "$storepass"
  done

elif [ -n "$1" ] && [ -f "$1" ]; then
  # No stdin, but a file argument is provided
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    provision_client "$client" "$storepass"
  done < "$1"

elif [ -f clients ]; then
  # No stdin, not file argument but 'clients' file exists
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    provision_client "$client" "$storepass"
  done < clients

else
  echo "Usage: $0 [filename], via pipe or 'clients' file" >&2
  exit 1
fi
