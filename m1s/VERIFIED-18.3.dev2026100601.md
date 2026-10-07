# Verified package — October 6, 2026

- Package: `haos_odroid-m1s-18.3.dev2026100601.raucb`.
- Size: 202,705,717 bytes (about 193 MiB).
- SHA-256: `6df329b11daa233a2f40f549a85ffe7763b93a8d2cb89ad64ef96e92774b96ce`.
- Base: verified official HAOS 18.3 M1S release.
- Contents: rebuilt kernel and rootfs with official userspace retained.
- Rootfs changes: matching kernel module tree, custom OS version, added public update certificate.
- No boot or SPL image payloads; normal slot selection/status writes still apply.

Mounted filesystem comparison preserved 5,923 official paths outside the module
tree and the two declared metadata files. It preserved 222 userspace hardlink
groups. Only three driver module files were added and no paths were removed.
The packaged module tree matches the kernel build. Required module signatures
verify against the module certificate embedded in the packaged kernel.
The kernel configuration delta is exactly RTW89_8851BU and its two selected
dependencies. The existing official board device tree matches the rebuilt one.

RAUC verified the signed update and complete verity payload. Both image hashes,
the original install-check hook and retained official update certificates were
verified. The selected artifact remains a draft; on-device installation, boot,
Wi-Fi traffic, Bluetooth coexistence and Home Assistant services are untested.

The earlier full-build `18.3.dev20261006` package is superseded for installation.
