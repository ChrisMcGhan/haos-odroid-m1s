#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/settings.sh"
task_artifacts="${task_dir}/artifacts"
mkdir -p "${task_artifacts}"

docker run --rm -i --privileged --network none --entrypoint /bin/bash \
  -v "${build_volume}:/build" \
  -v "${signing_volume}:/signing" \
  -e TASK_VERSION_FULL="${task_version_full}" "${build_image}" -s <<'VERIFY'
set -euo pipefail
umask 077
test "$(cat /build/build.exit)" = 0
export PATH="/build/output/host/bin:/build/output/host/sbin:${PATH}"
task_review=/build/review-artifacts
mkdir -p "${task_review}"

task_kernel_config=/build/output/build/linux-6.18.52/.config
if [ ! -f "${task_kernel_config}" ]; then
  task_kernel_config="$(find /build/output/build -path '*/linux-*/.config' -print -quit)"
fi
test -f "${task_kernel_config}"
for task_option in RTW89 RTW89_CORE RTW89_USB RTW89_8851B RTW89_8851BU; do
  grep -qx "CONFIG_${task_option}=m" "${task_kernel_config}"
done
grep -E '^CONFIG_(RTW89|BT_HCIBTUSB|MAC80211)' "${task_kernel_config}" \
  > "${task_review}/resolved-driver-config.txt"

task_module="$(find /build/output/target/usr/lib/modules /build/output/target/lib/modules \
  -name 'rtw89_8851bu.ko*' -print -quit 2>/dev/null || true)"
task_firmware="$(find /build/output/target/usr/lib/firmware /build/output/target/lib/firmware \
  -name 'rtw8851b_fw.bin*' -print -quit 2>/dev/null || true)"
test -n "${task_module}" && test -f "${task_module}"
test -n "${task_firmware}" && test -f "${task_firmware}"
printf 'module=%s\nfirmware=%s\n' "${task_module}" "${task_firmware}" \
  > "${task_review}/packaging-check.txt"
sha256sum "${task_module}" "${task_firmware}" >> "${task_review}/packaging-check.txt"

task_extracted="$(mktemp -d /build/verify-rootfs.XXXXXX)"
trap 'rm -rf "${task_extracted}"' EXIT
fsck.erofs --extract="${task_extracted}" /build/output/images/rootfs.erofs \
  > "${task_review}/rootfs-check.txt" 2>&1
task_image_module="$(find "${task_extracted}/usr/lib/modules" \
  -name 'rtw89_8851bu.ko*' -print -quit)"
task_image_firmware="$(find "${task_extracted}/usr/lib/firmware" \
  -name 'rtw8851b_fw.bin*' -print -quit)"
test -n "${task_image_module}" && test -f "${task_image_module}"
test -n "${task_image_firmware}" && test -f "${task_image_firmware}"
cmp "${task_module}" "${task_image_module}"
cmp "${task_firmware}" "${task_image_firmware}"
kmod modinfo "${task_image_module}" > "${task_review}/driver-modinfo.txt"
grep -qi 'usb:v0BDApB851' "${task_review}/driver-modinfo.txt"
printf 'Extracted root filesystem matches driver and firmware staging files.\n' \
  >> "${task_review}/rootfs-check.txt"
openssl verify -CAfile "${task_extracted}/etc/rauc/keyring.pem" /build/cert.pem \
  >> "${task_review}/rootfs-check.txt"
python3 - "${task_extracted}/etc/rauc/keyring.pem" <<'PY'
import re,sys
from pathlib import Path
certs=lambda p:set(re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',Path(p).read_text(),re.S))
official=certs('/build/buildroot-external/ota/rel-ca.pem')
assert official and official.issubset(certs(sys.argv[1])), 'Official update trust roots missing'
print('Verified official trust roots retained in the root filesystem.')
PY

task_bundle="/build/output/images/haos_odroid-m1s-${TASK_VERSION_FULL}.raucb"
test -f "${task_bundle}"
rauc --keyring=/build/cert.pem info --output-format=shell "${task_bundle}" \
  > "${task_review}/bundle-info.shell"
python3 - "${task_review}" <<'PY'
import json,sys,shlex,hashlib,os
from pathlib import Path
review=Path(sys.argv[1])
fields={}
for line in (review/'bundle-info.shell').read_text().splitlines():
    if not line.startswith('RAUC_') or '=' not in line:
        continue
    key,value=line.split('=',1)
    parsed=shlex.split(value)
    fields[key]=' '.join(parsed)
assert fields['RAUC_MF_COMPATIBLE']=='haos-odroid-m1s', fields
assert fields['RAUC_MF_VERSION']==os.environ['TASK_VERSION_FULL'], fields
assert fields['RAUC_MF_FORMAT']=='verity', fields
classes={fields[f'RAUC_IMAGE_CLASS_{i}'] for i in range(int(fields['RAUC_MF_IMAGES']))}
assert classes=={'boot','kernel','rootfs','spl'}, classes
for i in range(int(fields['RAUC_MF_IMAGES'])):
    slotclass=fields[f'RAUC_IMAGE_CLASS_{i}']
    filename='rootfs.erofs' if slotclass=='rootfs' else fields[f'RAUC_IMAGE_NAME_{i}']
    image=Path('/build/output/images')/filename
    assert image.is_file(), image
    with image.open('rb') as stream:
        digest=hashlib.file_digest(stream,'sha256').hexdigest()
    assert digest==fields[f'RAUC_IMAGE_DIGEST_{i}'], (slotclass,digest)
    assert image.stat().st_size==int(fields[f'RAUC_IMAGE_SIZE_{i}']), slotclass
(review/'bundle-info.json').write_text(json.dumps(fields,indent=2)+'\n')
print('Verified signed ODROID-M1S verity bundle metadata.')
PY

cp "${task_bundle}" "${task_review}/"
cp /build/cert.pem "${task_review}/cert.pem"
openssl x509 -in /build/cert.pem -noout -fingerprint -sha256 \
  > "${task_review}/certificate-fingerprint.txt"
test "$(stat -c %a /build/key.pem)" = 600
if [ -f /signing/key.pem ]; then
  cmp /build/key.pem /signing/key.pem
  cmp /build/cert.pem /signing/cert.pem
else
  cp /build/key.pem /signing/key.pem
  cp /build/cert.pem /signing/cert.pem
  chmod 600 /signing/key.pem
fi
test "$(stat -c %a /signing/key.pem)" = 600
chown -R 1000:1000 /signing
cd "${task_review}"
sha256sum *.raucb cert.pem resolved-driver-config.txt packaging-check.txt \
  rootfs-check.txt driver-modinfo.txt bundle-info.json bundle-info.shell \
  certificate-fingerprint.txt > SHA256SUMS
printf 'Artifacts verified in %s\n' "${task_review}"
VERIFY

docker run --rm --network none --entrypoint /bin/tar \
  -v "${build_volume}:/build":ro \
  "${build_image}" -C /build/review-artifacts -cf - . | \
  tar -xf - -C "${task_artifacts}"
printf 'Exported verified artifacts to %s\n' "${task_artifacts}"
