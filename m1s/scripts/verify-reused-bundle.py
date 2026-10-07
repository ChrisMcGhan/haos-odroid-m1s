#!/usr/bin/env python3
"""Verify a two-image bundle, exact kernel config delta, and driver signatures."""
import hashlib
import json
import os
import re
import shlex
import struct
import subprocess
from pathlib import Path

work = Path(os.environ['TASK_REUSE_WORK'])
version = os.environ['TASK_REUSE_VERSION']
digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
run = lambda args, **kwargs: subprocess.run(args, check=True, **kwargs)
fields = {}
for line in Path('/public/bundle-info.shell').read_text().splitlines():
    if line.startswith('RAUC_') and '=' in line:
        key, value = line.split('=', 1)
        fields[key] = ' '.join(shlex.split(value))
assert fields['RAUC_MF_COMPATIBLE'] == 'haos-odroid-m1s'
assert fields['RAUC_MF_VERSION'] == version
assert fields['RAUC_MF_FORMAT'] == 'verity'
assert fields['RAUC_MF_IMAGES'] == '2'
assert {fields[f'RAUC_IMAGE_CLASS_{i}'] for i in range(2)} == {'kernel', 'rootfs'}
for i in range(2):
    image = work / 'verified' / fields[f'RAUC_IMAGE_NAME_{i}']
    assert image.stat().st_size == int(fields[f'RAUC_IMAGE_SIZE_{i}'])
    assert digest(image) == fields[f'RAUC_IMAGE_DIGEST_{i}']
    assert not fields[f'RAUC_IMAGE_HOOKS_{i}'], 'Unexpected image install hook'
assert fields['RAUC_MF_HOOKS'] == 'install-check'
release = (work / 'final-root/usr/lib/os-release').read_text()
assert f'VERSION_ID={version}\n' in release
certs = lambda p: set(re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', Path(p).read_text(), re.S))
assert certs(work / 'original-root/etc/rauc/keyring.pem').issubset(certs(work / 'final-root/etc/rauc/keyring.pem'))

for name, image in [('official', work / 'official/kernel.img'), ('custom', work / 'verified/kernel.img')]:
    run(['unsquashfs', '-d', str(work / f'{name}-kernel'), str(image)], stdout=subprocess.DEVNULL)
    result = subprocess.check_output(['/build/output/build/linux-6.18.52/scripts/extract-ikconfig', str(work / f'{name}-kernel/Image')], text=True)
    (work / f'{name}-kernel.config').write_text(result)
    if name == 'custom':
        assert result == Path('/build/output/build/linux-6.18.52/.config').read_text()
def config(path):
    result = {}
    for line in path.read_text().splitlines():
        if line.startswith('CONFIG_') and '=' in line:
            k, v = line.split('=', 1); result[k] = v
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            result[line.split()[1]] = 'n'
    return result
official = config(work / 'official-kernel.config'); custom = config(work / 'custom-kernel.config')
delta = {k: {'official': official.get(k, 'n'), 'custom': custom.get(k, 'n')}
         for k in official.keys() | custom.keys() if official.get(k, 'n') != custom.get(k, 'n')}
assert delta == {f'CONFIG_{k}': {'official': 'n', 'custom': 'm'}
                 for k in ('RTW89_USB', 'RTW89_8851B', 'RTW89_8851BU')}, delta
assert custom['CONFIG_MODULE_SIG_FORCE'] == official['CONFIG_MODULE_SIG_FORCE']

module_cert = work / 'module-cert.pem'
module_der = Path('/build/output/build/linux-6.18.52/certs/signing_key.x509').read_bytes()
assert module_der in (work / 'custom-kernel/Image').read_bytes(), 'Module trust certificate missing from packaged kernel'
run(['openssl', 'x509', '-inform', 'DER', '-in', '/build/output/build/linux-6.18.52/certs/signing_key.x509', '-out', str(module_cert)])
required = ('rtw89_core', 'rtw89_usb', 'rtw89_8851b', 'rtw89_8851bu', 'mac80211', 'cfg80211', 'btusb')
module_root = work / 'final-root/usr/lib/modules/6.18.52-haos'
records = ['Module-signing certificate is embedded in the packaged custom kernel: verified']
for name in required:
    matches = list(module_root.rglob(f'{name}.ko')); assert len(matches) == 1
    data = matches[0].read_bytes(); marker = b'~Module signature appended~\n'
    assert data.endswith(marker), name
    size = struct.unpack('>I', data[-len(marker)-4:-len(marker)])[0]
    end = len(data) - len(marker) - 12
    payload = work / 'module-content'; signature = work / 'module-signature.der'
    payload.write_bytes(data[:end-size]); signature.write_bytes(data[end-size:end])
    result = subprocess.run(['openssl', 'cms', '-verify', '-binary', '-inform', 'DER',
              '-in', str(signature), '-content', str(payload), '-certfile', str(module_cert),
              '-noverify', '-out', '/dev/null'], check=True, capture_output=True, text=True)
    records.append(f'{name}: {result.stderr.strip()}')
Path('/public/module-signature-verification.txt').write_text('\n'.join(records) + '\n')
provenance = {
    'version': version, 'packaging': 'official-userspace-custom-kernel',
    'official_source_commit': 'b22f929d3bc8895f5cf84d13d71a24714b59eed4',
    'official_bundle_sha256': digest(work / 'official.raucb'),
    'official_kernel_sha256': digest(work / 'official/kernel.img'),
    'official_rootfs_sha256': digest(work / 'official/rootfs.img'),
    'custom_kernel_sha256': digest(work / 'verified/kernel.img'),
    'packaged_rootfs_sha256': digest(work / 'verified/rootfs.img'),
    'kernel_configuration_delta': delta,
    'retained_official_keyring_certificates': True,
    'boot_and_spl_images': 'omitted; their install hooks are not invoked',
    'original_install_check_hook_sha256': digest(work / 'verified/hook'),
    'hardware_validation': 'not performed',
    'rauc_installation_validation': 'manifest and RAUC 1.13 source reviewed; on-device installation not performed',
}
Path('/public/provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print('Verified two-image manifest, original hook, kernel configuration delta and required module signatures.')
