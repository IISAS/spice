# Dockerfile
FROM openjdk:17-jdk-slim

# metadata
LABEL maintainer="you@example.com"
LABEL description="OpenJDK + OpenSSL image (includes keytool and openssl)"

ARG USER_ID=1000
ARG GROUP_ID=1000

# avoid interactive prompts
ARG DEBIAN_FRONTEND=noninteractive

# install openssl and common tools, clean apt cache to keep image small
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      procps \
      tzdata && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g ${GROUP_ID} ca && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} ca && \
    mkdir -p /ca /certs && \
    chown -R ca:ca /ca && \
    chown -R ca:ca /certs

WORKDIR /ca
USER ca
