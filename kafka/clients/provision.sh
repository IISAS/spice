#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}" && echo "🛈  CWD: ${PWD}"

. ./envars.sh

CA_ROOT="$(realpath '../../ca')"
CA_HOME="${CA_ROOT}/ca_home"
CLIENTS_HOME="${SCRIPT_DIR}"
KAFKA_HOME="${CLIENTS_HOME}/.."

#export CA_ROOT=${CA_ROOT}
#export CA_HOME=${CA_HOME}

ca_cert_file="/ca/cacert.pem"

###############################################################################


function clean_path() {
  path=$1
  echo "$path" | sed 's#//*#/#g'
  return 0
}


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
    return 1
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
  alias="$2"
  CN="$3"
  validity=$4
  storepass="$5"
  keypass="${6:-}"

  if [ -f "${CA_ROOT}/${keystore}" ]; then
    echo "⚠️  keystore already exists (skipping): ${keystore}"
    return 1
  fi

  echo "creating keystore: ${keystore}"
    
  cmd=(${CA_ROOT}/ca.sh keytool \
    -genkeypair \
    -keystore "${keystore}" \
    -alias "${alias}" \
    -validity ${validity} \
    -keyalg RSA \
    -storetype pkcs12 \
    -storepass "${storepass}" \
    -dname "CN=${CN}")
    
  # Add -keypass only if provided (non-empty)
  if [[ -n $keypass ]]; then
    cmd+=(-keypass "$keypass")
  fi

  "${cmd[@]}"

  if [ ! -f "${CA_ROOT}/${keystore}" ]; then
    echo "❌ keystore not created: ${keystore}"
    return 1
  fi

  echo "✅ keystore created: ${keystore}"
  return 0
}


function create_csr() {

  keystore="$1"
  file="$2"
  alias="$3"
  storepass="$4"
  keypass="${5:-}"

  if [ -f "${CA_ROOT}/$file" ]; then
    echo "⚠️  CSR already exists: $file"
    return 1
  fi

  cmd=(${CA_ROOT}/ca.sh keytool \
    -certreq \
    -keystore "${keystore}" \
    -file "${file}" \
    -alias "${alias}" \
    -storepass "${storepass}" \
    -storetype PKCS12)

  if [[ -n ${keypass} ]]; then
    cmd+=(-keypass "${keypass}")
  fi

  "${cmd[@]}"

  if [ ! -f "${CA_ROOT}/$file" ]; then
    echo "❌ could not create CSR: $file"
    return 1
  fi

  echo "✅ CSR created: $file"
  return 0
}
  

function sign_csr() {

  csr=$1
  out=$2
  days=$3

  out_host=$(clean_path "${CA_ROOT}/${out}")

  if [ -f "${out_host}" ]; then
    echo "⚠️  certificate already exists: $out"
    return 1
  fi

  ${CA_ROOT}/ca.sh openssl ca -batch -config /etc/ssl/openssl.cnf -policy signing_policy -extensions signing_req -days ${days} -in "${csr}" -out "${out}"

  if [ ! -f "${out_host}" ]; then
    echo "❌ signed certificate not found after signing CSR: ${out}"
    return 1
  fi

  echo "✅ certificate signed: ${out}"
  return 0
}


function generate_client_properties () {

  truststore_location="$1"
  truststore_password="$2"
  keystore_location="$3"
  keystore_password="$4"
  key_password="${5:-}"
  
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

  echo "✅ cert ${file} imported into ${keystore}"
  return 0
}


