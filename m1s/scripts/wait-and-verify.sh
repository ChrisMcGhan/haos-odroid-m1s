#!/bin/bash
set -euo pipefail
task_script_dir="$(cd "$(dirname "$0")" && pwd)"
while [ "$(docker inspect haos-ugreen-build --format '{{.State.Status}}')" = running ]; do
  sleep 30
done
task_exit="$(docker inspect haos-ugreen-build --format '{{.State.ExitCode}}')"
if [ "${task_exit}" != 0 ]; then
  docker logs --tail 80 haos-ugreen-build
  exit "${task_exit}"
fi
"${task_script_dir}/verify-and-export.sh"
