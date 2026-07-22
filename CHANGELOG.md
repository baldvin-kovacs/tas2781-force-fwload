# Changelog

## 0.2.2 — 2026-07-22

Release engineering only, no functional changes.

- Release tags are now GPG-signed.
- Source tarballs are published as GitHub release assets together with a
  detached PGP signature; the PKGBUILD verifies them via `validpgpkeys`
  (key `1C711551878F8E1EC2F47E37F57A7B17F6FFB8C8`, Baldvin Kovacs
  <baldvin@baldvin.net>, fetchable from keys.openpgp.org).
- First release published to the AUR as `tas2781-force-fwload`.

## 0.2.1 — 2026-07-22

- tas2781-win-fw: the pacman hook no longer executes the tool from wherever
  it happened to be run (a git checkout the user didn't know they had to
  keep). It now runs a generated, self-contained `reapply.sh` inside
  `/var/lib/tas2781-force-fwload/` — the override keeps re-applying itself
  even if the checkout, or the package, is later removed. Users with a
  0.2.0-era hook: rerun `install` once to regenerate it.

## 0.2.0 — 2026-07-22

- New optional tool `tas2781-win-fw`: install the TAS2781 DSP firmware from
  the user's own Windows installation (mounted partition, directory, or
  extracted file) as a persistent override. Validates the blob header,
  backs up the stock file, and on Arch writes a pacman PostTransaction hook
  so the override survives `pacman -Syu` / linux-firmware upgrades.
  `status` / `reapply` / `revert` subcommands included. The firmware itself
  is proprietary and is NOT distributed with this project.
- docs: side finding written up — the Windows driver ships a 10-day-newer
  revision of the same tuning differing only in five DRC/limiter DSP words
  (thresholds −5.5/−0.5 dB, steps 1.5→1.0 dB); identical below threshold.

## 0.1.1 — 2026-07-22

Documentation fix, no functional changes.

- The "Unneeded loading dsp conf" diagnostic message is a `dev_dbg()` and is
  invisible without dynamic debug — the 0.1.0 README implied it shows up in
  dmesg by default, which would falsely rule out affected machines. The
  "Is this your bug?" section now walks through enabling the callsite via
  `/sys/kernel/debug/dynamic_debug/control` first.

## 0.1.0 — 2026-07-21

Initial release.

- `tas2781-force-fwload` script + systemd oneshot service: turn
  `Speaker Force Firmware Load` on at boot (polls for the control while the
  TAS2781 firmware loads asynchronously).
- udev rule pinning runtime PM to `on` for devices bound to `tas2781-hda`.
- modprobe drop-in setting `snd_hda_intel power_save=0`.
- Optional extras: WirePlumber keep-sink-open drop-in (hides the ~2.5 s
  re-staging lead-in), `hda_model` quirk example for kernels < 7.1.
- Verified on Lenovo Yoga Pro 9 16IMH9 (83DN), kernel 7.0.14-arch1.
