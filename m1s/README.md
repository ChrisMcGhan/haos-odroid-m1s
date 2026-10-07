# ODROID-M1S Wi-Fi support with official userspace

Personal fork of [Home Assistant Operating System](https://github.com/home-assistant/operating-system).
Images built here are custom builds and are not official Home Assistant releases.

The selected installation package reuses official HAOS 18.3 userspace, replacing
only the kernel and its matching module tree. Its version is
`18.3.dev2026100601`. It contains **kernel and rootfs images only**: shared boot
files and SPL/bootloader images are omitted. The earlier full-build package
`18.3.dev20261006` is superseded and is retained only as a build reference.

The root filesystem preserves all official file contents, permissions,
ownership, xattrs, symlinks, file/symlink timestamps and userspace hardlinks
outside the module tree and two declared metadata files: `usr/lib/os-release`
(custom version) and `etc/rauc/keyring.pem` (our added public certificate).
Directory timestamps and inode numbers can change when repackaging. Official
firmware and userspace binaries are retained. The selected package booted on
ODROID-M1S on October 7, 2026; 5 GHz Wi-Fi association/traffic and Bluetooth
reception passed. Forced 2.4 GHz authentication and some post-reboot Home
Assistant device reconnections remain unresolved; see the verification record.

## Current patch and status

The UGREEN AX900 RTL8851BU adapter, USB ID `0bda:b851`, works with the native
Linux `rtw89_8851bu` driver. Official HAOS 18.3 has that kernel source, but omits
`CONFIG_RTW89_8851BU`. This fork enables it as a module; Kconfig selects its
USB transport and RTL8851B dependencies. The board already includes rtw89
firmware. Bluetooth uses the existing `btusb` driver.

| Item | Value |
| --- | --- |
| Upstream release | HAOS 18.3 |
| Upstream commit | `b22f929d3bc8895f5cf84d13d71a24714b59eed4` |
| Buildroot commit | `d2b75e0548bf1f0c56d17cac44d5fe9a0e17e60a` |
| Patch commit | `dda7fe9` |
| Kernel build reference | `18.3.dev20261006` (full build; superseded for installation) |
| Selected update version | `18.3.dev2026100601` (official userspace reused) |
| Target | `odroid_m1s` / `haos-odroid-m1s` |
| Validation | Package/signatures verified October 6; slot A boot, 5 GHz Wi-Fi traffic and Bluetooth reception passed October 7; follow-up gaps recorded in `VERIFIED-18.3.dev2026100601.md` |

The runtime patch and version label have separate commits. Fork-specific
documentation and helpers live under `m1s/`; upstream build machinery remains
in its original locations.

## Build and inspect

Clone this fork's patch branch with submodules. Docker must be running and have
enough disk space and at least 8 GB VM memory for the default limits. The helper
uses native Docker architecture and four compiler jobs. It streams the checkout
into a case-sensitive Linux volume, which avoids macOS filesystem problems.

```sh
git clone --branch codex/ugreen-rtl8851bu --recurse-submodules \
  https://github.com/ChrisMcGhan/haos-odroid-m1s.git
cd haos-odroid-m1s
m1s/scripts/run-build.sh
m1s/scripts/wait-and-verify.sh
mkdir -p m1s/artifacts/official
gh release download 18.3 --repo home-assistant/operating-system \
  --pattern haos_odroid-m1s-18.3.raucb --dir m1s/artifacts/official
m1s/scripts/package-reused-userspace.sh \
  m1s/artifacts/official/haos_odroid-m1s-18.3.raucb
```

The build/verification helper produces the matching kernel and modules. The
upstream build target compiles other components too, but the final packaging
step discards those rebuilt userspace and bootloader binaries and starts from
the verified official release filesystem. These scripts do not schedule a
recurring task. Run `docker logs --tail 30 haos-ugreen-build` for compile progress.
Completed packages and downloads remain cached in named Docker volumes.
After verification, the private signing key is retained in the dedicated
`haos-ugreen-signing` Docker volume and reused by future versioned builds.
Do not delete that volume when cleaning old build output. A copy also remains
inside the corresponding build volume; neither volume should be published.

Verification checks resolved driver options, module metadata and USB ID,
firmware, the extracted EROFS filesystem, retention of official update roots,
the bundle signature, board compatibility, version, and payload hashes.
Verified files are exported to `m1s/artifacts/`, which is excluded from Git.
Only the signed `.raucb`, public certificate, checksums, and verification
records are eligible for release assets. Never upload `key.pem` or a build
volume archive.

The selected bundle and its verification records are exported to
`m1s/artifacts/reused-userspace-18.3.dev2026100601/`. Packaging verifies the
official release digest/signature/payload, compares the actual mounted final
filesystem against the actual official filesystem, checks the matching module
tree and required module signatures, checks the exact three-option resolved
kernel delta, and verifies the final signature and both payload hashes.
See the [verified package record](VERIFIED-18.3.dev2026100601.md) for its exact
checksum, size, scope and remaining hardware tests. The package is narrower in
installation scope; it still contains complete kernel/rootfs images.

Its public signing
certificate SHA-256 fingerprint is
`AC:F3:C3:68:60:64:88:A0:79:2C:4C:3F:5D:E3:B3:9D:2F:09:CA:F4:A6:DF:7C:72:F2:49:03:14:B4:39:BA:35`.
The versioned GitHub draft release holds only public bundle/certificate/checksum
and verification assets. The selected update has not been booted or tested on
the ODROID. The superseded full-build draft must not be used for installation.

GitHub Actions is disabled for this fork. The inherited upstream workflow's
fallback can upload a generated signing key as an artifact. A future dedicated
M1S CI workflow should require persistent signing secrets, fail when they are
missing, and upload only verified public outputs. Source maintenance and
release storage on GitHub do not require hosted CI.

## Update the maintained fork

1. Fetch the next official stable tag from the `upstream` remote and inspect
   whether RTL8851BU has already been enabled.
2. Start a fresh `codex/` branch from that exact tag. Update its Buildroot
   submodule, then carry forward the driver commit only if still needed.
3. Set an explicit custom development version and carry forward this support
   directory. Review changes to kernel config, firmware, RAUC and bootloader
   packaging before rebuilding.
4. Update the packaging pins and verify a fresh kernel/rootfs update using the
   matching official release userspace. Do not reuse userspace across kernel or
   release changes without reviewing compatibility. Start its GitHub release as
   a draft and record
   the upstream tag/SHA, patch SHA, full version, certificate fingerprint and
   SHA-256 checksums. State hardware validation results explicitly.
5. Install and validate on the board before marking the release tested. Future
   official OS updates can replace this patch until it is included upstream.

After hardware validation, propose the driver-only commit against upstream
`dev`, following [HAOS's contribution instructions](https://developers.home-assistant.io/docs/operating-system/getting-started/).
An accepted official release would allow this custom build to be retired.

## Installation and rollback

HAOS uses signed RAUC A/B updates. Install the compatible verified bundle into
the inactive kernel/rootfs slot while retaining the working slot. Host access
and temporary trust of the custom public certificate are needed for the first
custom update; retain official roots and signature checking.

Before installing, retain a fresh Home Assistant backup outside the board and
confirm the current booted slot. Home Assistant data is shared between A/B.
The selected bundle omits shared boot files and SPL, so their install hooks are
not invoked. Normal slot selection/status still updates shared boot state;
Home Assistant data remains shared, so the other OS slot is not a full-system
snapshot. U-Boot permits three attempts per slot;
a successful boot with a functional regression can still be marked good.

After booting, verify driver binding and firmware startup, Wi-Fi discovery,
association and traffic, Bluetooth coexistence and existing HA services.
Keep Ethernet available. `ha os boot-slot <previous-slot>` selects the prior
OS slot; reboot and verify the selected version. Physical recovery may be
needed if the host cannot be reached.

See the [official update and signing documentation](https://developers.home-assistant.io/docs/operating-system/update-system/).
The build scripts do not install an image or reboot a board.

## Branches and release roles

- `codex/ugreen-rtl8851bu`: maintained default branch with packaging and documentation.
- `codex/haos-18.3-rtl8851bu`: official 18.3 source plus the single driver line.
- `dev`: inherited upstream reference; changes for upstream target its current dev branch.

The selected installation artifact is the reused-userspace draft
`18.3.dev2026100601`. The superseded full-build draft `18.3.dev20261006` is a
historical build reference. Inherited unrelated branch copies are removed from
this fork; upstream branches and release tags remain in the upstream project.
Use a new custom package version whenever replacing released artifact inputs.
