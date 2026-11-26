# Remote access and security

## How the app connects

Lastbook's share listener (`python3 server.py --lan`, or **Share this library with my devices** in the desktop app from [Lastbook PR #343](https://github.com/Immortal-Protocols/lastbook/pull/343)) listens on every network interface, plain HTTP, port 8890 (the desktop app uses the first free port in 8890–8899). It prints or shows an access link:

```
http://192.168.1.20:8890/?key=AbCdEf…
```

The key is in `derived/lan-key` inside the **library data folder** (the `LastbookData` folder, or whatever `--data` points to). It stays the same when you stop and start sharing; to make a new one, stop sharing, delete that file, and start sharing again. Every request needs it. The listener accepts it four ways (checked in this order: query, Bearer, header, cookie), and this app uses three:

| Where | Used by this app for |
|---|---|
| `X-Lastbook-Key` header | every API call, document, thumbnail and Save for offline download |
| `?key=` in the URL | video streaming: AVPlayer can't add a header to its Range requests without private API, and an AirPlay receiver fetches the URL itself. Media, API and Range requests with `?key=` are served in place (no redirect). |
| `sg_key` cookie | the web views only. Opening the access link (`/?key=…`) as a page sets the cookie and redirects (302) to the same address without the key, so it leaves the address bar. The app also puts the cookie in the web view's store before loading. |
| `Authorization: Bearer` | not used |

The listener serves only a read-only allowlist: library browsing, files, search, encyclopedias, maps and videos. Setup, updates, notes, battery, local-AI controls, tools and the share switch itself answer 403 to other devices, and this app never asks for them. Chat with the host's local AI is a separate option on the host ("Include Chat with this computer's local AI"), off by default and never on with `server.py --lan`. When it is off, `/api/assistant/status` answers `{"shared": false, …}` and `POST /api/chat` is a JSON 403; the app hides Chat.

Without the key, or with a wrong one, everything is 403 with an HTML page ("This guide is shared on this network only with an access link…"), including `/`. A route that is not shared is a different 403, JSON `{"error": "This is not part of what is shared from this library."}`. The app shows different messages for the two. Stopping sharing closes the port. The app's API session stores no cookies, so a changed key or stopped share takes effect on the next request.

## Addresses

Lastbook accepts only `localhost` or a bare IP address in the `Host` header (`host_ok()`); names, including Tailscale MagicDNS names, are refused. The app therefore asks for an IP and refuses:

- public internet addresses (the listener is plain HTTP with a key in the link; don't forward the port);
- host names (they would be refused by Lastbook anyway).

It allows loopback, private LAN ranges (10/8, 172.16/12, 192.168/16, 169.254/16, IPv6 ULA and link-local), and Tailscale (100.64.0.0/10, `fd7a:115c:a1e0::/48`).

## Away from home: Tailscale

1. Install Tailscale on the computer and on the iPhone or iPad, signed in to the same tailnet.
2. On the computer, find its Tailscale IPv4 address (Tailscale menu → the computer → copy the 100.x.y.z address, or `tailscale ip -4`).
3. In the app, edit the library (or add a second one) with that IP and the same port and key.

Both devices need Tailscale on. Nothing is exposed to the internet.

## App Transport Security

iOS blocks plain HTTP by default. `NSAllowsLocalNetworking` covers LAN addresses but, by most reports, not Tailscale's 100.64.0.0/10 (CGNAT) range, `NSExceptionDomains` cannot name an IP range, and `NSAllowsArbitraryLoads` is ignored whenever a narrower ATS key (`NSAllowsLocalNetworking`, `…ForMedia`, `…InWebContent`) is present. So this build sets `NSAllowsArbitraryLoads` alone, and the app's own address check (above) keeps it from talking to the internet. That key would need a justification in App Store review; once Lastbook serves HTTPS with a pinned certificate, it can go.

## Saved items

Save on this device writes single files into the app's sandbox (Application Support, excluded from iCloud backup, not synced to your other devices), with a storage cap. Nothing else from the library is stored, apart from a capped viewing cache (Caches) that Settings → Clear cache empties.

## When Lastbook supports it

A "New key" button, pairing tokens with a list and revoke, a QR code, Bonjour discovery (`_lastbook._tcp`, no secrets in TXT), TLS with a pinned fingerprint, MagicDNS names, and published H.264 copies of AV1/VP9 videos. The app will adopt them without dropping the access-link path.
