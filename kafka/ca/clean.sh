#!/usr/bin/env bash

CWD="$(pwd)"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

rm -fv *.pem
rm -fv index.txt
rm -fv index.txt.*
touch ./index.txt

rm -fv serial.txt
rm -fv serial.txt.*
echo 01 > ./serial.txt

cd "${CWD}"
