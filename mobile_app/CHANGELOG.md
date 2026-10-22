# Changelog

All notable changes to the EvilCrow RF mobile app are documented here.

---

## What's New in this update

**Authored by DaGromflomite. Assisted by Claude.**

- ⚡ **Much faster transfers to the Crow.** Sending files to the SD card is now roughly **40×
  faster** — a section that used to take ~19 minutes now finishes in well under a minute.
- 🗂️ **New way to load the SubGHz database.** Instead of trying to pull the entire database
  over Bluetooth at once (which never fit), you now download it to your phone and **pick just
  the sections you want** to send to the Crow — with a file count shown for each category and a
  one-screen explainer of how it works.
- 🧹 **Format-the-SD-card option** built into the flow, so you can start from a clean, correctly
  set-up card before transferring.
- 🔁 **Brute-force now covers US *and* EU gear.** Pick the frequency for region-specific
  protocols — Honeywell 433.92 (EU) / 345 MHz (US), and Chamberlain/LiftMaster 315 / 390 MHz —
  plus a **timing (te) selector** so you can sweep remotes whose timing varies unit-to-unit.
- 📡 **Bigger, simpler transmit button.** One tap to start transmitting continuously, tap again
  to stop — easier to hit and better for stubborn receivers than a single quick burst.
- ⏱️ **"Time remaining" estimate** while files transfer, so you know how long a section will take.
- ✅ Fixed a bug where successful transfers were wrongly reported
  as "failed," and cleaned up stray error messages during transmit.
- 📄 **Files open instantly.** Opening a file no longer tries to read it back over Bluetooth
  first (which was slow); previewing is now a quick optional button, and sending a file never
  needed it.

Full technical detail below.

---

## [Unreleased] — Sectioned SubGHz DB download, upload reliability & speed, transmit/brute UX

Authored by **DaGromflomite**. Assisted by Claude.

Closes #16 (SubGHz database too large to pull over BLE in one piece).

### Added — Sectioned SubGHz database download (the headline feature)
- **Pick which sections to download.** Instead of pulling the entire multi-thousand-file
  repository dump in one go (which overruns BLE limits), the app downloads the database ZIP
  to the phone, then lets you choose exactly which category folders to transfer to the Crow's
  SD card.
- **Category checklist** with per-category file counts, plus **Select all / Clear**.
- **"Include brute-force folders" opt-in switch** (off by default) — the large brute-force
  dumps are excluded unless you ask for them.
- **Intro / explainer pop-up** describing the whole flow (ZIP → phone storage → pick sections
  → transfer to SD), including the per-transfer file considerations.
- **Optional "format SD card first"** step to set up a clean filesystem before transferring.
- **Lossless large-file splitting.** Oversized RAW `.sub` sweeps are split into smaller,
  fully valid `<name>_NN.sub` pieces so each transfers reliably over BLE. Every piece repeats
  the original header and carries whole lines of `RAW_Data`, so the pulse timing is preserved
  exactly; the firmware transmits by file *content* (not filename), so each piece plays
  identically and the pieces in sequence reproduce the full sweep.
- Files are written to `/SUB Files/<category>/…` (SD root, pathType 5) so they are browsable,
  playable, and transmittable on the device.

### Added — UX
- **Live "time remaining" (ETA)** during an upload, measured from the real per-file rate and
  updated as it goes.
- **Large click-on / click-off transmit toggle.** Replaces the small single-shot transmit
  control: tap once to start transmitting the file continuously, tap again to stop. Finger-
  friendly target.
- **Brute-force frequency picker** on region/variant protocols:
  - Honeywell — **433.92 MHz (EU)** / **345 MHz (US)**
  - Chamberlain & LiftMaster — **315 MHz** / **390 MHz**
  Routed through the firmware's existing custom De Bruijn command, so no firmware change is
  required.
- **Brute-force `te` (timing) override** dropdown (200–700 µs) for manually sweeping the
  resistor-set protocols (Princeton, Holtek, …) whose timing varies unit to unit.

### Changed — Upload performance (~40× faster, verified)
- Removed the artificial 10 ms per-chunk delay — BLE write-with-response already provides the
  flow control, so the extra sleep was pure overhead.
- Reduced the per-file pause from 150 ms to 20 ms.
- **Stream uploads straight from memory** — removed the per-file scratch temp-file write/read
  round-trip (the bytes are already in memory from the phone-side download).
- Request a **high-priority BLE connection** after MTU negotiation (Android: shorter connection
  interval → more throughput).
- Measured: a section that took ~19 minutes now completes in well under a minute, with no loss
  of reliability.

### Changed — Transmit
- File **preview is now opt-in**: opening a file no longer auto-reads its contents back over BLE
  (which was slow and could time out on large files). A "Load preview" button reads on demand.
  Transmitting never needed the preview — the Crow plays straight off its SD.

### Fixed
- **Upload false-failures.** When the firmware acknowledged a file very quickly, the success
  reply could null the pending completer before the upload routine awaited it, throwing
  "Null check operator used on a null value" and mislabeling every (actually successful) upload
  as failed — and stalling the progress counter/resume tracking. The routine now awaits a local
  reference to the completer. Uploads report honestly and progress/resume work correctly.
- **Spurious transmit error noise.** During continuous (toggle) transmission the firmware emits
  harmless status messages (`SignalSendingError` with `errorCode 0`, a bogus module index, and a
  stray "command not supported"). These are now ignored so they don't pollute the UI/logs or
  disturb the repeat loop; genuine transmit errors still surface.

### Notes
- No firmware changes are required by this release; it works against the current
  EvilCrowRF-V2 firmware.
