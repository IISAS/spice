#!/usr/bin/env bash

CWD="$(pwd)"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

set -a
source .env
set +a

CLIENTS_HOME=${SCRIPT_DIR}
echo "CLIENTS_HOME: ${CLIENTS_HOME}"

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

function delete_client() {
  
  client_name="${DOCKER_NAMESPACE}client-$1"
  client_dir="${CLIENTS_HOME}/${client_name}"
  secrets_dir="$client_dir/secrets"

  keystore_file="$secrets_dir/keystore.jks"
  keystore_credentials="$secrets_dir/keystore_creds"
  truststore_file="$secrets_dir/truststore.jks"
  truststore_credentials="$secrets_dir/truststore_creds"
  csr_file="$secrets_dir/csr.pem"
  cert_file="$secrets_dir/cert.pem"
  client_properties_file="${client_dir}/client.properties"

  if [ ! -d "$client_dir" ]; then
    echo "❌ client not found: $client_name"
    return
  fi

  echo "removing client: $client_name"

  if [ -f "$keystore_file" ]; then
    rm -v "$keystore_file"
  fi

  if [ -f "$keystore_credentials" ]; then
    rm -v "$keystore_credentials"
  fi

  if [ -f "$truststore_file" ]; then
    rm -v "$truststore_file"
  fi

  if [ -f "$truststore_credentials" ]; then
    rm -v "$truststore_credentials"
  fi

  if [ -f "$csr_file" ]; then
    rm -v "$csr_file"
  fi

  if [ -f "$cert_file" ]; then
    rm -v "$cert_file"
  fi
 
  if [ -f "$client_properties_file" ]; then
    rm -v "$client_properties_file"
  fi

  rmdir_if_empty $secrets_dir
  rmdir_if_empty $client_dir

  if [ ! -d "$client_dir" ]; then
    echo "✅ removed client: $client_name"
  fi
}

if [ -p /dev/stdin ]; then
  # Input is coming from a pipe or redirection
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    delete_client $client
  done

elif [ -n "$1" ] && [ -f "$1" ]; then
  # No stdin, but a file argument is provided
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    delete_client $client
  done < "$1"

elif [ -f clients ]; then
  # No stdin, not file argument but 'clients' file exists
  while IFS=',' read -r client storepass; do
    [[ -z "$client" || $client == \#* ]] && continue
    delete_client $client
  done < clients

else
  echo "Usage: $0 [filename], via pipe, or 'clients' file" >&2
  exit 1
fi
