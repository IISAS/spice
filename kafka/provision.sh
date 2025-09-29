#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}" && echo "🛈  CWD: ${PWD}"

. ./envars.sh

CA_ROOT='../ca'
CA_HOME="${CA_ROOT}/ca_home"

KAFKA_HOME=${SCRIPT_DIR}
KAFKA_CLIENTS_HOME='./clients'

export CA_ROOT=${CA_ROOT}
export CA_HOME=${CA_HOME}

ca_cert_file="/ca/cacert.pem"


###############################################################################


function import_cert() {

  keystore=$1
  file=$2
  alias=$3
  storepass=$4
  keypass=${5:-}  # Default to empty string if no 5th argument

  cmd=(${CA_ROOT}/ca.sh keytool \
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

  ${CA_ROOT}/ca.sh keytool \
    -certreq \
    -keystore "${keystore}" \
    -file "${file}" \
    -alias "${alias}" \
    -storepass "${storepass}" \
    -keypass "${keypass}" \
    -storetype PKCS12

  if [ -f "${CA_ROOT}/$file" ]; then
    echo "✅ CSR created: ${CA_ROOT}/$file"
  else
    echo "❌ could not create CSR: ${CA_ROOT}/$file"
    return 1
  fi

  return 0
}
  

function sign_csr() {
  
  csr=$1
  out=$2
  days=$3
  
  if [ -f "$out" ]; then
    echo "⚠️  certificate already exists: $out"
    return 0
  fi

  ${CA_ROOT}/ca.sh openssl ca -batch -config /etc/ssl/openssl.cnf -policy signing_policy -extensions signing_req -days ${days} -in "${csr}" -out "${out}"

  if [ -f "${CA_ROOT}/${out}" ]; then
    echo "✅ certificate signed: ${out}"
    return 0
  fi
    
  [ ! -f "${CA_ROOT}/${out}" ] && { echo "❌ signed certificate not found after signing CSR: ${CA_ROOT}/${out}"; return 1; }

  return 0
}


function clean_path() {
  path=$1
  echo "$path" | sed 's#//*#/#g'
  return 0
}

###############################################################################

./docker-compose.yml.sh > docker-compose.yml

truststores=()
common_truststore_filename="/certs/${KAFKA_SSL_TRUSTSTORE_FILENAME}"
common_truststore_filename_host=$(clean_path "${CA_ROOT}/${common_truststore_filename}")

common_truststore_password_file="/certs/${KAFKA_SSL_TRUSTSTORE_CREDENTIALS}"
common_truststore_password_file_host=$(clean_path "${CA_ROOT}/${common_truststore_password_file}")

 
# store truststore password in a file
if [ ! -f "${common_truststore_password_file_host}" ]; then
  echo ${KAFKA_SSL_TRUSTSTORE_PASSWORD} > "${common_truststore_password_file_host}"
else
  echo "⚠️  truststore password file already exists: ${common_truststore_password_file_host}"
fi

# reload passwords from the disk
read -r KAFKA_SSL_TRUSTSTORE_PASSWORD < "${common_truststore_password_file_host}"

# add CARoot cert into the global truststore
import_cert "${common_truststore_filename}" "${ca_cert_file}" 'CARoot' "${KAFKA_SSL_TRUSTSTORE_PASSWORD}"

# generate keystores for brokers
for i in `seq ${KAFKA_NUM_BROKERS}`; do

  node_name="${DOCKER_NAMESPACE}${KAFKA_BROKER_PREFIX}${i}"

  echo -e "\n### ${node_name} ###\n"
  
  secrets_dir="/certs/${node_name}/secrets"
  secrets_dir_host=$(clean_path "${CA_ROOT}/${secrets_dir}")
  keystore_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_FILENAME}"
  keystore_password_file="${secrets_dir}/${KAFKA_SSL_KEYSTORE_CREDENTIALS}"
  keystore_ssl_key_file="${secrets_dir}/${KAFKA_SSL_KEY_CREDENTIALS}"
  truststore_file="${secrets_dir}/${KAFKA_SSL_TRUSTSTORE_FILENAME}"
  truststore_file_host=$(clean_path "${CA_ROOT}/${truststore_file}")
  private_key_csr_file="${secrets_dir}/csr.pem"
  signed_private_key_cert_file="${secrets_dir}/cert.pem"
  private_key_validity_days=3650
  private_key_cert_validity_days=3650
 
  # create broker's secrets dir at host to store keystore and truststore
  mkdir -p "${CA_ROOT}/${secrets_dir}"

  # store keystore password in a file
  if [ ! -f "${CA_ROOT}/${keystore_password_file}" ]; then
    echo ${KAFKA_SSL_KEYSTORE_PASSWORD} > "${CA_ROOT}/${keystore_password_file}"
  else
    echo "⚠️  keystore password file already exists: ${CA_ROOT}/${keystore_password_file}"
  fi

  # store SSL key in a file
  if [ ! -f "${CA_ROOT}/${keystore_sll_key_file}" ]; then
    echo ${KAFKA_SSL_KEY_PASSWORD} > "${CA_ROOT}/${keystore_ssl_key_file}"
  else
    echo "⚠️  keystore ssl key file already exists: ${CA_ROOT}/${keystore_ssl_key_file}"
  fi

  # reload passwords from the disk
  read -r KAFKA_SSL_KEYSTORE_PASSWORD < "${CA_ROOT}/$keystore_password_file"
  read -r KAFKA_SSL_KEY_PASSWORD < "${CA_ROOT}/$keystore_ssl_key_file"

  # create keystore with a private key
  if [ ! -f "${keystore_file}" ]; then
    ${CA_ROOT}/ca.sh keytool \
      -genkeypair \
      -keystore "${keystore_file}" \
      -alias "${node_name}" \
      -validity ${private_key_validity_days} \
      -keyalg RSA \
      -storetype pkcs12 \
      -storepass "${KAFKA_SSL_KEYSTORE_PASSWORD}" \
      -keypass "${KAFKA_SSL_KEY_PASSWORD}" \
      -dname "CN=${node_name}"
      [[ $? ]] || { echo "✅ keystore created: ${keystore_file}"; }
  else
    echo "⚠️  keystore already exists: ${keystore_file}"
  fi

  # obtain certificate for the private key
  # create private key CSR
  create_csr "${keystore_file}" "${private_key_csr_file}" "${node_name}" "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # sign private key CSR
  sign_csr "${private_key_csr_file}" "${signed_private_key_cert_file}" ${private_key_cert_validity_days}
  # import CA into the keystore
  import_cert "${keystore_file}" "${ca_cert_file}" 'CARoot' "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # import signed private key certificate
  import_cert "${keystore_file}" "${signed_private_key_cert_file}" "${node_name}" "${KAFKA_SSL_KEYSTORE_PASSWORD}" "${KAFKA_SSL_KEY_PASSWORD}"
  # import signed private key certificate into the common truststore
  import_cert "${common_truststore_filename}" "${signed_private_key_cert_file}" "${node_name}" "${KAFKA_SSL_TRUSTSTORE_PASSWORD}"
  # copy common truststore credentials
  mkdir -p "./volumes/${node_name}/secrets"
  cp -v "${common_truststore_password_file_host}" "${secrets_dir_host}"
  truststores+=("${truststore_file_host}")

done

echo "copying trustore to Kafka nodes..."

for truststore in "${truststores[@]}"; do
  cp -v "${common_truststore_filename_host}" "${truststore}"
done

#"${KAFKA_CLIENTS_HOME}/provision.sh"
