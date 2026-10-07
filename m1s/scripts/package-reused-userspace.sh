#!/bin/bash
# Package official 18.3 userspace with the verified custom kernel/module set.
# This is packaging only: it never connects to or installs on the ODROID.
set -euo pipefail
. "$(dirname "$0")/settings.sh"
test "$#" = 1 || { printf 'Usage: %s /path/to/haos_odroid-m1s-18.3.raucb\n' "$0" >&2; exit 1; }
task_official_dir="$(cd "$(dirname "$1")" && pwd)"
task_official_name="$(basename "$1")"
test "${task_official_name}" = haos_odroid-m1s-18.3.raucb
task_reuse_version=18.3.dev2026100601
task_reuse_artifacts="${task_dir}/artifacts/reused-userspace-${task_reuse_version}"
mkdir -p "${task_reuse_artifacts}"

docker run --rm -i --privileged --network none --cpus=4 --memory=6g \
  --entrypoint /bin/bash \
  -v "${build_volume}:/build":ro -v "${signing_volume}:/signing":ro \
  -v "${task_official_dir}:/official":ro \
  -v "${task_source}/m1s/scripts:/scripts":ro \
  -v "${task_reuse_artifacts}:/public" \
  -e TASK_REUSE_VERSION="${task_reuse_version}" \
  "${build_image}" -s <<'PACKAGE'
set -euo pipefail
umask 077
export PATH="/build/output/host/bin:${PATH}"
task_work="$(mktemp -d /tmp/haos-reuse.XXXXXX)"
cleanup() {
  for task_mount in final-root original-root; do
    mountpoint -q "${task_work}/${task_mount}" && umount "${task_work}/${task_mount}" || true
  done
  rm -rf "${task_work}"
}
trap cleanup EXIT
printf '%s  %s\n' \
  708bf6c4d031f9f3ebec49594af8a517f1b68f6850f6afca17b8802df884e365 \
  /official/haos_odroid-m1s-18.3.raucb | sha256sum -c -
printf '%s  %s\n' \
  8774b2874ed1a83d7ac802cb0987d3ecf098ea06703ef25c1a6501198ff35ff6 \
  /build/output/images/kernel.img | sha256sum -c -
test "$(cat /build/build.exit)" = 0
cmp /build/cert.pem /signing/cert.pem
cmp /build/key.pem /signing/key.pem

cp /official/haos_odroid-m1s-18.3.raucb "${task_work}/official.raucb"
rauc --keyring=/build/buildroot-external/ota/rel-ca.pem info \
  --output-format=shell "${task_work}/official.raucb" > /public/official-info.shell
rauc --keyring=/build/buildroot-external/ota/rel-ca.pem extract \
  "${task_work}/official.raucb" "${task_work}/official"
mkdir -p "${task_work}/original-root" "${task_work}/final-root"
mount -t erofs -o loop,ro "${task_work}/official/rootfs.img" "${task_work}/original-root"
cp -a "${task_work}/original-root" "${task_work}/root"
fsck.erofs --extract="${task_work}/custom-root" --xattrs /build/output/images/rootfs.erofs
rm -rf "${task_work}/root/usr/lib/modules"
cp -a "${task_work}/custom-root/usr/lib/modules" "${task_work}/root/usr/lib/modules"
cat /signing/cert.pem >> "${task_work}/root/etc/rauc/keyring.pem"
python3 - "${task_work}/root/usr/lib/os-release" <<'VERSION'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]); text=p.read_text()
assert 'VERSION_ID=18.3\n' in text
p.write_text(text.replace('18.3',os.environ['TASK_REUSE_VERSION']))
VERSION
openssl verify -CAfile "${task_work}/root/etc/rauc/keyring.pem" /signing/cert.pem
cmp "${task_work}/original-root/usr/lib/firmware/rtw89/rtw8851b_fw.bin" \
  "${task_work}/custom-root/usr/lib/firmware/rtw89/rtw8851b_fw.bin"

mkdir "${task_work}/content"
cp /build/output/images/kernel.img "${task_work}/content/kernel.img"
mkfs.erofs --quiet -b4096 -zlz4hc,12 -C262144 -Ededupe -Efragments -Eztailpacking \
  --preserve-mtime --mkfs-time -T "$(date +%s)" \
  "${task_work}/content/rootfs.img" "${task_work}/root" > /public/filesystem-check.txt
fsck.erofs --extract "${task_work}/content/rootfs.img" >> /public/filesystem-check.txt
mount -t erofs -o loop,ro "${task_work}/content/rootfs.img" "${task_work}/final-root"
python3 /scripts/audit-reused-userspace.py "${task_work}/original-root" \
  "${task_work}/final-root" "${task_work}/custom-root/usr/lib/modules" \
  /public/reuse-comparison.json
cmp "${task_work}/original-root/etc/rauc/system.conf" "${task_work}/final-root/etc/rauc/system.conf"
cp "${task_work}/official/hook" "${task_work}/content/hook"
cat > "${task_work}/content/manifest.raucm" <<MANIFEST
[update]
compatible=haos-odroid-m1s
version=${TASK_REUSE_VERSION}
description=Official HAOS 18.3 userspace with RTL8851BU-enabled kernel and matching modules

[bundle]
format=verity

[hooks]
filename=hook
hooks=install-check;

[image.kernel]
filename=kernel.img

[image.rootfs]
filename=rootfs.img
MANIFEST

rauc --cert=/signing/cert.pem --key=/signing/key.pem \
  --signing-keyring=/signing/cert.pem bundle "${task_work}/content" "${task_work}/reused.raucb"
rauc --keyring=/signing/cert.pem info --output-format=shell \
  "${task_work}/reused.raucb" > /public/bundle-info.shell
rauc --keyring=/signing/cert.pem extract "${task_work}/reused.raucb" "${task_work}/verified"
cmp "${task_work}/content/kernel.img" "${task_work}/verified/kernel.img"
cmp "${task_work}/content/rootfs.img" "${task_work}/verified/rootfs.img"
cmp "${task_work}/official/hook" "${task_work}/verified/hook"
test ! -e "${task_work}/verified/boot.vfat"
test ! -e "${task_work}/verified/spl.img"
export TASK_REUSE_WORK="${task_work}"
python3 /scripts/verify-reused-bundle.py
cp "${task_work}/reused.raucb" "/public/haos_odroid-m1s-${TASK_REUSE_VERSION}.raucb"
cp /signing/cert.pem /public/cert.pem
cp "${task_work}/verified/manifest.raucm" /public/manifest.raucm
openssl x509 -in /signing/cert.pem -noout -fingerprint -sha256 > /public/certificate-fingerprint.txt
cd /public
sha256sum *.raucb cert.pem manifest.raucm official-info.shell bundle-info.shell \
  reuse-comparison.json provenance.json filesystem-check.txt \
  module-signature-verification.txt certificate-fingerprint.txt > SHA256SUMS
printf 'Verified reused-userspace bundle exported. Hardware validation remains pending.\n'
PACKAGE

(cd "${task_reuse_artifacts}" && shasum -a 256 -c SHA256SUMS)
printf 'Prepared %s\n' "${task_reuse_artifacts}"
