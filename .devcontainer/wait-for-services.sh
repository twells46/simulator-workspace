#!/usr/bin/env bash
# Installed in the image as wait-for-services; runs on each start (devcontainer.json
# postStartCommand). Bounded so a database that never comes up (e.g. bad
# Firebase credentials) cannot hang startup.
set -uo pipefail

timeout=${1:-60}
redis_ok=false
database_ok=false
for ((i = 0; i < timeout; i++)); do
  $redis_ok || { redis-cli -h redis ping >/dev/null 2>&1 && redis_ok=true; }
  # Any HTTP response counts; the API has no health endpoint.
  $database_ok || { curl -s -o /dev/null --max-time 2 http://database:4000/ && database_ok=true; }
  if $redis_ok && $database_ok; then
    echo "redis and database are ready."
    exit 0
  fi
  sleep 1
done

$redis_ok || echo "warning: redis did not answer PING within ${timeout}s; continuing." >&2
$database_ok || echo "warning: database:4000 did not respond within ${timeout}s; continuing. Check 'docker compose logs database' on the host." >&2
exit 0
