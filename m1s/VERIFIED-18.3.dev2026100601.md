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
The packaged module tree matches the kernel build. All 4,039 packaged module
signatures verify against the module certificate embedded in the packaged kernel.
The kernel configuration delta is exactly RTW89_8851BU and its two selected
dependencies. The existing official board device tree matches the rebuilt one.

RAUC verified the signed update and complete verity payload. Both image hashes,
the original install-check hook and retained official update certificates were
verified. At package verification on October 6, on-device installation and
hardware testing had not been performed. The artifact remains a draft.

The earlier full-build `18.3.dev20261006` package is superseded for installation.

## Astra review follow-up — October 6, 2026

The maintained verifier now checks every packaged `.ko` file and uses OpenSSL
`-nointern` to require the designated kernel certificate rather than any
certificate supplied inside a module signature. The strengthened verifier passed
against the existing package. Negative checks rejected an unrelated signing
certificate and modified module content. The package SHA-256 above is unchanged;
this follow-up changes verification tooling, not firmware contents.

## On-device installation — October 7, 2026

A fresh full Home Assistant backup was copied off the board, with matching
SHA-256 hashes and compressed archive integrity verified. The board then
verified the transferred bundle's signature and complete payload. RAUC installed
the two images into slot A, and the board booted `18.3.dev2026100601` with A marked
good. Full partition hashes confirmed that official slot B was unchanged;
the shared boot script and board DTB were also unchanged.

The native `rtw89_8851bu` driver bound to USB `0bda:b851`, loaded the existing
firmware and created a Wi-Fi interface. Kernel taint is zero. A 5 GHz connection
passed ten gateway pings with zero packet loss, and another ten passed while
Bluetooth scanned. Bluetooth reception observed 26 distinct addresses initially
and 27 during the traffic overlap. This is a short functional test, not a
throughput or long-term stability result. Ethernet remained the primary route;
the temporary Wi-Fi connection was removed afterward.

Two follow-up gaps remain: the access point rejected forced 2.4 GHz
authentication with status 37, and two Matter devices plus some Alexa controls
remained unavailable after reboot. Their causes have not been established.
Supervisor reports healthy/supported, all previously running apps restarted,
and the local Thread border router rejoined as a router. Device reconnection
follow-up is pending; this record does not claim that every Home Assistant
device passed validation.
