#!/usr/bin/env bash
docker compose -f docker-compose.yml -f kafka/docker-compose.yml --env-file .env up -d
