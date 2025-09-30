#!/usr/bin/env bash

set -a
source .env
set +a

containers=$(docker ps --format='{{.Names}}' | egrep -E '^'${NAME}'-(airflow|domino|kafka).+')
for container in  ${containers}; do
  id=$(docker inspect --format='{{.ID}}' ${container})
  echo "truncating logs of ${container} (${id})"
  truncate -s 0 /mnt/data/docker-data/containers/${id}/${id}-log.json
done
