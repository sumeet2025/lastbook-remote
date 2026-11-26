# Prompt: Build Lastbook Remote — a universal iPhone + iPad client

You are working in this repository (`lastbook-remote`, MIT). It will hold a lightweight SwiftUI client that reads a [Lastbook](https://github.com/Immortal-Protocols/lastbook) library over the local network or a Tailscale tunnel. Lastbook is an offline knowledge library for Mac, Windows and Linux: a Python engine/server, a web UI in `web/`, and an optional on-device AI.

Read this document, `docs/ARCHITECTURE.md`, and the Lastbook files it names, before you write code. Do not open issues or comments on the Lastbook repository unless the person you are helping asks you to.

## Goal

Let a person browse the library, search, read documents and encyclopedia articles, and play videos on an iPhone or iPad **without installing the library, content packs, or the AI model on the device**. Content stays on the host computer. The library folder may live on a NAS that the host has mounted. The phone or tablet is a thin client.

The person may **explicitly save** individual documents, videos and other items the host serves (such as encyclopedia articles) onto **that specific iPhone or iPad** for later or for use with no network. That is not the same as installing the library, which stays a non-goal. Search, browsing, encyclopedia links, maps and Chat still need the host unless that content was saved.

## Current state (verified against Lastbook PR #343 at 499a6d0)

Useful files in https://github.com/Immortal-Protocols/lastbook: `README.md`, `server.py` (`ShareHandler`, `start_lan`, `stop_lan`, `load_lan_key`), `engine/share.py` (the switch and its flags), `engine/share_http.py` (allowlist, key, redirect rules), `web/setup.js` (the sharing controls), `docs/LIBRARY-SERVER.md`, `engine/library.py`, `web/app.js`, `mobile/ipad/README.md`.

- **Two servers, tracked apart.** The local reader (`SERVER`, loopback only, full handler) and the share listener (`SHARE_SERVER`, `ShareHandler`, all interfaces). The share switch starts and stops only `SHARE_SERVER`. In the desktop app it takes the first free port in **8890–8899**; `python3 server.py --lan` uses 8890 (or `--port`). Plain HTTP, not HTTPS.
- **Off by default, and it remembers.** Sharing is off unless the person clicks Start sharing in Library and local AI. If they leave it on, it starts again when Lastbook reopens (`share.restore()` at launch; Setup says "Sharing stays on until you stop it, and starts again when Lastbook reopens."). Stop closes the port and every in-progress stream. Quitting closes the port but keeps the preference.
- **The access key.** One key in `derived/lan-key` inside the **library data folder** (`LastbookData`, or whatever `--data` / `LASTBOOK_DATA` points to; `HERE = DATA` in `server.py`), created on first share with mode 600. It stays the same across Stop and Start. To change it, stop sharing, delete that file, and start sharing again (the key is read when sharing starts). There is no "New key" button yet.
- **How the key is accepted** (`presented_key`, in this order): `?key=` in the URL, `Authorization: Bearer <key>`, `X-Lastbook-Key: <key>`, then the `sg_key` cookie. Compared in constant time. Every request needs it, including `/` and video Range requests.
- **`?key=` on a page navigation** (`/`, `/index.html`, other `.html` under the app UI; GET, no `Range`) sets `sg_key` (HttpOnly, SameSite=Strict, one year) and answers **302** to the same address without the key. Everything else with `?key=` is **served in place, no redirect**: `/api/*`, `/videos/`, `/videos-external/`, `/transcripts/`, `/metadata/videos/`, media suffixes, static assets, and `/zim/`, `/documents/`, `/pages/`, `/courses/`, `/collections/`, `/assets/`, and any request with a `Range` header (`should_redirect_key`). So AVPlayer, AirPlay and download Range requests keep working with the key in the URL.
- **Read-only allowlist** (`SHARE_EXACT`, `SHARE_PREFIXES`): the app UI (not setup or update pages), library files, encyclopedias, maps, search and browse APIs, video lists and transcripts, `/api/assistant/status`. Not on it: setup, update, notes, battery, local-AI controls, tools, the share switch, `catalog.json`, `derived/`, and `POST` anything except Chat when shared.
- **Two different refusals:**
  - No key or a wrong key: **403** with `Content-Type: text/html`, a page that says "This guide is shared on this network only with an access link. Ask the person running it for the link shown when it started." (`Handler.deny()`).
  - A key is fine but the route is not shared: **403** JSON `{"error": "This is not part of what is shared from this library."}` (`deny_not_shared()`).
  - Also: a host name instead of an IP gets 403 JSON `{"error": "not allowed from this page"}` (`host_ok()`), and an unknown item is 404 JSON.
- **Chat is a separate opt-in.** "Include Chat with this computer's local AI" is off by default (`share.json` `ai`), read on every request. `server.py --lan` never shares Chat. The signal, verified on the listener:
  - Not shared: `GET /api/assistant/status` → `{"online": false, "available": false, "shared": false, "coverage": {}}`, and `POST /api/chat` / `GET /api/retrieve` → 403 "not part of what is shared".
  - Shared: `GET /api/assistant/status` → the host's model status (`model`, `online`, `error`, `local`, `vision`, `index`, `coverage`) with **no** `shared` key; `POST /api/chat` answers 200 with a `text/event-stream` (an `error` event `model_unavailable` when the model isn't running).
  - The client treats Chat as available when `shared != false` and `online == true`, re-checks when the app returns to the foreground, and hides Chat otherwise. A POST without an `Origin` header (a native client) passes `origin_ok()`.
