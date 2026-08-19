#!/bin/sh
set -eu

echo "invoice-sync: starting"

if [ -z "${DB_PASSWORD:-}" ]; then
  echo "invoice-sync: ERROR db-password not injected" >&2
  exit 1
fi
echo "invoice-sync: db-password loaded (length ${#DB_PASSWORD})"

if [ "${FORCE_FAIL:-false}" = "true" ]; then
  echo "invoice-sync: FORCE_FAIL set, exiting non-zero" >&2
  exit 1
fi

echo "invoice-sync: completed"
