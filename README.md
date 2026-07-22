# tas2781-force-fwload

**Restore woofer/bass output on Linux laptops with Texas Instruments TAS2781
smart amplifiers** (e.g. Lenovo Yoga Pro 9 16IMH9) by forcing the kernel
driver to fully re-stage the amplifier DSPs on every playback stream.

This is a clean, packaged workaround for a bug in the kernel's `tas2781-hda`
/ `tas2781-fmwlib` driver stack. An upstream kernel fix is planned (see
[Upstream status](#upstream-status)); until it lands, this package makes the
speakers work correctly today.

## The symptom

On affected machines, sound appears to work — but only the tweeters play.
Bass is absent, audio is thin and quiet. Confusingly:

- The **first** playback stream after a cold boot (or after suspend/resume)
  may have full, correct sound — then it never comes back.
- In practice even that first stream is usually already broken, because the
  desktop audio server (WirePlumber/PipeWire) opens and closes the device
  several times within seconds of login, silently consuming the one good
  cycle before you play anything.
- Mixer levels, routing, and driver state all *look* healthy.

## Is this your bug?

Two quick checks:

1. The kernel driver is `tas2781-hda`:

   ```
   ls /sys/bus/i2c/drivers/tas2781-hda/
   ```

   should list one or more bound i2c devices.

2. The tell-tale log signature. **The message is debug-level (`dev_dbg`), so
   it does not appear in dmesg by default** — enable it first (needs
   `CONFIG_DYNAMIC_DEBUG`, which is on in stock Arch/Debian/Ubuntu/Fedora
   kernels):

   ```
   echo 'func tasdevice_select_tuningprm_cfg +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
   ```

   Then play something, stop it, start playback again, and check:

   ```
   sudo dmesg | grep -i "Unneeded loading dsp conf"
   ```

   Repeated `tasdevice_select_tuningprm_cfg: Unneeded loading dsp conf 0`
   lines while your bass is missing confirm the bug. (Turn the logging back
   off with the same `echo` command, using `-p` instead of `+p`. Note that
   once this package's fix is active, the line disappears — forced staging
   makes the "unneeded" branch no longer taken.)

If the driver never binds at all (check 1 lists nothing and there are no
tas2781 messages in dmesg), see
[If the control never appears](#if-the-control-never-appears) below — on
kernels before 7.1 some machines additionally need an `hda_model` quirk.

## Root cause, in short

The TAS2781 amplifiers run a DSP program that the driver downloads over i2c.
The driver caches "program X / config Y already loaded" and skips re-staging
on every subsequent stream open. But on every stream **close** it sends the
firmware's `PRE_SHUTDOWN` sequence — and on affected platforms that shutdown
leaves the woofer DSP dead in a way the normal `PRE_POWER_UP` sequence (sent
on every open) does not revive. Register dumps show the DSP memory pages
zeroed after the shutdown/power-up round trip, while the driver still
believes the program is loaded.

Result: full staging happens exactly once per reset (cold boot or resume),
that one open/close cycle has correct sound, and every later open re-stages
nothing — tweeters only.

Full analysis with kernel code references and the evidence trail is in
[docs/TECHNICAL.md](docs/TECHNICAL.md).

## What this package does

The driver already exposes an escape hatch: the ALSA control
**`Speaker Force Firmware Load`**. When on, every PCM open bypasses the
"already loaded" cache and fully re-stages DSP program + config +
calibration on all amplifiers. This package simply makes that reliable and
automatic:

| Component | Installed as | Purpose |
|---|---|---|
| `tas2781-force-fwload` script + systemd service | `bin/`, systemd unit dir | Turns `Speaker Force Firmware Load` on at every boot (polls until the async firmware load exposes the control) |
| udev rule | `90-tas2781-no-runtime-pm.rules` | Pins the amps' runtime PM to `on` — with runtime autosuspend active the amps shut down after seconds of silence and the workaround is not reliable |
| modprobe config | `tas2781-force-fwload.conf` | `snd_hda_intel power_save=0`, so the HDA path is not power-cycled behind the driver's back |

Everything is plain shell + standard config files; dependencies are just
`alsa-utils` and systemd.

## The 2.5-second tradeoff

Full re-staging pushes the complete DSP program over i2c to every amplifier,
which takes time. Two user-visible consequences:

1. **~2.5 s of silence** at the start of each playback stream that begins
   after the sink has suspended (music resumes fine; the first couple of
   seconds are swallowed).
2. **Short sounds can vanish entirely** — a notification blip may fit
   entirely inside the silent staging window.

If this bothers you, install the optional WirePlumber drop-in from
[`extras/wireplumber/`](extras/wireplumber/): it keeps the speaker sink from
suspending, so streams close rarely and re-staging becomes a once-per-boot
cost instead of a once-per-song one. Instructions are in the file header.

## Installation

### Arch Linux

From the AUR (once published): `tas2781-force-fwload`.

Or build directly from this repo:

```
git clone https://github.com/baldvin-kovacs/tas2781-force-fwload
cd tas2781-force-fwload/packaging/arch
makepkg -si
```

### Other distributions (Debian, Ubuntu, Fedora, …)

```
git clone https://github.com/baldvin-kovacs/tas2781-force-fwload
cd tas2781-force-fwload
sudo make install
```

`make install` defaults to `/usr/local/bin` plus `/etc/systemd/system`,
`/etc/udev/rules.d`, `/etc/modprobe.d`. All paths are overridable — see the
Makefile header. `sudo make uninstall` removes everything.

### Enable and verify

```
sudo systemctl enable --now tas2781-force-fwload.service
sudo udevadm control --reload
sudo reboot   # cleanest way to apply the modprobe + udev pieces
```

After the reboot, log in, wait a minute for firmware load, then:

```
systemctl status tas2781-force-fwload          # active (exited), SUCCESS
amixer -c 0 cget iface=CARD,name='Speaker Force Firmware Load'   # values=on
```

(Adjust `-c 0` if your sound card has a different index; note the
`iface=CARD` — without it amixer reports "Cannot find the given element".)

Play music: expect the ~2.5 s lead-in, then full-range sound — and it should
**stay** full-range across stops, restarts, and suspend/resume.

## If the control never appears

On kernels **older than 7.1**, some machines have an SSID collision that
makes the generic SOF HDA driver pick the wrong quirk table, so the TAS2781
side-codec never binds and the `Speaker Force Firmware Load` control never
exists. The Lenovo Yoga Pro 9 16IMH9 is one such machine (codec SSID
`17aa:38d6` vs PCI SSID `17aa:3811`; fixed upstream in 7.1).

See
[`extras/modprobe.d/tas2781-hda-model-quirk.conf.example`](extras/modprobe.d/tas2781-hda-model-quirk.conf.example)
for the one-line `hda_model=` fix and how to find your machine's codec SSID.

## Upstream status

The underlying bug is that `tasdevice_select_tuningprm_cfg()` (in
`sound/soc/codecs/tas2781-fmwlib.c`) trusts its `cur_prog`/`cur_conf` cache
across amplifier shutdown — i.e. it assumes DSP memory survives the
`PRE_SHUTDOWN` → `PRE_POWER_UP` round trip, which is not true on this
hardware. The planned upstream fix is to invalidate that cache when the
amplifiers are shut down (or to re-stage on power-up), so that a normal
stream open after shutdown restores the DSP without user configuration.

A kernel patch based on the evidence in [docs/TECHNICAL.md](docs/TECHNICAL.md)
is in preparation. Once a fixed kernel is widespread, this package becomes
unnecessary — that is the goal.

The related SSID-collision bind bug is already fixed in kernel 7.1.

## Tested hardware

| Machine | Kernel | Result |
|---|---|---|
| Lenovo Yoga Pro 9 16IMH9 (83DN) — 4× TAS2781 woofers + codec-driven tweeters | 7.0.14-arch1 | Verified: trace-level (full re-staging on every open, no more "Unneeded" short-circuit) and by ear, across repeated open/close cycles and suspend/resume |

The mechanism is generic to the `tas2781-hda` driver, so other TAS2781
laptops (various Lenovo Legion / ThinkPad / Yoga models and others) that show
the same "Unneeded loading dsp conf" signature with missing bass are expected
to benefit. If you try it on another model, please open an issue with your
machine, kernel version, and result — confirmations and failures are equally
valuable for the upstream report.

## License

[MIT](LICENSE).
