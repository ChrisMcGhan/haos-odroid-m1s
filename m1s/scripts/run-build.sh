#!/bin/bash
set -euo pipefail

. "$(dirname "$0")/settings.sh"

docker info >/dev/null
if docker container inspect "${build_container}" >/dev/null 2>&1; then
  if [ "$(docker container inspect -f '{{.State.Running}}' "${build_container}")" = true ]; then
    printf 'Build container %s is already running.\n' "${build_container}"
    exit 0
  fi
  # Build output, cache and signing material remain in dedicated volumes.
  docker container rm "${build_container}" >/dev/null
fi
docker build -t "${build_image}" "${task_source}"
docker volume create "${build_volume}" >/dev/null
docker volume create "${cache_volume}" >/dev/null
docker volume create "${signing_volume}" >/dev/null

# Stream sources into the Linux volume; no macOS bind mount is required.
# Kernel sources and intermediate files need a case-sensitive filesystem.
task_meta_hash="$(shasum -a 256 "${task_source}/buildroot-external/meta" | awk '{print $1}')"
task_config_hash="$(shasum -a 256 "${task_source}/buildroot-external/kernel/v6.18.y/device-support-wireless.config" | awk '{print $1}')"
COPYFILE_DISABLE=1 tar --no-xattrs --no-acls --exclude=./m1s/artifacts \
  --exclude=./m1s/\*.log --exclude=./key.pem --exclude=./cert.pem \
  -C "${task_source}" -cf - . | \
docker run --rm -i --network none --entrypoint /bin/bash \
  -v "${build_volume}:/build" -v "${cache_volume}:/cache" \
  -e TASK_META_HASH="${task_meta_hash}" -e TASK_CONFIG_HASH="${task_config_hash}" \
  "${build_image}" -c '
    set -e
    if [ ! -e /build/.task-source-initialized ]; then
      tar -xf - -C /build
      chown -R 1000:1000 /build /cache
      touch /build/.task-source-initialized
    else
      tar -tf - >/dev/null
      printf "%s  %s\n" "$TASK_META_HASH" /build/buildroot-external/meta | sha256sum -c -
      printf "%s  %s\n" "$TASK_CONFIG_HASH" /build/buildroot-external/kernel/v6.18.y/device-support-wireless.config | sha256sum -c -
    fi'

docker run --detach --name "${build_container}" --privileged \
  --cpus=6 --memory=7g \
  -v "${build_volume}:/build" -v "${cache_volume}:/cache" \
  -v "${signing_volume}:/signing:ro" \
  -e BUILDER_UID=1000 -e BUILDER_GID=1000 \
  "${build_image}" /bin/bash -c '
    set -euo pipefail
    umask 077
    if [ -f /signing/key.pem ]; then
      cp /signing/key.pem /build/key.pem
      cp /signing/cert.pem /build/cert.pem
      chmod 600 /build/key.pem
    fi
    set +e
    make odroid_m1s BR2_JLEVEL=4 2>&1 | tee /build/build.log
    build_status=${PIPESTATUS[0]}
    printf "%s\n" "$build_status" > /build/build.exit
    exit "$build_status"'

printf 'Build started. Follow with: docker logs --tail 30 %s\n' "${build_container}"