- `host_ok()` allows only `localhost` or a bare IP. Named addresses, including Tailscale MagicDNS, are refused. Connect over Tailscale by IP.
- Video HTTP Range (206) works for mp4/webm/mkv. `HEAD` on a file gives `Content-Length` and `Last-Modified` (no `ETag`).
- The library is a `LastbookData` folder (`library-data/` + `derived/`), selectable with `--data`, `LASTBOOK_DATA`, or "Open another library folder". The folder must be writable on the host, so a read-only NAS mount is rejected.
- Many videos are AV1 or VP9. H.264 fallback copies are supported by Lastbook's iPad preview (`VideoCompat.swift`) but are not yet published for any pack.
- Lastbook's iPad app (`mobile/ipad/`) is a full **local** client. This project is a **remote** client, not a replacement, and does not live in that tree.

## Upstream (Lastbook) dependencies

This client does not change Lastbook unless the person you are helping asks for a separate pull request. Build against what exists, and keep room for the follow-ups below.

### Usable today

- [Pull request #343](https://github.com/Immortal-Protocols/lastbook/pull/343) (**Share this library with my devices**, reviewed and "ready for a maintainer decision", not merged yet). Until it is merged and released, `python3 server.py --lan` from that branch is the way to share; it uses the same `ShareHandler`, key and allowlist, without Chat.
- A library on a NAS works if the host has it mounted and can write derived files there. Other devices do not mount the NAS themselves.

### Follow-ups still needed in Lastbook (do not block the client)

Call these out in Settings as "when Lastbook supports it". Do not invent a private protocol that will fight them later.

- **New key** — a button that replaces `derived/lan-key` (today: stop, delete the file, start).
- **Pairing tokens** — a short code or QR that issues a per-device token, with a list and revoke, instead of only the shared key. Keep the key flow working for Safari and this app.
- **A QR code** on the share page for the access (or pairing) link.
- **Bonjour / mDNS** — advertise `_lastbook._tcp` with the library name and protocol version, and **no secrets** in the TXT record.
- **TLS** — a self-signed certificate whose fingerprint is pinned in the QR or pairing payload, so the client can use HTTPS and drop the ATS exception.
- **MagicDNS / host names** in `host_ok()`.
- **Published H.264 sidecars** for library videos.
- A file **version or ETag** in the catalog or HTTP headers, so a client can tell cheaply that a saved copy is out of date (today: `bytes` in the catalog plus `Content-Length` / `Last-Modified` from `HEAD`).

## This app (client)

A universal iPhone and iPad app in this repository: `LastbookRemote.xcodeproj` generated from `project.yml` (XcodeGen), the app in `App/`, and networking, models and storage in the `LastbookRemoteKit` Swift package. Bundle ID prefix and signing team go in the git-ignored `Config/Local.xcconfig`.

### Product

1. One SwiftUI app target for iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), iOS/iPadOS 17 or later. Layouts adapt to compact and regular widths, portrait and landscape.
2. **Do not install the library.** No installer, packs, models, search index, or a copy of `LastbookData` on the device. That is an explicit non-goal. Small caches are allowed (thumbnails, recently viewed documents, the HTTP cache), with a size cap and a "Clear cache" action. Items the person chooses to save are covered in **Save on this device** below.
3. Connect, until Lastbook has pairing and Bonjour:
   - Support the **current access link**. The person pastes it (`http://<ip>:<port>/?key=…`) or scans it (paste must work; the host shows no QR yet), or types IP, port and key.
   - Store the key in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in UserDefaults or a plist.
   - Manual address entry so it works over Tailscale, WireGuard, or another VPN. Default to a bare IP. Refuse host names (Lastbook refuses them) and public internet addresses (plain HTTP with a key).
   - Remember multiple libraries, with a switcher.
   - Do not build a public relay, and do not recommend port forwarding.
