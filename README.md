# SPICE

This is a docker compose deployment of SPICE services:

* Domino (forked and adjusted latest version of Domino to work with Apache Airflow v3.0.6) - https://github.com/iisas/domino
* Apache Airflow v3.0.6 - https://github.com/apache/airflow/tree/3.0.6
* Apache Kafka v4.0.0 - https://github.com/apache/kafka/tree/4.0.0

Domino pieces repository for SPICE is available here: https://github.com/IISAS/spice_domino_pieces

## Deployment

### Prerequisities
1. reverse proxy using Traefik (To be added here)

To deploy the SPICE environment with Kafka, run:
```bash
./kafka/provision.sh
./up.sh
```

### [./kafka/provision.sh](./kafka/provision.sh)
This script generates Kafka deployment with Encryption and Authentication using SSL. CA authority is generated automatically in the [./kafka/ca](./kafka/ca) directory.

### Testing the deployment
Adjust and run the following script to create a new topic and thus test the deployment.
```bash
bin/kafka-topics.sh --create --topic new-topic --bootstrap-server spice-iisas-kafka-broker-3.${HOSTNAME}:9093 --command-config kafka/clients/spice-iisas-client-alpha/client.properties 
```

### Kafka
Generate docker-compose.yml for Kafka deployment:
```bash
./kafka/docker-compose.yml.sh > ./kafka/docker-compose.yml
```
