# TAS2781 on Linux: why the bass dies, and why forcing firmware load fixes it

This document is the distilled result of a multi-session investigation on a
Lenovo Yoga Pro 9 16IMH9 (83DN): kernel-source analysis, always-on ftrace of
the tas2781 modules and the i2c bus, amplifier register dumps in good and bad
states, and by-ear verification. It contains the conclusions only, so it can
serve as the basis for an upstream kernel fix.

Kernel referenced throughout: **7.0.14** (Arch). Relevant sources:

- `sound/hda/codecs/side-codecs/tas2781_hda*.c` — the HDA side-codec glue
- `sound/soc/codecs/tas2781-fmwlib.c` — firmware download / DSP staging

## Hardware background (Yoga Pro 9 16IMH9)

- Intel SOF platform, card `sof-hda-dsp`, Realtek ALC287 codec.
- 4× TI TAS2781 smart amplifiers on i2c bus 4 (ACPI `TIAS2781`), addresses
  `0x38`, `0x3d` (right) and `0x3e`, `0x3f` (left). **All four drive
  woofers.** The tweeters hang off the ALC287 itself (pin 0x14) and never
  touch the TAS path — which is why the failure mode is "thin, quiet,
  bass-less sound" rather than total silence.
- Firmware: `TAS2XXX38D6.bin` (a genuine 4-device DSP program: one program
  "Tuning Mode", one playback config) plus `TIAS2781RCA*.bin` (which, when
  parsed, registers the ALSA controls — including the one this project uses).
  Firmware loads asynchronously, typically 10–20 s after boot.

## The bug

### 1. The driver caches "already loaded" across amplifier shutdown

`tasdevice_select_tuningprm_cfg()` (tas2781-fmwlib.c, ~line 2639 in 7.0.14)
runs on every PCM open and decides what to (re-)stage:

- The DSP **program** is downloaded only when
  `cur_prog != prm_no || force_fwload_status`.
- The **config and calibrated data** (`tasdev_load_calibrated_data()`,
  ~line 2688) only when `cur_conf != cfg_no`.

After the first successful staging, `cur_prog`/`cur_conf` match forever, so
every later open logs

```
tasdevice_select_tuningprm_cfg: Unneeded loading dsp conf 0
```

