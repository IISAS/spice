#!/usr/bin/env bash
./cmd.sh \
  --profile kafka \
  --profile airflow \
  --profile domino \
  up -d
