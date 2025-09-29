#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}" && echo "🛈  CWD: ${PWD}"

. ./envars.sh

CA_HOME='./ca_home'
echo "🛈  CA_HOME: $(realpath ${CA_HOME})"

rm -fv ${CA_HOME}/*.pem
rm -fv ${CA_HOME}/index.txt
rm -fv ${CA_HOME}/index.txt.*
touch ${CA_HOME}/index.txt && echo "created ${CA_HOME}/index.txt"

rm -fv ${CA_HOME}/serial.txt
rm -fv ${CA_HOME}/serial.txt.*
echo 01 > ${CA_HOME}/serial.txt && echo "created ${CA_HOME}/serial.txt"

rm -rfv ./volumes/certs/*
