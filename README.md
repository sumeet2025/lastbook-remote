# Lastbook Remote

A lightweight open-source iPhone and iPad client for viewing a [Lastbook](https://github.com/Immortal-Protocols/lastbook) library over your local network or a [Tailscale](https://tailscale.com) tunnel.

Lastbook is an offline knowledge library for Mac, Windows, and Linux. This app is a thin client: it does not install the library, content packs, or the on-device AI model. It reads the library already on your computer (or in a NAS folder that computer has mounted). You can optionally save individual videos or documents on the phone or tablet for later, away from home.

**Status: planning.** There is no app code in this repository yet. The requirements a coding agent can follow are in [docs/PRD.md](docs/PRD.md). How the pieces fit together is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## How it works

1. On the computer that holds the library, share it on your network:
   - In the Lastbook desktop app, turn on **Share this library with my devices** in Library and local AI. That switch is in [upstream pull request #343](https://github.com/Immortal-Protocols/lastbook/pull/343) and is off by default.
   - Until that lands, you can already run `python3 server.py --lan --data /path/to/LastbookData` on the host. It prints an access link.
2. On your iPhone or iPad, this app will connect to that host over the same Wi-Fi, or over a private VPN such as Tailscale. Today the host only accepts a bare IP address, not a name (including Tailscale MagicDNS).
3. You get the library's documents, search, maps, encyclopedias, and videos, and Chat if the host has local AI installed. The phone does not download the library. Search, encyclopedia links, and Chat still need the host even if you have saved a few items for offline use.

Do not put the access link on the public internet. The server is plain HTTP with a key in the link.

## Planned features

- One universal app for iPhone and iPad.
- Connect by pasting or scanning the host's access link (the current key-and-cookie flow). Remember more than one library.
- The existing Lastbook web UI, wrapped in a native shell, with native PDF viewing and native video playback.
- Optional **Save for offline** of individual videos and documents, with the size shown first, a storage cap, and a Downloaded screen where items can be deleted. Prefer an H.264 copy when the host has one.
- Use the host's local AI for Chat when it is available; hide Chat when it is not.
- Later, when Lastbook adds them: automatic discovery on the local network, pairing tokens, a QR code, and HTTPS.

## Roadmap

1. **This repository** — requirements, architecture, and license. You are here.
2. **A first client** — connect with today's access link, show the library, open documents, and play and seek videos, including over Tailscale by IP.
3. **Save for offline** — individual items, a storage cap, and a Downloaded screen.
4. **Easier pairing** — Bonjour discovery, pairing tokens, QR, and TLS, once those exist in Lastbook. Until then the app stays compatible with `server.py --lan` and with PR #343 as it is.

## Documentation

- [Requirements (PRD)](docs/PRD.md) — the prompt for building the app, including what Lastbook already provides and what this client must do.
- [Architecture](docs/ARCHITECTURE.md) — the native shell, the host, and the network.

Lastbook itself: [github.com/Immortal-Protocols/lastbook](https://github.com/Immortal-Protocols/lastbook) and [lastbook.org](https://lastbook.org).

## Privacy

The app will not include analytics, accounts, or third-party SDKs. Connection secrets stay in the Keychain. The only network use is talking to the Lastbook host you chose, on your local network or through a VPN you set up. Saved items stay on the device until you delete them. Nothing is sent to the authors of this app.

## License and affiliation

This project is independently developed and is **not affiliated with or endorsed by** Lastbook or Immortal-Protocols. It is released under the [MIT License](LICENSE), the same license as Lastbook, so their web UI and protocols can be reused.
