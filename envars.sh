#!/usr/bin/env bash

SCRIPT_DIR=${SCRIPT_DIR:-.}

# local .env file
if [ -f ".env" ]; then
  echo "🛈  loading .env file from ${SCRIPT_DIR}"
  set -a
  source .env
  set +a
fi

# global .env file (overrides local)
if [ -f ".env" ]; then
  echo "🛈  loading global .env file from $(realpath ${SCRIPT_DIR}/..)"
  set -a
  source ../.env
  set +a
fi
