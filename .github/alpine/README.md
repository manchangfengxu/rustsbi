# Alpine Linux boot coverage

This implements [issue #377](https://github.com/rustsbi/rustsbi/issues/377),
part of [#307](https://github.com/rustsbi/rustsbi/issues/307).

## Scope and Inputs

Use the official Alpine 3.23.3 riscv64 standard ISO as a read-only live system.
Its kernel, initramfs, packages, modloop and GRUB come from the same verified
release. Reaching its normal OpenRC login and executing commands in its root
shell is the userspace milestone; an installed writable system is not required.

| Boot path | Chain | Firmware/payload |
| --- | --- | --- |
| `sbi` | RustSBI -> Alpine Linux -> OpenRC -> shell | Current dynamic firmware; ISO kernel and initramfs |
| `u-boot` | RustSBI -> U-Boot -> GRUB EFI -> Alpine -> shell | Ubuntu `u-boot-qemu` 2025.10-0ubuntu0.24.04.2, S-mode ELF |
| `edk2` | RustSBI -> EDK II -> GRUB EFI -> Alpine -> shell | Ubuntu `qemu-efi-riscv64` 2024.02-2ubuntu0.9, CODE/VARS pflash |

The script pins all three downloads by SHA-256 and verifies cached downloads
again on every run. RustSBI is built from the checkout and is never cached.
Fresh per-run directories contain extracted inputs, a serial FIFO and writable
UEFI variables. They are removed on exit; serial logs are retained separately.
The CI runner is Ubuntu 24.04, with QEMU package
`1:8.2.2+ds-0ubuntu1.18`. QEMU uses TCG, two harts, 2 GiB RAM and `virt,acpi=off`.

## Sources and Confirmed Assumptions

Consulted on 2026-10-02:

- [Alpine RISC-V support](https://wiki.alpinelinux.org/wiki/Riscv64).
- [Alpine QEMU guide](https://wiki.alpinelinux.org/wiki/Running_Alpine_riscv64_as_a_QEMU_guest):
  direct kernel/initramfs boot, ISO boot through U-Boot/GRUB or EDK II/GRUB,
  S-mode U-Boot, and the required `acpi=off` option.
- [Official release directory](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/riscv64/)
  and [ISO SHA-256](https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/riscv64/alpine-standard-3.23.3-riscv64.iso.sha256).
- [QEMU RISC-V firmware documentation](https://www.qemu.org/docs/master/system/target-riscv.html#risc-v-cpu-firmware):
  supply an explicit `-bios` to replace QEMU's default OpenSBI.
- Repository [Ubuntu boot test](../scripts/prototyper-ubuntu-boot.sh):
  the fixed Ubuntu U-Boot and EDK II package URLs, hashes and payload layouts.
- [RustSBI contribution rules](https://github.com/rustsbi/slides/blob/main/2025/reports/Contributing%20to%20RustSBI.md).

Local source snapshots were downloaded to `target/alpine/reference/` before
implementation. These are reference material, not executable CI inputs:

| Snapshot | SHA-256 |
| --- | --- |
| `riscv64.wiki` | `37e03019c84fe310cb95aa37b445af1b1661f67a5d94d24cc9c95bde8e5be2b3` |
| `qemu-guest.wiki` | `530d46a7fea89370a3e2d87857372028f7c31a505f36d03085ff5b4a3daabac8` |
| QEMU v10.2.2 `qemu-riscv.rst` | `316fba4ece60b6bbe559b7e2597278fdae5cca2d28d69fdefc0b8ae3fd055bfe` |
| `commit-guidelines.md` | `3152858f6ddffadddc42b0e7f46a85696da755e35650ad63fa89feceda8a74c8` |

The guide's example Edge `u-boot-qemu-2026.01-r0.apk` URL returned HTTP 404.
The boot test instead uses the repository's fixed Ubuntu package. The guide
describes an `extlinux.conf` regression in U-Boot 2025.10; this test boots the
ISO's GRUB EFI image. Its actual boot result, rather than a version assumption,
determines acceptance. U-Boot warnings about persisting EFI variables on
read-only media are not fatal by themselves.

## Implementation Route

- [x] Download references and verify the official ISO checksum.
- [x] Build the checkout's dynamic firmware and manually confirm direct boot.
- [x] Implement three boot paths, serial interaction and CI matrix.
- [x] Validate the complete matrix on the CI QEMU version.
- [x] Check failure handling and retained logs.
- [x] Review the diff and prepare an English commit referencing #377, with signoff.

## Run and Acceptance

Install `curl`, `xorriso`, `gzip`, `dpkg` and `qemu-system-riscv64`, plus the
firmware build dependencies documented in `firmware/README.md`. Then run:

```bash
cargo prototyper build
.github/scripts/prototyper-alpine-boot.sh sbi
.github/scripts/prototyper-alpine-boot.sh u-boot
.github/scripts/prototyper-alpine-boot.sh edk2
```

Acceptance requires all of the following for each path:

1. Verified download digests and the checkout's RustSBI banner.
2. The expected bootloader banner and GRUB boot entry on bootloader paths.
3. Alpine's OpenRC startup and riscv64 serial login.
4. A root-shell command confirms `ID=alpine`, release 3.23.3, architecture
   `riscv64`, kernel `6.18.7-0-lts`, PID 1 `init`, a readable device tree, and
   successful `apk --version`. EFI must exist on both GRUB paths and be absent
   on direct boot.
5. A complete `RUSTSBI-ALPINE-SMOKE-OK <path>` output line, followed by successful
   guest poweroff and QEMU exit status zero. Echoing the command does not count.
6. No fatal boot or guest assertion error, and completion within 300 seconds.

Failure checks cover missing markers, echoed markers, fatal errors, nonzero
QEMU exits and timeout. Logs must survive every failure. The workflow runs on
relevant pull requests to `main` and pushes to `main` or `ci/**`, supports manual
dispatch, and always attempts to upload each path's log. Pushing a `ci/` branch
also runs the matrix in a fork before opening an upstream pull request.

Override `ALPINE_QEMU` to test another emulator binary, `ALPINE_RUSTSBI` to test
a firmware input, and `ALPINE_BOOT_TIMEOUT_SECS` to shorten failure experiments.
`ALPINE_CACHE_DIR`, `ALPINE_WORK_DIR` and `QEMU_LOG_DIR` select local directories.
The defaults keep generated inputs under `target/` and logs under `qemu-logs/`.

## Local Results

On 2026-10-02, the default dynamic firmware built from base commit
`6d17ddca8bbd1564209c9736052696aa563a7661` passed all three paths on both
QEMU versions below. Each run confirmed the shell assertions, emitted its
complete success marker, and powered off with QEMU exit status zero.

| Emulator | `sbi` | `u-boot` | `edk2` |
| --- | --- | --- | --- |
| Ubuntu QEMU 8.2.2 (`1:8.2.2+ds-0ubuntu1.18`, CI input) | Pass | Pass | Pass |
| QEMU 10.2.2 | Pass | Pass | Pass |

Local logs are under `qemu-logs/alpine-qemu-8.2.2/` and
`qemu-logs/alpine-qemu-10.2.2/`. The Ubuntu QEMU package SHA-256 was checked
against the current official `noble-updates` package index:
`1c24233206744c634135fb1c374cfbd1238c09bc5563fb5a46f48dcb5552504e`.

`.github/alpine/test-boot-checks.sh` exercises the host's serial checks with
controlled output. Its 12 cases cover success, CR-terminated serial output,
an early success marker, a missing marker, command echo, a wrong boot-path
marker, missing RustSBI evidence, failed guest assertions, a panic following
a success marker, nonzero QEMU exit, boot timeout and shutdown timeout.
Every case also checks that cleanup retains the log. This suite is run in CI
before the real guest test; controlled output does not replace boot validation.

A real QEMU 8.2.2 run with `ALPINE_BOOT_TIMEOUT_SECS=1` returned exit status
one, stopped the emulator and retained its log under `qemu-logs/alpine-timeout/`.
ShellCheck 0.9.0, actionlint 1.7.12 and shell syntax checks also passed.

The complete hosted GitHub Actions run remains to be checked after submission.
