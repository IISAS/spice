#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

docker \
  run \
  --rm \
  -v "${SCRIPT_DIR}/volumes/etc/ssl:/etc/ssl" \
  -v "${SCRIPT_DIR}/volumes/ca:/ca" \
  -v "${SCRIPT_DIR}/volumes/certs:/certs" \
  ca:latest \
  $*