and stages nothing. (That line is a `dev_dbg()` — it only reaches dmesg with
dynamic debug enabled for `snd_soc_tas2781_fmwlib`, e.g.
`echo 'func tasdevice_select_tuningprm_cfg +p' > /sys/kernel/debug/dynamic_debug/control`.
The README's diagnostic section walks users through this.)

### 2. Stream close kills the DSP that the cache says is loaded

Every PCM **close** writes the firmware's `PRE_SHUTDOWN` register sequence to
the amplifiers. On this platform, that shutdown leaves the woofer DSP dead in
a way the `PRE_POWER_UP` sequence (written on every open) does **not**
revive. Register evidence: after a shutdown → power-up round trip, the DSP
memory pages read back zeroed (captured on amp `0x3e`), while the driver's
`cur_prog`/`cur_conf` still claim the program is resident.

So the invariant the cache relies on — *DSP contents survive between opens* —
is false here. Net behavior:

- reset + `prmg_load` (cold boot **or** system resume) → the **first** open
  does full staging → correct full-range sound for exactly that one
  open/close cycle;
- every subsequent open → "Unneeded", nothing staged → tweeters only.

### 3. The desktop audio server consumes the one good cycle

This is why users essentially never hear the good cycle: on a session-9 boot
trace, the greeter's WirePlumber performed the first PCM open at t=20.4 s
(full staging), followed by a ~10-open probe storm from the greeter and the
login session — all "Unneeded". The user's first real playback at t=84 s was
already in the broken state. The same pattern replays after suspend/resume
(`tas2781_system_resume` → `tasdevice_reset` + `prmg_load`, burned by the
WirePlumber re-probe ~4 s later).

This also explains the maddening intermittency reported for this class of
machine: whether the *user* ever gets the good cycle is a race between the
async firmware load, session startup, and the first manual playback.

## The workaround

The driver exposes `force_fwload_status` as the ALSA control
**`Speaker Force Firmware Load`** (a CARD-interface control, registered from
the RCA firmware). Setting it **on** flips the condition in
`tasdevice_select_tuningprm_cfg()` so that every PCM open performs the full
program + config + calibration staging.

Verified on the affected machine, starting from the burned state: with the
control on, ftrace shows full staging (no "Unneeded") on consecutive plays,
and the woofers are audibly restored — persisting across open/close cycles
and suspend/resume.

Two support pieces are required for reliability:

1. **Runtime PM pinned to `on`** for the amplifier i2c devices (udev rule
   matching `DRIVERS=="tas2781-hda"`). With runtime autosuspend active
   (3000 ms default), the amps enter software shutdown after short silences
   and the recovery behavior is not dependable. (Historical note: an early
   "force-fwload doesn't help" result was obtained *without* this pin, in a
   different failure state — the two must ship together.)
2. **`snd_hda_intel power_save=0`**, so the HDA path is not additionally
   power-cycled behind the driver's back.

### Cost

Full staging pushes the complete DSP program + config + calibration to all
four amplifiers over i2c on each fresh stream open: measured **~2.5–2.7 s of
silence** at stream start. Consequences: a lead-in gap after any sink
suspend, and short event sounds that can be swallowed whole. Mitigation:
keep the sink open (WirePlumber `session.suspend-timeout-seconds = 0`
drop-in, shipped in `extras/`), making staging a once-per-boot event.

## Sketch of the proper upstream fix

The cache is the bug, not the staging logic. Options, roughly in order of
preference:

1. **Invalidate `cur_prog`/`cur_conf` whenever the amplifiers are shut
   down** (PRE_SHUTDOWN path / runtime suspend / system suspend). The next
   open then naturally re-stages. Cost is identical to this workaround but
   only paid when the DSP was actually lost.
2. Re-stage config + calibrated data as part of the power-up path when
   coming back from shutdown.
3. Platform-quirk either of the above if some TAS2781 platforms genuinely
   retain DSP memory through PRE_SHUTDOWN and want to keep the skip.

Open question for upstreaming: whether *all* TAS2781 platforms lose DSP
memory on PRE_SHUTDOWN (making the cache simply wrong) or only some (making
this quirk-worthy). The register evidence here covers one platform.

## Side finding: the Windows driver ships a newer tuning revision

Decoding both blobs down to the register-write commands they encode
(`tasdevice_process_block` format: single/burst writes with book/page/reg
addressing) shows the Windows `TAS2XXX38D6.bin` on the Yoga Pro 9 16IMH9 is
a **10-day-newer build of the same tuning** (header timestamps 2023-12-19
Linux vs 2023-12-29 Windows). Every meaningful difference is exactly five
32-bit words in one 30-word table at DSP book 0x00 / page 0x0F, changed
identically for all four amplifiers — no EQ, crossover, gain, or
per-speaker calibration changes.

The table is a two-band dynamics (DRC/limiter) parameter block; the values
are dB stored in log2 units (× 20·log10 2). The deltas are exact: one
band's threshold lowered 5.5 dB, the other's 0.5 dB, one band's step pair
softened 1.5 → 1.0 dB (harmonizing the two bands), one coefficient snapped
to 9/32. This matches TI's own published tuning recipe for the Smart Amp
DRC (TAS2563 Tuning Guide, SLAA936: two crossover-split bands, per-band
thresholds; "reduce the region 2 threshold by 5 dB, soften the ratio") —
i.e. a standard final-polish pass that the Linux-shipped blob predates.

Practical upshot: below the DRC thresholds the two blobs behave
bit-identically; at high volume the Windows revision compresses bass
earlier and in finer steps. `tas2781-win-fw` (see README) lets users apply
their own Windows copy persistently.

## Related but separate: the SSID-collision bind bug (fixed in 7.1)

On the Yoga Pro 9 16IMH9 the HDA codec subsystem ID is `17aa:38d6` but the
PCI subsystem ID is `17aa:3811`; kernels before 7.1 look up the quirk table
with the wrong one, so the TAS2781 side-codec never binds at all — no amp
driver, no controls, no bass, ever. Workaround for old kernels:
`snd_sof_intel_hda_generic hda_model=17aa:38d6` (see
`extras/modprobe.d/`). Fixed upstream in kernel 7.1. It is mentioned here
because you must be past this bug before the force-fwload workaround is even
applicable.
