#!/usr/bin/env bash
docker compose -f docker-compose.yml --env-file .env ps
