#!/bin/bash
# Shared settings for the maintained M1S build. Source from another script.
task_source="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_dir="${task_source}/m1s"
task_major="$(sed -n 's/^VERSION_MAJOR="\([0-9]*\)"$/\1/p' "${task_source}/buildroot-external/meta")"
task_minor="$(sed -n 's/^VERSION_MINOR="\([0-9]*\)"$/\1/p' "${task_source}/buildroot-external/meta")"
task_suffix="$(sed -n 's/^VERSION_SUFFIX="\([A-Za-z0-9]*\)"$/\1/p' "${task_source}/buildroot-external/meta")"
task_version_main="${task_major}.${task_minor}"
task_version_full="${task_version_main}${task_suffix:+.${task_suffix}}"
[[ "${task_version_full}" =~ ^[0-9]+\.[0-9]+\.dev[0-9]+$ ]] || {
  printf 'Unexpected HAOS version: %s\n' "${task_version_full}" >&2
  return 1
}
build_image="haos-ugreen-builder:${task_version_main}"
build_volume="haos-ugreen-build-${task_version_main//./-}"
cache_volume="haos-ugreen-cache-${task_version_main//./-}"
signing_volume="haos-ugreen-signing"
build_container="haos-ugreen-build"