function provision_client() {

  client_name_short="$1"  
  storepass="$2"
  validity="${3:-365}"
 
  client_name="${DOCKER_NAMESPACE}${KAFKA_CLIENT_PREFIX}${client_name_short}"
  client_dir_host="${CLIENTS_HOME}/${client_name}"

  secrets_dir="/certs/_clients_/${client_name}/secrets"
  secrets_dir_host=$(clean_path "${CA_ROOT}/${secrets_dir}")

  # keystore
  keystore_file="${secrets_dir}/keystore.jks"
  keystore_file_host=$(clean_path "${CA_ROOT}/${keystore_file}")
  keystore_credentials="${secrets_dir}/keystore_creds"
  keystore_credentials_host=$(clean_path "${CA_ROOT}/${keystore_credentials}")

  csr_file="${secrets_dir}/csr.pem"
  signed_cert_file="${secrets_dir}/cert.pem"

  printf "\nprovisioning client: %s\n" "${client_name}"

  mkdir_chck "${client_dir_host}"
  mkdir_chck "${secrets_dir_host}"

  # keystore credentials
  create_credentials "${keystore_credentials_host}" "${storepass}"
  [ ! -f "${keystore_credentials_host}" ] && { echo "❌ keystore credentials not found: ${keystore_credentials_host}"; }
  read -r keystore_password < "${keystore_credentials_host}"

  create_keystore "${keystore_file}" "${client_name}" "${client_name}" ${validity} "${keystore_password}" &&
  create_csr "${keystore_file}" "${csr_file}" "${client_name}" "${keysstore_password}" &&
  sign_csr "${csr_file}" "${signed_cert_file}" "${validity}" &&
  import_cert "${keystore_file}" "${ca_cert_file}" "CARoot" "${keystore_password}" &&
  import_cert "${keystore_file}" "${signed_cert_file}" "${client_name}" "${keystore_password}"

  echo "copying certificates to client's dir ..."
  cp -v ${secrets_dir_host}/* "${client_dir_host}/"
  cp -v $(clean_path "${CA_HOME}/cacert.pem") "${client_dir_host}/"
  cp -v $(clean_path "${CA_ROOT}/certs/truststore.p12") "${client_dir_host}"

  # copied client's keystore and its credentials location
  keystore_file_client="${secrets_dir_host}/keystore.jks"
  keystore_credentials_client="${secrets_dir_host}/keystore_creds"
  
  # copy global truststore to the client
  echo "copying global truststore to the client ..."
  truststore_file_client="${secrets_dir_host}/truststore.jks"
  truststore_credentials_client="${secrets_dir_host}/truststore_creds"
  cp -v "${truststore_file_host}" "${truststore_file_client}"
  cp -v "${truststore_credentials_host}" "${truststore_credentials_client}"

  echo "converting keystore from JKS to PKCS12 ..."
  ${CA_ROOT}/ca.sh keytool -importkeystore \
    -srckeystore "${keystore_file}" \
    -srcstoretype JKS \
    -srcstorepass "${keystore_password}" \
    -destkeystore "${secrets_dir}/keystore.p12" \
    -deststoretype PKCS12 \
    -deststorepass "${keystore_password}" \
    -noprompt
  # convert PKCS12 to PEM
  ${CA_ROOT}/ca.sh openssl pkcs12 -in "${secrets_dir}/keystore.p12" -nocerts -nodes -out "${secrets_dir}/key.pem" -passin pass:"${keystore_password}"
  cp -v $(clean_path "${secrets_dir_host}/key.pem") "${client_dir_host}"
  cp -v $(clean_path "${secrets_dir_host}/keystore.p12") "${client_dir_host}"

  echo "Generating client.properties ..."
  generate_client_properties \
    "/opt/client/truststore.jks" \
    "${truststore_password}" \
    "/opt/client/keystore.jks" \
    "${keystore_password}" > "${client_dir_host}/client.properties"

  echo "generating scripts for the client ..."
  kafka_topics_sh_filename="kafka-topics-${client_name_short}.sh"
  cat <<EOF > ${kafka_topics_sh_filename}
#!/usr/bin/env bash

./kafka-topics.sh "${client_dir_host}" \$*
EOF
  chmod +x "${kafka_topics_sh_filename}"

  return 0
}


###############################################################################

truststore_file="/certs/truststore.jks"
truststore_file_host=$(clean_path "${CA_ROOT}/${truststore_file}")
truststore_credentials="/certs/truststore_creds"
truststore_credentials_host=$(clean_path "${CA_ROOT}/${truststore_credentials}")

[ ! -f "${truststore_credentials_host}" ] && { echo "❌ truststore credentials not found: ${truststore_credentials_host}"; }
read -r truststore_password < "${truststore_credentials_host}"

echo "converting truststore from JKS to PKCS12 ..."
${CA_ROOT}/ca.sh keytool -importkeystore \
  -srckeystore "${truststore_file}" \
  -srcstoretype JKS \
  -srcstorepass "${truststore_password}" \
  -destkeystore "/certs/truststore.p12" \
  -deststoretype PKCS12 \
  -deststorepass "${truststore_password}" \
  -noprompt

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
