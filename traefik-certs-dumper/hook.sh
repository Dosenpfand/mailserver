#!/usr/bin/env sh
set -eu
curl -u "${STALWART_USER}:${STALWART_PASSWORD}" https://${STALWART_HOST}/api/reload/certificate