4. **Auth on the wire.** Send `X-Lastbook-Key` on **every** native request (API, documents, thumbnails, downloads). Do not rely on the `sg_key` cookie: the API session stores no cookies, so a changed key or stopped share shows up on the next request. Exceptions:
   - **AVPlayer** streaming: use `?key=` on the media URL. The listener serves media and Range requests with `?key=` in place (no redirect). Custom headers for AVPlayer would need `AVURLAssetHTTPHeaderFieldsKey`, which is not public API (App Review risk) and is not passed to AirPlay. A resource loader (`AVAssetResourceLoaderDelegate`) could add the header but disables AirPlay of the URL and adds complexity. `?key=` is the supported path.
   - **AirPlay** receivers fetch the URL themselves and never see app headers, so `?key=` is required there.
   - **WKWebView** (the host's own UI): load the access link (`/?key=…`); the listener sets `sg_key` and 302s to a clean URL, and the web view keeps the cookie. Installing `sg_key` in the web view's cookie store before loading is also fine.
5. **Distinct error messages.**
   - 403 `text/html` (the "shared … only with an access link" page) → "The computer refused the access key": offer to paste the link again.
   - 403 JSON "not part of what is shared" → "This part of Lastbook stays on the host computer" (and for Chat: "Chat isn't shared from this computer").
   - 403 JSON "not allowed from this page" → "Use the computer's IP address, not its name".
   - 404 → not in the library. Connection refused or timeout → the reconnect screen (host asleep, sharing stopped, different network, Tailscale off). ATS failure (-1022) → a specific message.
6. UI: native Browse (shelves, collections, courses), Search (`/api/find`), Videos, PDFKit for documents, AVPlayerViewController for video, and the host's own `web/` UI in a WKWebView tab for encyclopedias, maps, guides and Chat. Keep screens organized so they can move to native later.
7. Video: AVPlayer with Range seeking, Picture in Picture, AirPlay and background audio. Detect AV1/VP9/WebM/MKV the device can't decode (read the MP4 sample entries with small Range requests, as `web/app.js` does). Prefer an H.264 sidecar if the server offers one, otherwise show "This video can't play on this device". No on-device transcoding.
8. Chat: only when the host shares it (see the signal above). Hide Chat otherwise, and say why in the library's info ("Chat isn't shared from this computer").
9. Resilience: handle the host sleeping, changing networks, sharing being stopped, or losing the NAS mount, with retry and a friendly reconnect screen. Never crash or spin forever. Saved items stay usable.
10. Security: secrets in the Keychain; TLS with a pinned fingerprint when Lastbook offers it. No analytics or third-party SDKs.
11. **App Transport Security.** The listener is plain HTTP. `NSAllowsLocalNetworking` covers LAN addresses but not Tailscale's 100.64.0.0/10 (CGNAT, not a "local" range to ATS), and `NSAllowsArbitraryLoads` is **ignored** when `NSAllowsLocalNetworking`, `NSAllowsArbitraryLoadsForMedia` or `NSAllowsArbitraryLoadsInWebContent` is present. `NSExceptionDomains` cannot name an IP range. So the app sets `NSAllowsArbitraryLoads` **alone**, and its own address check refuses anything that is not loopback, a private LAN range, link-local, or Tailscale (100.64/10, `fd7a:115c:a1e0::/48`). App Store review would need a justification; remove the exception once Lastbook serves HTTPS.
12. Accessibility: Dynamic Type, VoiceOver labels and sufficient contrast. Localization-ready strings.
13. NAS: the host (not this app) mounts it. The client only talks to the Lastbook server. No SMB in v1.

### Save on this device

The person can download items from a shared library onto **this** iPhone or iPad, for later or for use with no network. This is per item (or per collection the person picks), never the whole library.

**What can be saved** (verified on the listener; everything is a GET with the key):

| Content | Where it comes from | Opens offline with |
|---|---|---|
| PDFs and other documents | `/documents/…`, `/courses/…`, `/collections/…` (`path` from `/api/doc/<id>`) | PDFKit; text/Markdown natively |
| Saved web pages | `/pages/…` | WKWebView from the file (the HTML only; its images are separate requests) |
| Videos | `/videos/…`, `/videos-external/…` (Range, 206) | AVPlayer from the file, if the device can decode it |
| Video transcripts and thumbnails | `/api/transcript/<id>` (JSON cues), the item's `thumb` path, `/transcripts/…`, `/metadata/videos/…` | captions and poster beside the saved video |
| Encyclopedia articles | `/zim/<file>/<article>` (one sandboxed HTML page; images are further `/zim/` requests) | WKWebView from the saved files |
| A whole encyclopedia file | `/collections/<name>.zim` is served (can be many GB) | **Not in v1**: needs a ZIM reader on the device. At most offer "Export to Files" for another app such as Kiwix. |
| Page text and page images | `/api/page/<id>/<n>` (JSON text), `/api/page/<id>/<n>.png?w=` (needs poppler on the host) | optional, for quick previews |
| Maps | `/api/map/tile/z/x/y` (JSON vector tiles), terrain/aerial PNG tiles | **Not in v1.** The offline map database (`derived/geo/`) is not served; saving an area would mean thousands of tiles and a native renderer. |
| Search, catalog, Chat | not downloadable (`catalog.json` and `derived/` are 403; Chat needs the host model) | need the host |

**Requirements:**

1. **Per device.** Saves live on the device that saved them. They are not synced through iCloud or between devices unless a later decision says so.
2. **Where.** Files in the app sandbox under Application Support (`Offline/`), with `isExcludedFromBackup` set on that folder: the host still has every file, and large videos should not fill the person's iCloud backup. A small index (JSON) records the library, item, size, date, and the host's `Content-Length` / `Last-Modified` at save time. Temporary viewing copies stay in Caches and are not "saved".
3. **Size first.** Show the size (catalog `bytes`, or `HEAD` `Content-Length`) and the space left before downloading, and ask.
4. **Warnings.** Warn before a large download (for example over 200 MB) on a cellular or constrained network (`NWPathMonitor` `isExpensive` / `isConstrained`), and when it would leave little free space on the device (`volumeAvailableCapacityForImportantUsageKey`). Refuse a save that goes over the app's storage cap (a sensible default, changeable in Settings), with a clear message.
5. **Background downloads.** Use a background `URLSession` (`URLSessionConfiguration.background`) so downloads continue when the app is suspended, with `X-Lastbook-Key` on each request and the app delegate's background-events handler wired up. Show progress, allow cancel.
6. **Resumable.** Resume with `resumeData` where iOS provides it, and otherwise with HTTP `Range` from the partial file's size (the listener answers 206). A download interrupted by the host sleeping resumes when it is back.
7. **Downloaded screen.** Lists saved items grouped by library, with size and date, the storage used by the app, the cap, and the device's free space. Delete one, delete all, and delete all from one library.
8. **Save a whole collection or topic** (optional). From a collection (`/api/collection?name=`), a course, or a guide (`/api/topics`), offer "Save all (N items, X GB)" with the total shown first; it queues the items as single downloads and obeys the same cap and warnings.
9. **Staleness.** Show where and when each item was saved. When the library is reachable, compare the host's `Content-Length` / `Last-Modified` (from `HEAD`) and catalog `bytes` with what was saved; if they differ, mark the item "Updated on the computer" and offer to download it again. Never replace a saved copy silently.
10. **Offline use.** Saved items open with no network. Search, browse lists, encyclopedia links, maps and Chat still need the host unless that specific content was saved; say so in the UI and don't pretend the whole library is on the device.
11. **Playability.** Don't offer to save a video the device can't decode (AV1/VP9 without hardware support, WebM, MKV) unless an H.264 copy exists; explain why.
12. Optionally, mirror "saved" into Lastbook's own Saved list on the host only if the listener ever allows that write; today it doesn't, so keep the list on the device.

## Implementation status and plan

What `LastbookRemoteKit` and the app have today (v0.1, PR #1 in this repo):

- `LastbookClient`: header auth on every request, `keyedURL()` for AVPlayer/AirPlay, `webAppURL` for the web view, HEAD size, Range reads, error mapping for wrong key / not shared / host name / 404 / unreachable / ATS, and `AssistantStatus.chatAvailable`.
- `OfflineStore` (actor): explicit save of one item, foreground download in 8 MiB `Range` chunks into a `.part` file that resumes, a storage cap checked before downloading, an index that survives relaunch, delete one / delete all, `isExcludedFromBackup` on the folder.
- App: Save for offline with size confirmation, progress and cancel; a Downloaded screen (storage used against the cap) that opens PDFs, text, web pages and videos with no network; videos that can't play are not offered for saving.

Gaps to close, in order:

1. **Background downloads**: move `OfflineStore` downloads to a background `URLSession` with a delegate, `resumeData`, and `application(_:handleEventsForBackgroundURLSession:)`; keep the Range-from-partial fallback.
2. **Free space and cellular warnings**: device free space on the Downloaded screen and before a save; `NWPathMonitor` expensive/constrained check before large downloads.
3. **Staleness**: store `Content-Length` and `Last-Modified` from `HEAD` in `SavedItem`; a "Check for updates" pass when connected; "Download again".
4. **More content types**: encyclopedia articles (save the article HTML and the images it references), video transcripts and thumbnails beside saved videos.
5. **Save whole collection / topic** with a total-size confirmation and a queue.
6. **Delete all from one library** on the Downloaded screen.
7. **Native Chat** (optional): only when `chatAvailable`; otherwise keep Chat inside the host's web UI tab.
8. When Lastbook ships them: New key, pairing tokens, QR, Bonjour, TLS (then drop `NSAllowsArbitraryLoads`), MagicDNS, H.264 sidecars, file versions.

## NAS without a host (stretch, design only)

Write a short design note (`docs/REMOTE-NAS.md`) on what the app could do with an SMB share alone: opening PDFs and MP4s via the Files provider, and why search, the catalog, ZIM and maps need the engine. Recommend running the Lastbook server on the NAS (Docker or Python) as the supported path. Don't implement SMB parsing in v1.

## Out of scope

- App Store submission, signing team and bundle ID (leave placeholders in a git-ignored `Local.xcconfig`).
- A public relay or cloud service.
- On-device AI models, content packs, and installing or mirroring the whole library (an explicit non-goal; single items and chosen collections only).
- Syncing saved items between devices or through iCloud (unless decided later).
- Reading whole ZIM files or offline maps on the device in v1.
- Changing Lastbook's default privacy behavior, or depending on a Lastbook follow-up that has not landed. Ask before adding heavy dependencies or new network services.

## Acceptance criteria

Connecting and browsing:

- On the same Wi-Fi, a fresh iPhone and a fresh iPad can each connect with the access link (from the desktop share switch or from `server.py --lan`), search, open a PDF, open an encyclopedia article, and play and seek a playable video. The library itself is not installed on the device.
- The same works over Tailscale using the host's Tailscale IP.
- The library folder on an SMB share mounted on the host works end to end.
- Every native request carries `X-Lastbook-Key`; video uses `?key=` and plays, seeks and AirPlays; the web view loads the access link, follows the 302, and keeps working with the cookie.
- A wrong key shows the "access key not accepted" message (HTML 403); a route that isn't shared shows the "stays on the host computer" message (JSON 403); stopping sharing shows the reconnect screen. These are three different messages.
- With "Include Chat" off on the host (the default), Chat is hidden; with it on and the model running, Chat is offered. The client never calls setup, update, or other local-only host endpoints.
- Unplayable AV1 videos show a clear message, not a black screen.

Save on this device:

- Saving a document and a video shows the size and space left first; after confirming, both appear on the Downloaded screen with their sizes, and open after the host is unreachable (Airplane mode). Search and Chat say they need the computer.
- A large download on cellular or with low device storage shows a warning first. A save over the storage cap is refused with a clear message.
- A download continues when the app is sent to the background and the screen locks, and finishes or resumes later; a download interrupted by the host sleeping resumes (Range) when the host is back.
- Deleting one saved item, all items from one library, or everything frees the space shown on the Downloaded screen.
- Saved items are not in the device's iCloud backup and do not appear on the person's other devices.
- When a saved document changes on the host, the item is marked as updated there and can be downloaded again.
- Optional: "Save all" on a collection shows the total size first and saves each item, obeying the cap.

Unchanged elsewhere:

- Existing Lastbook desktop, `server.py --lan`, and iPad local-preview behavior is unchanged; this app is a separate project.

## Deliverables

1. The universal iPhone and iPad app, with a README covering build, sign-yourself steps, and how to test against `server.py --lan` and against the share switch in PR #343.
2. `docs/REMOTE-ACCESS.md` (setup, Tailscale-by-IP guidance, security model) and `docs/REMOTE-NAS.md` (design only).
3. Small, reviewable changes: connect and browse first, then Save on this device, then discovery/pairing once Lastbook has them.

Ask before changing the privacy model, adding dependencies, or talking to Lastbook APIs that are meant only for the host computer.
