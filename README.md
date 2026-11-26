# Lastbook Remote

A lightweight open-source iPhone and iPad client for viewing a [Lastbook](https://github.com/Immortal-Protocols/lastbook) library over your local network or a [Tailscale](https://tailscale.com) tunnel.

Lastbook is an offline knowledge library for Mac, Windows, and Linux. This app is a thin client: it does not install the library, content packs, or the on-device AI model. It reads the library already on your computer (or in a NAS folder that computer has mounted). You can optionally save individual videos or documents on the phone or tablet for later, away from home.

**Status: v0.1 developer preview.** A universal SwiftUI app (iPhone and iPad, iOS 17+) that connects to a shared Lastbook library, browses and searches it, opens PDFs, text and web pages, streams videos, and saves single items for offline use. Not on the App Store; you build it yourself in Xcode. How to try it on your own devices: [TESTING.md](TESTING.md). Requirements: [docs/PRD.md](docs/PRD.md). Design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build

You need a Mac with Xcode 16 or later.

```bash
git clone https://github.com/sumeet2025/lastbook-remote.git
cd lastbook-remote
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set DEVELOPMENT_TEAM and LASTBOOK_BUNDLE_ID_PREFIX
open LastbookRemote.xcodeproj
```

Pick the **LastbookRemote** scheme and your iPhone or iPad, and press Run. `LastbookRemote.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); after changing `project.yml` or adding files, run `brew install xcodegen && xcodegen`.

| Path | What it is |
|---|---|
| `App/` | The SwiftUI app: libraries, Browse, Search, Videos, the host's own Lastbook UI, Downloaded, Settings. |
| `LastbookRemoteKit/` | A Swift package with no UI: the share-listener client, models, access-link parsing, the codec check, and the offline store. Builds and tests on macOS and Linux (`swift test`). |
| `scripts/make_sample_library.py` | Builds a tiny library (PDFs, text, a web page, an H.264 and an AV1 video) to test against. |
| `project.yml`, `Config/` | The XcodeGen spec and build settings. Your signing team goes in the git-ignored `Config/Local.xcconfig`. |

### Tests

```bash
cd LastbookRemoteKit
swift test                                   # unit tests
# against a real share listener (see TESTING.md):
LASTBOOK_TEST_LINK='http://127.0.0.1:8890/?key=…' swift test
```

## How it works

1. On the computer that holds the library, share it on your network:
   - In the Lastbook desktop app, turn on **Share this library with my devices** in Library and local AI. That switch is in [upstream pull request #343](https://github.com/Immortal-Protocols/lastbook/pull/343) and is off by default.
   - Until that lands, you can already run `python3 server.py --lan --data /path/to/LastbookData` on the host. It prints an access link.
2. On your iPhone or iPad, this app connects to that host over the same Wi-Fi, or over a private VPN such as Tailscale. Today the host only accepts a bare IP address, not a name (including Tailscale MagicDNS).
3. You get the library's documents, search, maps, encyclopedias, and videos, and Chat if the host has local AI and turns on "Include Chat" for shared devices (off by default). The phone does not download the library. You can save single documents, videos and pages on that iPhone or iPad for later; search, encyclopedia links, maps and Chat still need the host.

Do not put the access link on the public internet. The server is plain HTTP with a key in the link.

## Features in v0.1

- One universal app for iPhone and iPad.
- Connect by pasting the host's access link, scanning it as a QR code with the camera, or typing the IP, port and key. Keys are stored in the Keychain. Remember more than one library and switch between them. The app refuses public internet addresses and host names.
- Native **Browse** (shelves → collections → items, including courses), **Search** (`/api/find`, with highlighted matches), and **Videos** rows.
- Native **PDF** viewing (PDFKit, opens at the matching page from a search), text and Markdown, and saved web pages.
- **Video** with AVPlayer: streaming with Range seeking, Picture in Picture, AirPlay and background audio. AV1, VP9, WebM and MKV files that the device can't decode show a clear message instead of a black screen.
- The host's own Lastbook web app in a **Lastbook** tab, for encyclopedias, maps, guides, and Chat if the host shares it.
- **Save for offline** of single items: the size is shown first, downloads resume with HTTP Range, a storage cap (5 GB by default) refuses saves that would go over, and a **Downloaded** screen opens items with no network and deletes one or all.
- A reconnect screen when the host is asleep, sharing is off, or the key changed.

Later, when Lastbook adds them: automatic discovery on the local network, pairing tokens, a QR code shown by the host (the app can already scan one), HTTPS, host names, and H.264 copies of AV1 videos.

## Roadmap

1. **This repository** — requirements, architecture, and license. Done.
2. **A first client** — connect with today's access link, show the library, open documents, and play and seek videos, including over Tailscale by IP. v0.1.
3. **Save for offline** — individual items, a storage cap, and a Downloaded screen. v0.1; background downloads come later.
4. **Easier pairing** — Bonjour discovery, pairing tokens, QR, and TLS, once those exist in Lastbook. Until then the app stays compatible with `server.py --lan` and with PR #343 as it is.

## Documentation

- [Requirements (PRD)](docs/PRD.md) — the prompt for building the app, including what Lastbook already provides and what this client must do.
- [Architecture](docs/ARCHITECTURE.md) — the native shell, the host, and the network.
- [Remote access](docs/REMOTE-ACCESS.md) — the access link, Tailscale by IP, and the security model.
- [Testing on your devices](TESTING.md) — step by step.

Lastbook itself: [github.com/Immortal-Protocols/lastbook](https://github.com/Immortal-Protocols/lastbook) and [lastbook.org](https://lastbook.org).

## Privacy

The app does not include analytics, accounts, or third-party SDKs. Connection secrets stay in the Keychain. The only network use is talking to the Lastbook host you chose, on your local network or through a VPN you set up. Saved items stay on the device until you delete them. Nothing is sent to the authors of this app.

## License and affiliation

This project is independently developed and is **not affiliated with or endorsed by** Lastbook or Immortal-Protocols. It is released under the [MIT License](LICENSE), the same license as Lastbook, so their web UI and protocols can be reused.
