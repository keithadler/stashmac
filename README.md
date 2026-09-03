# Stash for Mac

Encrypted backup of the folders that matter, into the free storage you already have: the Google
Drive that comes with Gmail, the OneDrive that comes with Microsoft 365, iCloud Drive, Dropbox, an
external disk, a NAS. The provider only ever holds scrambled blobs. You hold the key, as 24 words
and a QR code on a card.

Free, MIT licensed, no account, no server, no subscription. Same family as
[Tidy for Mac](https://github.com/keithadler/tidymac) and [Clip for Mac](https://github.com/keithadler/clipmac).

**Status: shell.** This repository currently proves the part that has to be right before anything
else: the key, its recovery card, and the encrypted chunk format. Folders, destinations, schedules
and restore are the next milestones (see below).

## What it refuses to do

- Upload anything the provider can read. Chunks are encrypted on the Mac and named by a keyed hash,
  so the provider cannot tell what a blob is, or whether two people stored the same file.
- Keep a copy of your key anywhere but this Mac's Keychain. The recovery card is the only backup of
  it, and the app says so before you can continue. Lose the card and the backup is unreadable, by
  anyone, including you.
- Restore a chunk that fails authentication. Damaged or tampered data is reported, never written.
- Open cloud placeholders while reading your folders (a file that only exists in iCloud is skipped
  and listed, not downloaded behind your back).

## The key

Stash for Mac makes a random 256-bit key. You keep it three ways, all on one printable card:

- **24 words** (BIP-39 encoding, with a checksum word, so a typo is caught before restore starts)
- **A QR code** of the same key, scannable by a phone camera or by the app on a new Mac
- **A fingerprint**, eight characters, so two cards can be told apart

Everything else is derived from the key with HKDF: the chunk encryption key, the chunk naming key,
the manifest key. There is no password, so there is nothing to guess.

## Threat model, in one screen

Protects against a breached or subpoenaed cloud account, a curious provider, a lost laptop with the
sync folder on it, and someone who has your Google or Microsoft password. Does not protect against
malware running on the Mac while the app has the key in memory, a lost recovery card, or someone
with account access deleting the ciphertext (point it at two destinations). The provider can see
when you back up and roughly how much. Full text: [docs/threat-model.md](docs/threat-model.md).

## Cryptography

Standard primitives from Apple's frameworks only, no homemade parts: ChaChaPoly for chunks and the
manifest, HKDF-SHA256 for key derivation, HMAC-SHA256 for chunk names, SecRandom for the key.
Chunk format: `STSH1` + 12-byte nonce + ciphertext + 16-byte tag. Test vectors in
`Sources/StashMac/Tests`.

## Command line (today)

```
stashmac key new                 make a key, print the 24 words
stashmac key show                print the words and fingerprint
stashmac key card card.pdf       write the printable recovery card
stashmac key restore "<24 words>" | --qr card.png
stashmac key forget              remove the key from this Mac
stashmac seal in out             encrypt one file as a chunk; stashmac open reverses it
stashmac status                  stashmac selftest
```

## Roadmap

1. Folders: pick them, walk them, skip cloud placeholders, track changes by size and date.
2. Chunk store: split, dedupe by keyed hash, seal, write; manifest of every snapshot, encrypted.
3. Destinations: any folder first (that covers every provider through its own desktop app),
   then Google Drive and OneDrive APIs with the app-only scopes that need no review.
4. Restore: browse snapshots, restore a file, a folder, or everything, to a new place.
5. Verify: weekly random-file restore, `stashmac verify` over every chunk's tag.
6. Schedule, menu bar status, second destination nag, help, Spanish, release.

## Building

macOS 14 or later and the Command Line Tools. No Xcode, no dependencies.

```bash
./build-app.sh --install --run     # universal build, installs, symlinks stashmac
stashmac selftest                  # the suites, no Xcode needed
swift test                         # same suites under XCTest where Xcode exists
```

## License

MIT. See LICENSE. Mac and macOS are trademarks of Apple Inc.; Google Drive, OneDrive, iCloud and
Dropbox belong to their owners and are named only to identify those services.
