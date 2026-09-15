#!/bin/bash
# Runs the acceptance suite (ACCEPTANCE.md) from nothing:
#   docker compose up --build, wait healthy, pytest, docker compose down -v.
# Exit code is pytest's.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-iredmail-phase-a:dev}"
# Row 13 (restart + upgrade) needs a second tag; the same tag proves the
# restart half and the migration path stays exercised on every run.
export IMAGE IMAGE_NEXT="${IMAGE_NEXT:-$IMAGE}"
COMPOSE_FILE="${HERE}/test/compose.yaml"
COMPOSE_ARGS=(-f "${COMPOSE_FILE}")
# The admin-shim overlay is only correct for the official image - see
# test/compose.official-shim.yaml and test/README.md "The admin contract".
if [ "${IMAGE}" = "iredmail/mariadb:stable" ]; then
    COMPOSE_ARGS+=(-f "${HERE}/test/compose.official-shim.yaml")
fi
RESULTS_DIR="${HERE}/test-results"
mkdir -p "${RESULTS_DIR}"

cleanup() {
    docker compose "${COMPOSE_ARGS[@]}" down -v --remove-orphans
}
trap cleanup EXIT

echo "==> docker compose up (image: ${IMAGE})"
docker compose "${COMPOSE_ARGS[@]}" up -d --build
up_status=$?
if [ "${up_status}" -ne 0 ]; then
    echo "compose up failed (exit ${up_status})"
    exit "${up_status}"
fi

echo "==> waiting for both mail servers to report healthy (up to 15 min for cold amd64-under-emulation pulls/first boot)"
deadline=$((SECONDS + 900))
while [ "${SECONDS}" -lt "${deadline}" ]; do
    # only mail-a/mail-b have a healthcheck - the dns sidecar doesn't, and
    # would otherwise show an empty Health forever.
    statuses="$(docker compose "${COMPOSE_ARGS[@]}" ps --format '{{.Service}} {{.Health}}' | grep '^mail-')"
    if echo "${statuses}" | awk '{print $2}' | grep -qv '^healthy$'; then
        sleep 5
        continue
    fi
    if [ -n "${statuses}" ]; then
        echo "==> healthy: ${statuses}"
        break
    fi
    sleep 5
done

python3 -m venv "${HERE}/.venv-test" 2>/dev/null || true
if [ -x "${HERE}/.venv-test/bin/pip" ]; then
    "${HERE}/.venv-test/bin/pip" install -q -r "${HERE}/test/requirements.txt"
    PYTEST="${HERE}/.venv-test/bin/pytest"
else
    pip3 install -q -r "${HERE}/test/requirements.txt"
    PYTEST=pytest
fi

echo "==> pytest"
"${PYTEST}" "${HERE}/test" \
    --junitxml="${RESULTS_DIR}/junit.xml" \
    -v
pytest_status=$?

exit "${pytest_status}"
