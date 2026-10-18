#!/usr/bin/env bash
# Starts every image restricted (its own user, a read-only root, every capability dropped)
# beside Postgres with pgvector, and waits for each to serve: TEI with a small embedding model
# and a small reranker, the api, the worker and the control plane.
# Usage: scripts/smoke-test.sh <api-image> <control-plane-image> <tei-image>
set -euo pipefail
api_image=$1
cp_image=$2
tei_image=$3
net=hindsight-smoke
containers=(smoke-postgres smoke-tei smoke-rerank smoke-api smoke-worker smoke-cp)

cleanup() {
  docker rm -f "${containers[@]}" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
docker network create "$net" >/dev/null

restricted=(--network "$net" --user 1000:1000 --read-only --cap-drop ALL --security-opt no-new-privileges
  --tmpfs '/tmp:uid=1000,gid=1000,mode=1777')

docker run -d --name smoke-postgres --network "$net" -e POSTGRES_USER=hindsight \
  -e POSTGRES_PASSWORD='p@ss:w/rd' -e POSTGRES_DB=hindsight_db pgvector/pgvector:pg17 >/dev/null

db=(-e HINDSIGHT_DB_HOST=smoke-postgres -e HINDSIGHT_DB_PORT=5432 -e HINDSIGHT_DB_NAME=hindsight_db
  -e HINDSIGHT_DB_USER=hindsight -e 'HINDSIGHT_DB_PASSWORD=p@ss:w/rd'
  -e HINDSIGHT_API_LLM_PROVIDER=openai -e HINDSIGHT_API_LLM_API_KEY=smoke
  -e HINDSIGHT_API_LLM_BASE_URL=http://127.0.0.1:9/v1 -e HINDSIGHT_API_LLM_MODEL=smoke
  -e HINDSIGHT_API_EMBEDDINGS_PROVIDER=tei -e HINDSIGHT_EMBEDDINGS_HOST=smoke-tei -e HINDSIGHT_EMBEDDINGS_PORT=8091
  -e HINDSIGHT_API_RERANKER_PROVIDER=tei -e HINDSIGHT_RERANKER_HOST=smoke-rerank -e HINDSIGHT_RERANKER_PORT=8092)

# wait_for <container> <url>: polls the url from inside the container until it answers.
wait_for() {
  for _ in $(seq 1 120); do
    if docker exec "$1" python3 -c "import urllib.request; urllib.request.urlopen('$2', timeout=3)" >/dev/null 2>&1 \
      || docker exec "$1" node -e "fetch('$2').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))" >/dev/null 2>&1; then
      echo "$1 serves $2"
      return 0
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$1")" != true ]; then
      docker logs "$1" 2>&1 | tail -40
      echo "$1 exited before it served $2" >&2
      return 1
    fi
    sleep 5
  done
  docker logs "$1" 2>&1 | tail -40
  echo "$1 never served $2" >&2
  return 1
}

until docker exec smoke-postgres pg_isready -U hindsight -d hindsight_db >/dev/null 2>&1; do sleep 2; done
docker exec smoke-postgres psql -U hindsight -d hindsight_db -c 'CREATE EXTENSION IF NOT EXISTS vector' >/dev/null

# The api and the worker start before TEI exists, as they do when a release restarts TEI
# beside them: each waits for both TEI servers rather than exiting.
docker run -d --name smoke-api "${restricted[@]}" "${db[@]}" -e HINDSIGHT_ROLE=api \
  -e HINDSIGHT_API_PORT=8888 "$api_image" >/dev/null
docker run -d --name smoke-worker "${restricted[@]}" "${db[@]}" -e HINDSIGHT_ROLE=worker \
  -e HINDSIGHT_API_WORKER_HTTP_PORT=8889 "$api_image" >/dev/null
for waiting in smoke-api smoke-worker; do
  until docker logs "$waiting" 2>&1 | grep -q 'hindsight-start: waiting for http://smoke-tei:8091/health'; do
    [ "$(docker inspect -f '{{.State.Running}}' "$waiting")" = true ] \
      || { docker logs "$waiting" 2>&1 | tail -20; echo "$waiting exited instead of waiting for TEI" >&2; exit 1; }
    sleep 1
  done
  echo "$waiting waits for TEI"
done

docker run -d --name smoke-tei "${restricted[@]}" --tmpfs '/data:uid=1000,gid=1000' \
  -e MODEL_ID=sentence-transformers/all-MiniLM-L6-v2 -e PORT=8091 "$tei_image" >/dev/null
docker run -d --name smoke-rerank "${restricted[@]}" --tmpfs '/data:uid=1000,gid=1000' \
  -e MODEL_ID=cross-encoder/ms-marco-MiniLM-L-6-v2 -e PORT=8092 "$tei_image" >/dev/null
wait_for smoke-api http://127.0.0.1:8888/health
wait_for smoke-worker http://127.0.0.1:8889/health

docker run -d --name smoke-cp "${restricted[@]}" -e HINDSIGHT_DATAPLANE_HOST=smoke-api -e HINDSIGHT_DATAPLANE_PORT=8888 \
  -e HINDSIGHT_CP_PORT=3000 -e NODE_ENV=production "$cp_image" >/dev/null
wait_for smoke-cp http://127.0.0.1:3000/

docker exec smoke-api python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8888/v1/default/banks', timeout=5).read()[:200])"

for c in smoke-tei smoke-rerank smoke-api smoke-worker smoke-cp; do
  others=$(docker top "$c" -eo pid,uid,comm | tail -n +2 | awk '$2 != 1000')
  [ -z "$others" ] || { echo "$c runs a process as another uid: $others" >&2; exit 1; }
done
echo "smoke test passed"
