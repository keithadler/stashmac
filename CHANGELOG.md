# Changelog

## 1.0.1 — 2026-09-03

"More from the Same Maker" in the Help menu, pointing at the family page. Help and README gained the same section.

## 1.0.0 — 2026-09-03

First release.

- A random 256-bit key with a printable recovery card: 24 words with a checksum, a QR code, a
  fingerprint. No password. The card must be typed back before it closes.
- Encrypted chunks (ChaChaPoly, keyed names) and encrypted manifests; the provider only ever
  holds ciphertext. Identical content is stored once; a second backup uploads only what changed.
- Any folder as a destination: iCloud Drive, Google Drive, OneDrive, Dropbox, a disk, a NAS.
  Cloud placeholders are listed, never downloaded; evicted chunks are never fetched by verify.
- Restore browser for files, folders or everything; damaged pieces fail one file, never
  partial writes. Verify opens every chunk and restores a random file; weekly by default.
- Snapshot manager with what each snapshot frees, two retention policies (newest N, thin out
  over time), and a grace period so two Macs on one card never lose an upload in flight.
- Exclusions by name pattern and size; Photos libraries, caches and temp files skipped by default;
  ~/Library skipped when the home folder is chosen. A backup may never contain itself.
- Hourly or daily schedule while the app is open, menu bar item, notifications on failure,
  open at login and a daily update check by default (both toggles), help in English and Spanish.
- `stashmac` command line with `--json` everywhere; 33 test cases three ways plus an
  end-to-end integration script.
