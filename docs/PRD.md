# Prompt: Build Lastbook Remote — a universal iPhone + iPad client

You are working in this repository (`lastbook-remote`, MIT). It will hold a lightweight SwiftUI client that reads a [Lastbook](https://github.com/Immortal-Protocols/lastbook) library over the local network or a Tailscale tunnel. Lastbook is an offline knowledge library for Mac, Windows and Linux: a Python engine/server, a web UI in `web/`, and an optional on-device AI.

Read this document, `docs/ARCHITECTURE.md`, and the Lastbook files it names, before you write code. Do not open issues or comments on the Lastbook repository unless the person you are helping asks you to.

## Goal

Let a person browse the library, search, read documents and encyclopedia articles, and play videos on an iPhone or iPad **without installing the library, content packs, or the AI model on the device**. Content stays on the host computer. The library folder may live on a NAS that the host has mounted. The phone or tablet is a thin client.

The person may **explicitly save individual videos or documents** on the device for later. That is not the same as installing the library. Search, encyclopedia links, and Chat still need the host.

## Current state (verify in Lastbook's code)

Useful files in https://github.com/Immortal-Protocols/lastbook: `README.md`, `server.py`, `docs/LIBRARY-SERVER.md`, `app/main.py`, `app/bridge.py`, `engine/library.py`, `engine/share.py`, `web/app.js`, `mobile/ipad/README.md`.

- `python3 server.py` binds `127.0.0.1:8890`. `python3 server.py --lan` binds `0.0.0.0:8890` and prints `http://<host-ip>:8890/?key=…`. The key lives in `derived/lan-key`. Opening the link sets an HttpOnly `sg_key` cookie. Other clients get 403 without it. Plain HTTP, not HTTPS.
- `host_ok()` allows only `localhost` or a bare IP. Named addresses, including Tailscale MagicDNS, are refused. Connect over Tailscale by IP.
- Routes include `/ui/`, `/api/doc/`, `/api/page/`, `/api/find`, `/api/videos`, `/documents/`, `/pages/`, `/courses/`, `/zim/`, `/videos/`, `/videos-external/`. Video HTTP Range (206) is supported for mp4/webm/mkv.
- The library is a `LastbookData` folder (`library-data/` + `derived/`), selectable with `--data`, `LASTBOOK_DATA`, or "Open another library folder". The folder must be writable on the host, so a read-only NAS mount is rejected.
- Many videos are AV1 or VP9. H.264 fallback copies are supported by Lastbook's iPad preview (`VideoCompat.swift`) but are not yet published for any pack.
- Lastbook's iPad app (`mobile/ipad/`) is a full **local** client. Open Lastbook PR #200 adds an iPhone target to it. This project is a **remote** client, not a replacement, and does not live in that tree.

## Upstream (Lastbook) dependencies

This client does not change Lastbook unless the person you are helping asks for a separate pull request. Build against what already exists, and keep room for the follow-ups below.

### Already landed, or usable today

[Pull request #343](https://github.com/Immortal-Protocols/lastbook/pull/343) adds an opt-in **Share this library with my devices** switch to the packaged desktop app (Library and local AI). Until it is merged, `python3 server.py --lan` is the supported way to share.

What #343 does, for the client to rely on:

- The switch is **off by default**. Turning it on starts the existing LAN server (`server.py` / `--lan` logic, not a fork of it) on `0.0.0.0`, first free port in **8890–8899**.
- The same `derived/lan-key` and `sg_key` cookie as `server.py --lan`. The desktop page shows the access link, with Copy and Stop. The listening port closes when sharing is stopped or the app quits. If sharing was left on, it starts again at launch.
- **Read-only for non-localhost callers**, even with the key: `/api/setup`, `/api/update`, `/api/battery`, `/api/not-found`, `/api/assistant/local`, `/api/tool`, `/api/tools`, and `/api/share` are blocked. Library reads, search, maps, encyclopedias, videos, and `/api/chat` stay allowed, so a phone can use the host's local AI.
- With the switch off, the desktop app opens no listening port. Tests in `app.tests.test_share` cover off = no port, the key, and the remote allow-list.
- A library on a NAS works if the host has it mounted and can write derived files there. Other devices do not mount the NAS themselves.

### Follow-ups still needed in Lastbook (do not block the first client)

Call these out in the client README or settings as "when Lastbook supports it." Do not invent a private protocol that will fight them later.

- **Pairing tokens** — a short code or QR that issues a per-device token, with a list and revoke, instead of only the shared URL key. Keep the current key-and-cookie flow working for Safari and for this app.
- **Bonjour / mDNS** — advertise `_lastbook._tcp` with the library name and protocol version, and **no secrets** in the TXT record.
- **TLS** — a self-signed certificate whose fingerprint is pinned in the QR or pairing payload, so the client can use HTTPS.
- **A QR code** on the share page for the access (or pairing) link.
- **MagicDNS / host names** in `host_ok()` — today only a bare IP works, including on Tailscale.
- **Published H.264 sidecars** for library videos, so devices that cannot decode AV1 or VP9 can still play them.

## This app (client)

Build a universal iPhone and iPad app in this repository. Suggested layout: an Xcode project at the repo root (or `ios/`), with a short `ios/README` covering build and sign-yourself steps. Leave the bundle ID and signing team as placeholders in a git-ignored `Local.xcconfig`.

### Product

1. One SwiftUI app target for iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`). Deployment target iOS/iPadOS 17 or later unless the code demands newer. Layouts adapt to compact and regular widths, portrait and landscape.
2. **Do not install the library.** No installer, packs, models, or a copy of `LastbookData` on the device. Small caches are allowed: thumbnails, recent pages, and the HTTP cache, with a size cap and a "Clear cache" action.
3. **Save for offline is allowed**, only when the person asks for a specific video or document:
   - Show the size and confirm before saving. Prefer an H.264 copy when the host offers one (AV1 will not play on iPhones older than the 15 Pro).
   - Use resumable downloads with HTTP Range.
   - Keep a storage cap (a sensible default, and a setting to change it). Refuse a save that would go over, with a clear message.
   - A **Downloaded** screen lists saved items and lets the person delete one or all of them.
   - A saved document or video can be opened with no network. Search, encyclopedia links, maps, and Chat still need the host — say so in the UI, and do not pretend the whole library is on the device.
   - Optionally, hook "Save for offline" into Lastbook's existing Saved list on the host, if that can be done with the public read APIs plus a small, clearly marked write that the host already allows. If it cannot, keep a local list on the device and do not invent a new host API.
4. Connect, until Lastbook has pairing and Bonjour:
   - Support the **current access-link and cookie flow**. The person pastes the link (`http://<ip>:<port>/?key=…`) or scans it if you show a scanner (the host may not show a QR yet, so paste must work).
   - Store the key or cookie material in the Keychain, not in UserDefaults or a plist.
   - Manual address entry (IP and port) so it works over Tailscale, WireGuard, or another VPN. Default to a bare IP. Warn that host names, including MagicDNS, are refused by the server today.
   - Do not build a public relay, and do not recommend port forwarding or exposing the link to the public internet.
   - Remember multiple libraries, with a switcher.
   - When Lastbook adds Bonjour, pairing tokens, QR, or TLS, adopt them without dropping the key-link path.
5. UI: host the existing `web/` UI from the Mac (or other host) in a WKWebView (fastest path, guaranteed parity), wrapped in native chrome: a library picker, connection status, share sheet, and a path to Downloaded. Use native PDF viewing (PDFKit) and native video playback (AVPlayer) where they beat the web view. Keep the code organized so screens can later move to native.
6. Docs: open documents, pages, courses and encyclopedia (ZIM) articles served by the host. PDFs stream with Range where supported. Use search via `/api/find`.
7. Video: AVPlayer with Range seeking, Picture in Picture, AirPlay and background audio where allowed. Detect AV1/VP9 the device can't decode. Prefer an H.264 sidecar if the server offers one, otherwise show a clear "This video can't play on this device" message, and still offer Save for offline if an H.264 copy exists. No on-device transcoding.
8. Chat: if the host has local AI installed, the client can use it through the server (`/api/chat` is allowed for remote callers). Hide Chat when it isn't available.
9. Resilience: handle the host sleeping, changing networks, or losing the NAS mount, with retry and a friendly reconnect screen. Never crash or spin forever.
10. Security: secrets in the Keychain; TLS with a pinned fingerprint when the server offers it; minimal ATS exceptions (local networking only) when it doesn't. No analytics or third-party SDKs, matching Lastbook's privacy stance.
11. Accessibility: Dynamic Type, VoiceOver labels and sufficient contrast. Localization-ready strings.
12. NAS: when the library is on a NAS, the host (not this app) mounts it. The client only talks to the Lastbook server on the host. Do not implement SMB in v1.

## NAS without a host (stretch, design only)

Write a short design note (`docs/REMOTE-NAS.md`) on what the app could do with an SMB share alone: opening PDFs and MP4s via the Files provider, and why search, the catalog, ZIM and maps need the engine. Recommend running the Lastbook server on the NAS (Docker or Python) as the supported path. Don't implement SMB parsing in v1.

## Out of scope

- App Store submission, signing team and bundle ID (leave placeholders in a git-ignored `Local.xcconfig`).
- A public relay or cloud service.
- On-device AI models, content packs, and installing the library.
- Changing Lastbook's default privacy behavior, or depending on a Lastbook follow-up that has not landed. Ask before adding heavy dependencies or new network services.

## Acceptance criteria

- On the same Wi-Fi, a fresh iPhone and a fresh iPad can each connect with the access link (from the desktop share switch or from `server.py --lan`), search, open a PDF, open an encyclopedia article, and play and seek a playable video. The library itself is not installed on the device.
- The same works over Tailscale using the host's Tailscale IP.
- The library folder on an SMB share mounted on the host works end to end.
- The person can save one document and one video for offline use: they see the size first, the files appear on the Downloaded screen, and they open after the host is unreachable. Search and Chat do not work offline, and the UI says so. Deleting a saved item frees the space.
- A save that would exceed the storage cap is refused with a clear message.
- Unplayable AV1 videos show a clear message, not a black screen.
- Turning sharing off on the host, or using a wrong key, immediately blocks access (401/403).
- The client never calls setup, update, or other local-only host endpoints.
- Existing Lastbook desktop, `server.py --lan`, and iPad local-preview behavior is unchanged; this app is a separate project.

## Deliverables

1. The universal iPhone and iPad app, with a README covering build, sign-yourself steps, and how to test against `server.py --lan` and against the share switch in PR #343.
2. `docs/REMOTE-ACCESS.md` (setup, Tailscale-by-IP guidance, security model) and `docs/REMOTE-NAS.md` (design only).
3. Small, reviewable changes: connect and browse first, then Save for offline, then discovery/pairing once Lastbook has them.

Ask before changing the privacy model, adding dependencies, or talking to Lastbook APIs that are meant only for the host computer.
