#!/bin/bash
# Runs the acceptance suite (ACCEPTANCE.md) from nothing:
#   docker compose up --build, wait healthy, pytest, docker compose down -v.
# Exit code is pytest's.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${HERE}/test/compose.yaml"
RESULTS_DIR="${HERE}/test-results"
mkdir -p "${RESULTS_DIR}"

cleanup() {
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
}
trap cleanup EXIT

echo "==> docker compose up (image: ${IMAGE:-iredmail/mariadb:stable})"
docker compose -f "${COMPOSE_FILE}" up -d --build
up_status=$?
if [ "${up_status}" -ne 0 ]; then
    echo "compose up failed (exit ${up_status})"
    exit "${up_status}"
fi

echo "==> waiting for both services to report healthy (up to 15 min for cold amd64-under-emulation pulls/first boot)"
deadline=$((SECONDS + 900))
while [ "${SECONDS}" -lt "${deadline}" ]; do
    statuses="$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.Service}} {{.Health}}')"
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
