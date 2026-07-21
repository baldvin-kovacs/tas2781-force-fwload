# Changelog

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
