#!/usr/bin/env bash
docker compose \
  --profile flower \
  --env-file airflow/.env \
  --env-file domino/.env \
  --env-file kafka/.env \
  -f docker-compose.yml \
  -f airflow/docker-compose.yml \
  -f domino/docker-compose.yml \
  -f kafka/docker-compose.yml \
  $*
