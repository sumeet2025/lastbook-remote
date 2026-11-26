# Testing Lastbook Remote on your iPhone and iPad

This is v0.1. It was built and its networking package was tested on Linux against a real Lastbook share listener, but the app itself (SwiftUI, PDFKit, AVKit, WebKit) has **not been compiled yet**: that needs Xcode. If the first build fails, copy the first error from Xcode's Issue navigator and send it back.

You need: a Mac with Xcode 16 or later, Python 3.11+, your iPhone and/or iPad with a cable, and an Apple ID (a free one works for your own devices).

## 1. Share a library from your Mac (Lastbook PR #343 branch)

```bash
git clone -b share-with-devices https://github.com/sumeet2025/lastbook.git ~/src/lastbook-pr343
cd ~/src/lastbook-pr343
```

Pick **one** of these:

**A. Command line (quickest).** Point it at the library the Lastbook app already installed:

```bash
python3 server.py --lan --data "$HOME/Library/Application Support/Lastbook/LastbookData"
```

**B. A small test library**, if you'd rather not use the real one (it has two PDFs, text, Markdown, a web page, an H.264 video and an AV1 video):

```bash
git clone https://github.com/sumeet2025/lastbook-remote.git ~/src/lastbook-remote
python3 ~/src/lastbook-remote/scripts/make_sample_library.py ~/lastbook-sample   # needs ffmpeg for the videos: brew install ffmpeg
python3 server.py --lan --no-index --data ~/lastbook-sample
```

**C. The desktop app's switch** (what PR #343 adds):

```bash
python3 -m venv .venv
.venv/bin/pip install -r packaging/requirements_macos.txt
.venv/bin/python app/main.py
```

Then Library and local AI → turn on **Share this library with my devices** → Copy the link. It uses the first free port in 8890–8899.

With A or B, the terminal prints:

```
Lastbook is sharing on this network: http://192.168.1.20:8890/?key=AbCd…
```

Keep that link; you'll paste it into the app. If macOS asks whether Python may accept incoming connections, choose **Allow**. If `server.py` stops with a missing-module error, use the virtual environment from C (`.venv/bin/python server.py --lan …`).

Quick check from the Mac: open the link in Safari; the Lastbook page should load. Without `?key=…` it should say the guide is shared only with an access link.

## 2. Build and run the app

```bash
cd ~/src/lastbook-remote            # clone it as in 1B if you haven't
git fetch && git checkout v0.1-app  # until the v0.1 pull request is merged
cp Config/Local.xcconfig.example Config/Local.xcconfig
open -e Config/Local.xcconfig
```

In `Config/Local.xcconfig` set:

- `DEVELOPMENT_TEAM` to your team ID. Find it in Xcode → Settings → Accounts → your Apple ID → the team; or developer.apple.com → Account → Membership details. Your free "Personal Team" is fine.
- `LASTBOOK_BUNDLE_ID_PREFIX` to something unique to you, such as `com.sumeetpaul`. The app's ID becomes `com.sumeetpaul.lastbookremote`.

Then:

1. `open LastbookRemote.xcodeproj`. Xcode resolves the local `LastbookRemoteKit` package by itself.
2. Plug in the iPhone. On the phone, turn on Settings → Privacy & Security → **Developer Mode** if Xcode asks (the phone restarts).
3. In Xcode's toolbar pick the **LastbookRemote** scheme and your iPhone, and press **Run** (⌘R).
4. With a free Apple ID, the first launch is blocked: on the phone open Settings → General → VPN & Device Management → your Apple ID → **Trust**. Run again.
5. Repeat with the iPad (same project, pick the iPad as the destination).

If signing complains: open the LastbookRemote target → Signing & Capabilities and check that the team shows yours. You can choose it there, but it is lost the next time someone runs `xcodegen`; `Local.xcconfig` keeps it.

## 3. What to check

Connect (same Wi-Fi as the Mac):

1. Tap **Add a library** → **Paste access link**. The IP, port and key fill in. Tap **Test connection**: you should see "Connected: N items". **Save**.
2. iOS asks to find devices on your local network → **Allow**. (If you denied it: Settings → Lastbook Remote → Local Network.)
3. The library opens on **Browse**.

Browse and read:

4. Open a shelf, then a collection (a course shows all its PDFs and videos), then a PDF. It opens in the native viewer; pinch to zoom, scroll pages.
5. **Search** for something in the library (`water` in the test library). Matches are in bold. Opening a PDF result should land on the matching page.
6. Open a text or Markdown item, and a saved web page.
7. The **Lastbook** tab shows the Mac's own Lastbook interface: try an encyclopedia article and the map.

Video:

8. **Videos** → play an H.264 video (`Test pattern (H.264)` in the test library). Seek around, try Picture in Picture, AirPlay to a TV if you have one, and lock the phone (sound should keep playing).
9. Open an AV1 video (`Test pattern (AV1)`). On most iPhones and iPads you should see "This video is in the AV1 format, which this iPhone can't play…", not a black screen. On an iPhone 15 Pro or later, or a recent M-series iPad, it may play, which is correct.

Save for offline:

10. On a PDF and on a video, tap **Save for offline**. A dialog shows the size and the space left. Save; a progress bar shows; then "Saved".
11. Open **Downloaded** (tab, or from the library list). Both items are there with sizes.
12. Turn on Airplane mode (or stop `server.py` with Ctrl-C). Open both items from Downloaded: they should open and play. The library tabs should show the reconnect screen, not spin forever. Turn the network back on and tap **Try again**.
13. Settings → set the offline limit to 100 MB, then try to save something larger: it should be refused with a clear message. (Reset it afterwards.)
14. Delete one saved item (swipe), then **Delete all**; the used space goes back to zero.

Access and security:

15. Edit the library, change one character of the key, save, open it: "Access key not accepted".
16. Stop sharing (Ctrl-C `server.py`, or Stop sharing), delete `derived/lan-key` in the **library data folder** (the folder you passed to `--data`), and start sharing again: the old key stops working; paste the new link. Stopping and starting without deleting the file keeps the same key.
17. Try adding a public IP (e.g. 8.8.8.8) or a name (`mymac.local`): the app refuses with an explanation.

Tailscale (away from home):

18. Install Tailscale on the Mac and the iPhone, same account. On the Mac run `tailscale ip -4` (or copy the 100.x address from the Tailscale menu).
19. In the app, add a second library with that 100.x IP, port 8890, and the same key. Switch the phone to cellular (Wi-Fi off), keep Tailscale on, and repeat 4, 5 and 8.
20. Use the library switcher (computer icon, top left) to move between the two.

iPad:

21. Rotate, and try Split View / Stage Manager. Lists, the PDF viewer and the player should resize.

## 4. Send back

- Any Xcode build error (the first one is enough), with the file and line.
- For anything that misbehaves: the step number, iPhone or iPad model and iOS version, a screenshot, and the last lines of the `server.py` terminal.

## Run the package tests yourself (optional)

```bash
cd ~/src/lastbook-remote/LastbookRemoteKit
swift test
LASTBOOK_TEST_LINK='http://127.0.0.1:8890/?key=…' swift test   # with server.py --lan running on the test library from 1B
```

The live tests expect the test library from step 1B (they look for its item IDs).
