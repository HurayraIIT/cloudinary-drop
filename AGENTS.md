# AGENTS.md

This is a guide for AI coding agents working on CloudDrop. Read it before changing anything. For the user-facing view, read [README.md](README.md).

## What this project is

CloudDrop is a **personal** macOS menu bar app. The user drops image or video files on its menu bar icon, and each one is uploaded to Cloudinary. The resulting public link opens in the default browser and is copied to the clipboard.

- It has one user, one Cloudinary account and two Macs, both on macOS 26. The **M1 MacBook Air (8 GB, fanless) is the main one**; the M4 Pro is an office Mac being returned. Tune anything CPU-, heat- or memory-sensitive for the Air.
- It is never distributed, notarized or put on the App Store.
- It is deliberately minimal, and resisting feature creep is part of the job (see [ADR 0004](docs/adr/0004-scope-boundaries.md)).

## Read these first

| File | Why |
|---|---|
| [CONTEXT.md](CONTEXT.md) | **The glossary.** Drop, Media File, Capture, Size Limit, Compression, Quality Level, Upload, Upload Queue, Share Link, Link History, Delete, Usage, Last Error, Cloudinary URL. Use these exact terms in code, comments, UI text and commits, and avoid the synonyms it lists under *Avoid* |
| [docs/adr/](docs/adr/) | **Why things are the way they are.** Don't "fix" anything an ADR explains without discussing it with the user first |
| [README.md](README.md) | Behaviour as the user sees it, plus the manual test checklist |

The ADRs:
- **0001:** native Swift + AppKit, built with SwiftPM and a Makefile. No Xcode project, no SwiftUI `MenuBarExtra`; Tauri and Electron were rejected with reasons.
- **0002:** the Cloudinary URL is pasted once and stored in the Keychain. Reading `~/.zshrc` and using an unsigned preset were rejected.
- **0003:** signed uploads go straight to Cloudinary, with no server. The Free-plan Size Limits are enforced on the Mac.
- **0004:** the explicit list of things that are out of scope.
- **0005:** short Share Links: random `d/<8 chars>` names, links built from the public_id (root path for images, no version), and uploads that never overwrite.
- **0006:** the Link History is fetched from Cloudinary's Search API, so both Macs show the same list; Cloudinary-made image thumbnails are the one transformation outside HEIC→JPG.
- **0007:** Delete from a Link History row: the signed `destroy` with `invalidate=true`, an alert with Cancel as default, Deleted assets hidden locally while search catches up.
- **0008:** videos are compressed on the Mac with the user's Homebrew ffmpeg (libx264) before uploading, and the Size Limit is checked afterwards. The menu has a Compress Videos toggle and three Quality Levels (CRF 22/24/26). Apple's encoder, slower presets, native resolution and retrying at lower quality were rejected.

`CONTEXT.md` is a glossary **only**: no implementation details. Add an ADR only for decisions that are hard to reverse, would surprise a future reader, **and** came from a real trade-off. Use the next number (`0008-…`) and keep it to a paragraph or two.

## Environment facts

- **Command Line Tools only, no Xcode.** `xcodebuild` doesn't work. Never add an `.xcodeproj`, `.xcworkspace`, asset catalogs, storyboards or anything else that needs Xcode.
- **Swift 6.x, `swift-tools-version:6.0`, Swift 6 language mode**, so strict concurrency checking is on. The platform is `.macOS("26.0")`.
- **No third-party dependencies.** Only Apple frameworks are used: AppKit, Foundation, CryptoKit, ImageIO, Security, ServiceManagement, UniformTypeIdentifiers and OSLog. Don't add Swift packages.
- **Builds are signed ad-hoc** (`codesign --sign -`) with the identifier `com.hurayraiit.clouddrop`. Each rebuild therefore changes the code signature, and macOS asks the user again for Keychain access on the next Drop. That's expected and accepted; don't try to fix it.
- **In zsh, `log` is a shell builtin.** Call `/usr/bin/log show …` or `/usr/bin/log stream …` explicitly.

## Commands

```sh
make test       # unit tests; the ONLY correct way to run them
make app        # release build → build/CloudDrop.app (ad-hoc signed)
make install    # make app, then kill the running app, copy it to /Applications and relaunch
make uninstall
make clean
```

> ⚠️ **Never use plain `swift test`.** Swift Testing ships with Command Line Tools but isn't on SwiftPM's search path. Without the `-F` and rpath flags in the Makefile, `swift test` either fails with `no such module 'Testing'` or, in some setups, **runs zero tests and exits 0**. `make test` passes the flags and fails if the output doesn't contain `Test run with N tests` with N > 0. XCTest isn't available at all, so don't use it.

A healthy run ends with a line like:

```
✔ Test run with 25 tests in 6 suites passed after 0.005 seconds.
```

Only run `make install` when it's appropriate. It replaces the app the user is actively using, and the in-memory Link History and Last Error are lost when it restarts.

## Architecture

```
Sources/
  CloudDropCore/                  Library target. Foundation-level logic, all unit-tested. No AppKit.
    CloudinaryCredentials.swift   Parses a Cloudinary URL (tolerates `export CLOUDINARY_URL="…"`, quotes, whitespace, ?query)
    PublicID.swift                public_id = d/<8 random a-z0-9>; the URL folder vs the console folder
    MediaKind.swift               image/video from a UTType; Size Limits; Refusal messages; checkMediaFile(...)
    ShareLink.swift               Share Link from public_id + format (root path for images, no version, HEIC/HEIF → .jpg); MenuText.truncateMiddle and fileSize
    Thumbnail.swift               Square, centre-cropped image thumbnail for the Link History via ImageIO (decodes small, never the whole file); the Cloudinary thumbnail URL and decoding it
    HistorySearch.swift           HistoryEntry; the Search API request for the Link History, reading its answer (403, rate limit), merging this Mac's unconfirmed Uploads and hiding Deleted ones; HistoryTime labels
    TemporaryFiles.swift          Names the multipart bodies, Drop folders and capture folders in $TMPDIR; isCapture; saves Captures to Downloads as `cd-<name>`; removeLeftovers() sweeps the rest and saves leftover Captures
    Uploader.swift                Signing, the streamed multipart upload with progress, reading the response, verify() (ping + upload-permission probe)
    Delete.swift                  The signed destroy request (invalidate=true), reading its answer, the delete-permission probe
    Usage.swift                   Usage (the menu line's text), UsageSchedule (when each call is due) and UsageReader: the Usage API's stored bytes and credits, and the account-wide image and video counts
  CloudDrop/                      Executable target: the AppKit app. Not unit-tested; use the manual checklist
    main.swift                    NSApplication with the .accessory activation policy
    AppDelegate.swift             Installs a hidden main menu (needed for ⌘V/⌘C in text fields), login item, StatusController; sweeps temp files at launch and quit
    StatusController.swift        NSStatusItem, drag destination, icon states, menu building, settings window
    HistoryRowView.swift          The custom menu row for one Link History entry: thumbnail, filename, size and time columns, Copy, Open and Delete buttons
    UsageRowView.swift            The Usage line's menu row: one label in the filenames' font and colour, never highlighted
    UploadQueue.swift             @MainActor Upload Queue: validation, sequential uploads, Deletes (alongside, not queued), Last Error, logging
    LinkHistory.swift             @MainActor Link History: throttled background refresh, rate-limit pause, this Mac's unconfirmed Uploads, hidden Deleted ones, thumbnail cache
    UsageTracker.swift            @MainActor Usage line: storage and credits hourly, counts every 5 minutes or after this Mac's Upload/Delete, the Link History's rate-limit pause
    SettingsWindowController.swift  One secure text field: parse, Uploader.verify, KeychainStore.save, then a warning if the key can't search or delete
    KeychainStore.swift           Generic password; service com.hurayraiit.clouddrop, account CLOUDINARY_URL
    LoginItem.swift               SMAppService.mainApp; registers once on first launch (on by default)
Tests/CloudDropCoreTests/         Swift Testing (`import Testing`, @Suite/@Test/#expect) for CloudDropCore only
Resources/Info.plist              LSUIElement=true (no Dock icon), LSMinimumSystemVersion 26.0
Makefile                          Build, bundle, sign, install, and the test wrapper
```

**Put logic in `CloudDropCore` whenever you can,** and test it there. The `CloudDrop` target should stay thin AppKit glue.

### How a Drop flows

1. `StatusController` registers the **status item's window** for drag types and makes itself that window's `delegate`. `NSWindow` forwards `NSDraggingDestination` calls to its delegate. This is the trick that makes dropping onto a menu bar icon work, so don't replace it with a SwiftUI or `MenuBarExtra` approach.
2. `draggingEntered`/`draggingUpdated` accept any file drag (`.copy`) but only **highlight** the button when at least one file is an image or video. This lets a PDF-only drop be refused with a visible Last Error rather than silently bouncing back.
3. `performDragOperation`:
   - calls `queue.beginDrop()`, which **clears the Last Error**
   - retries the Keychain read if the last one failed, then checks that credentials exist. If not, it refuses, saves any Captures in the Drop to Downloads, and opens settings when no Cloudinary URL is saved (not when the Keychain couldn't be read)
   - reads file URLs from the pasteboard, falling back to `NSFilePromiseReceiver`. Each promise is received into its own Drop folder and is deleted afterwards, whatever happened.
   - a Capture (a file URL in `…/TemporaryItems/…`, from a floating screenshot or screen recording thumbnail) is moved into its own capture folder at once, because macOS deletes it when the drag ends. It's deleted after a successful Upload; refused or failed, it's moved to `~/Downloads/cd-<name>` (`cd-<name> 2` on a clash) and the Last Error ends with "Saved to Downloads."
4. `UploadQueue.add` runs `checkMediaFile` (type and Size Limit). A file whose size can't be read is refused as unreadable, never waved past the Size Limit. A file that fails gets `refuse(message)`, which sets the Last Error and flashes ✗. A file that passes is appended to `pending`.
5. `drain()` uploads **one at a time**. For each success:
   - `ShareLink.make` builds the Share Link
   - it's copied to the clipboard and opened with `NSWorkspace.shared.open`
   - for an image, a thumbnail is made (off the main actor) while the file is still on disk
   - it's handed to `LinkHistory.add` as an unconfirmed entry, sorted by Cloudinary's `created_at` from the upload response
   - the ✓ flash is shown

   A failure sets the Last Error and flashes ✗, and the queue **continues** with the next file.
6. `StatusController.render()` picks the icon: flash (✓/✗, 2 s) > uploading (`arrow.up.circle` + ` NN%`) > idle (`icloud.and.arrow.up`).

### How the Link History refreshes

1. `LinkHistory.refresh()` runs at launch and from `menuNeedsUpdate`. It skips if a fetch is running, the last one started under 30 s ago, or a rate limit pause hasn't ended.
2. The menu is built at once from what's already known. When the fetch returns, an **open** menu is rebuilt only if its Link History section changed (public_ids, the problem line, loading/empty); a thumbnail arriving just updates its row. The highlight is restored by Share Link.
3. A successful fetch replaces the fetched list. `HistorySearch.stillUnconfirmed` keeps this Mac's own Uploads that search doesn't list yet, for up to 2 minutes after the Upload.
4. Image rows without a thumbnail get one from Cloudinary (`c_fill,w_44,h_44`, `.jpg`), cached in memory by public_id and pruned to what's shown.
5. Saving new credentials calls `LinkHistory.reset()`, which clears everything and refetches.

### How the Usage line refreshes

1. `UsageTracker.refresh()` runs at launch and from `menuNeedsUpdate`, next to the Link History's. It skips everything while `LinkHistory.isPaused`, and a rate limit it hits itself calls `LinkHistory.pause(until:)`: one key, one limit.
2. Storage and credits (`GET /usage`, one call) are due an hour after the last answer; Cloudinary only updates them daily. The counts (two searches) are due 5 minutes after the last answer, or sooner when the last answer started less than 15 s after this Mac's latest Upload or Delete. After a failure, either waits at least 30 s.
3. A success replaces that half; a 403 clears it, which hides the line until the next interval; anything else keeps the last values and is only logged. The line shows only when all four values are known.
4. An open menu is rebuilt only when the line's text changes. Saving new credentials calls `UsageTracker.reset()`.

### How a Delete flows

1. The row's trash button closes the menu, then `StatusController.confirmDelete` shows an `NSAlert` (run on the next main-actor turn, outside the menu's tracking loop). Cancel is added first and given Return; Delete is red and has no key equivalent.
2. `UploadQueue.delete` clears the Last Error and calls `Uploader.delete` at once, alongside any running Upload, on the same session.
3. `ok` and `not found` both succeed: `LinkHistory.remove` hides the public_id, and ✓ flashes. A failure sets the Last Error to `Couldn't delete <file>: …` and flashes ✗; the row stays.
4. `HistorySearch.stillDeleted` keeps hiding the public_id while fetches still list it, for up to 2 minutes after the Delete. No fetch is started for it, so the list is one short until the next refresh.

## Invariants: don't break these

These are decisions the user made during design. Changing any of them needs their explicit approval.

**Uploads**
- **Sequential uploads.** One at a time, in drop order. A new Drop joins the end of the queue, and a failed Upload never stops the rest.
- **Every successful Upload opens the Share Link in the browser *and* copies it.** The clipboard ends up holding the last success. There's no batch or joined-links mode.
- **Size Limits:** images ≤ 10,485,760 bytes and videos ≤ 104,857,600 bytes, checked **before** uploading: on the original for images and for videos when Compression is off or ffmpeg is missing, and on the compressed file otherwise. Images are never transcoded or downscaled. There are no chunked uploads (100 MB is already the plan's per-file maximum).
- **Compression** ([ADR 0008](docs/adr/0008-compress-videos-before-upload.md)):
  - ffmpeg is the user's Homebrew one, looked up at `/opt/homebrew/bin/ffmpeg` (a GUI app doesn't get the shell's PATH). It's never bundled or installed by the app. It's looked up when the menu opens and before each compression.
  - The pipeline is fixed: VideoToolbox decode, `scale_vt` only to fit within 1920×1920 (keep aspect, round down to even), libx264 `veryfast`, `-threads 2`, ≤ 30 fps, AAC 96 kbps, MP4 with `+faststart`. Only the CRF changes, from the Quality Level.
  - The toggle and Quality Level are per Mac (UserDefaults), on and CRF 22 by default, and **read at Drop time**: changing them never affects a video already dropped.
  - Every video is compressed when it's on, and the compressed file is uploaded **even if it's bigger** than the original. Its `display_name` ends in `.mp4` to match its Share Link.
  - While compressing, the icon is `arrow.down.right.and.arrow.up.left` with ` NN%` (ffmpeg's progress against the video's length), then the usual uploading icon.
  - No retry at a lower Quality Level, and no pausing for heat. Over the limit after compressing → refused (`rec.mov is still 120 MB compressed, video limit is 100 MB.`, plus `Try CRF 26.` below CRF 26), and saved to Downloads: a Capture as `cd-rec (original).mov` and `cd-rec (compressed).mp4`, a Finder file as `cd-rec (compressed).mp4` only.
  - ffmpeg fails (including sources the M1 can't hardware-decode, such as AV1 or VP9): the original is uploaded if it fits, with the Last Error `Couldn't compress rec.mov, uploaded it as is`; otherwise it's refused as usual. There's no software-decoding fallback.
  - A video refused for size without compressing ends its message with `Install ffmpeg to compress it.` (no ffmpeg) or `Turn on Compress Videos to fit it.` (off).
  - Quitting stops ffmpeg and deletes its partial output; the launch and quit sweep removes any left behind. Original files are never modified.
- **A user's files are never moved or deleted.** Only Captures and files received from a file promise are. `TemporaryFiles.isCapture` matches just `/TemporaryItems/` and CloudDrop's own `clouddrop-captures/`. Never widen it to `/tmp` or `/var/folders`: a file the user drags from there in Finder is theirs, and would be deleted after uploading.
- **A Capture is never lost.** It's the only copy, so whenever it won't be uploaded (refused, failed, no Cloudinary URL, or CloudDrop quits or crashes first) it's saved to Downloads, and the Last Error says so. Captures saved by the cleanup at quit are counted in the `capturesSavedAtQuit` UserDefaults key, and the next launch reports them with those found at launch: "Saved 2 unfinished Captures to Downloads", with a ✗ flash. Files received from a file promise are never saved: their original still exists.
- **Accepted types:** `UTType` conforming to `.image` → image, `.movie` → video. Everything else is refused.

**Naming and links**
- **The public_id format** is `d/<8 random a-z0-9>`, e.g. `d/k3f9x2ab`. The original filename never appears in it. It's sent as `display_name` instead, so the console still shows it (see [ADR 0005](docs/adr/0005-short-share-links.md)).
- **The Share Link is built from the response's `public_id` and `format`, not from `secure_url`:**
  - images: `https://res.cloudinary.com/<cloud>/d/<name>.<format>`, the root path URL form
  - videos: `https://res.cloudinary.com/<cloud>/video/upload/d/<name>.<format>`, because the root path form 404s for videos
  - there's never a version segment
  - `.heic`/`.heif` become `.jpg`
  - Videos uploaded after Compression are `.mp4`, so their Share Links are too.
  - Don't add `f_auto`, `q_auto` or other transformations. The Link History's thumbnail URLs are the only other transformation, and they're never a Share Link ([ADR 0006](docs/adr/0006-link-history-from-cloudinary.md)).
- **Uploads never overwrite.** They're sent with `overwrite=false`. On a taken name, Cloudinary answers **200** describing the *old* file with `"existing": true`, and `Uploader.uploadedFile` turns that into `UploadError.nameTaken`. Without this check, the new Upload would get the old file's link. Leaving the version out is only safe because of this: a default overwrite serves the new bytes even at the old versioned URL.

**Menu**
- **The Last Error clears when the next Drop or Delete begins**, not when an Upload next succeeds. Otherwise a refusal in a mixed Drop would vanish before the user saw it.
- **The Link History comes from Cloudinary** ([ADR 0006](docs/adr/0006-link-history-from-cloudinary.md)): the 10 newest assets in `asset_folder=clouddrop`, from either Mac, newest first by `created_at`.
  - It's held in memory only, thumbnails included; nothing is written to disk. That's why `HistorySearch` uses an ephemeral session.
  - The menu never waits on the network: it shows the current list, or "Loading…" before the first fetch has worked.
  - A failed refresh keeps the old list and adds a disabled "Couldn't refresh Link History" line with the reason as its tooltip. A rate limit (HTTP 420/429) shows "Link History paused until 03:00 PM" and stops refreshes until `X-FeatureRateLimit-Reset`. Neither touches the Last Error.
- **Each entry is a `HistoryRowView`** in a fixed 420 pt menu: one 30 pt line of `[thumbnail] filename … size time [Copy] [Open]`, with the Share Link, the full date and time, and the size as the tooltip.
  - The filename is `display_name`, or the public_id's last part when that's empty.
  - The time is `HistoryTime.label`: the 12-hour `02:34 PM` today (`HistoryTime.clock`, also used by the tooltip and the paused line), `Yesterday`, a weekday within the last week, then `d MMM`, plus the year for past years.
  - The size is Cloudinary's `bytes`: what was uploaded, so a compressed video shows the compressed size, and a HEIC shows the HEIC's size, not the JPEG its Share Link delivers. This Mac's unconfirmed Uploads take it from the upload response. `MenuText.fileSize` uses the Size Limit messages' binary units: `850 KB` under 1 MB, `4.2 MB` under 10 MB, then `87 MB`. An unknown size leaves the cell blank, never `0 KB`.
  - The size and time are right-aligned columns in grey monospaced digits. Each is as wide as its widest label in the menu, so every row lines up; there's no `·` separator.
  - Images get a 22 pt square thumbnail with 4 pt rounded corners: made locally for this Mac's Uploads, fetched from Cloudinary for the rest. Videos get the `film` symbol, never a preview, and images without a thumbnail get `photo`.
  - The filename is shortened in the middle to the width that's left (`.byTruncatingMiddle`), not to a character count.
  - Clicking the row or Copy copies the link (and does **not** open it). Open opens it without copying. Every action closes the menu, and a copy flashes ✓.
  - Delete (`trash`, after Open with a 10 pt gap) asks first in an alert naming the file, with Cancel as the default button. It works on any row, from either Mac and in either public_id shape. It never touches the clipboard, even if it holds the Deleted Share Link ([ADR 0007](docs/adr/0007-delete-from-the-link-history.md)).
  - A view in a menu item draws its own highlight: `menu(_:willHighlight:)` sets `isHighlighted` for hover and arrow keys. Return sends the item's action, which copies.
  - The buttons are always visible: grey normally, white on the highlighted row (an accent colour would vanish on the accent-coloured highlight).
- **The compression section** sits between the Link History and the Usage line, with a separator above and below. It uses native items, like Launch at Login:
  - `Compress Videos` with a checkmark, then three indented checkmark items, shown only while it's on: `CRF 22 · Best quality`, `CRF 24`, `CRF 26 · Smallest files`.
  - Without ffmpeg, `Compress Videos` is disabled and unchecked (whatever is saved), with a grey `Please install ffmpeg` line below it and no Quality Levels.
- **The Usage line** is one 30 pt `UsageRowView` after the separator under the compression section, with no separator below it: `1,210 images · 26 videos · 636 MB · 12% of credits`.
  - It's a view because macOS draws a disabled item's title dimmed and smaller. It uses the menu font with monospaced digits in the filenames' colour, lines up with the menu items below (Set Cloudinary URL… and Launch at Login), and never highlights.
  - It covers the **whole account**, not just `asset_folder=clouddrop`; raw files aren't counted.
  - The Free plan has **no storage limit**: storage, bandwidth and transformations share 25 credits a month. So there's no "remaining storage"; `credits.used_percent` (whole number, `<1%` below 1%) is the only measure of what's left.
  - Storage uses `MenuText.fileSize`, which steps to `1.3 GB` from 1000 MB up.
  - No tooltip, no "Loading…", never the Last Error. Hidden until every value is known.
- **Quit is immediate**, with no confirmation while uploads are running.
- **No notifications and no sounds.** Feedback is the icon only.

**Setup**
- **Launch at Login** is registered once on first launch, tracked by the `didApplyDefaultLoginItem` UserDefaults flag, and toggled from the menu.
- **Credentials** are read from the Keychain once, at launch for the first Link History fetch, and cached in `StatusController`. After a rebuild the Keychain prompt therefore appears as soon as the new build starts. The settings window updates the cache when it saves.
  - Only "no item" is cached as missing. Any other failure (e.g. Deny on the prompt) sets the Last Error "Couldn't read the Cloudinary URL from the Keychain" and is retried on the **next Drop only**, never on menu clicks, so a Deny doesn't bring the prompt back every time the icon is clicked.

## The Cloudinary API: what matters

**Signed upload**
- Endpoint: `POST https://api.cloudinary.com/v1_1/<cloud>/<image|video>/upload`, multipart. The resource type is explicit, not `auto`.
- Signed params: `asset_folder`, `display_name`, `overwrite`, `public_id` and `timestamp`. The signature is SHA-1 of the sorted `k=v` pairs joined by `&`, followed by the secret. `api_key`, `signature` and `file` are **not** signed. The signing test includes the example from Cloudinary's docs.
- **The account uses dynamic folder mode.** The legacy `folder` param would only set the console folder, not the URL path. So we send **both**:
  - `asset_folder=clouddrop` for the console folder
  - `public_id=d/…` for the URL path

  They're independent on purpose: a short URL path, and a readable console folder that also holds the uploads made before ADR 0005.

  Don't switch to `folder`.

**Timeouts**
- `timeoutIntervalForRequest = 60`, an idle/stall timeout.
- `timeoutIntervalForResource = 24h`. A 100 MB video on slow Wi-Fi can take minutes, so don't add an overall deadline.

**Memory**
- The multipart body is **streamed to a temp file** in 1 MB chunks, then sent with `session.upload(for:fromFile:delegate:)`.
- Each chunk is copied inside `autoreleasepool`. Without it every chunk stays alive until the upload finishes: a 75 MB video peaked at about 80 MB before this fix and about 17 MB after. Never load a whole file into `Data`.
- Progress comes from a per-task `URLSessionTaskDelegate` (`didSendBodyData`) and is hopped to the main actor. `UploadQueue` ignores progress from an earlier Upload and only redraws the icon when the whole percentage changes.
- `UploadQueue` keeps **one `Uploader` (one `URLSession`)** and reuses it while the Cloudinary URL stays the same. A replaced one is `invalidate()`d.
- Quitting mid-upload skips the `defer` that deletes the multipart body, so `TemporaryFiles.removeLeftovers()` runs at launch and in `applicationWillTerminate`. It only touches `clouddrop-*.multipart`, `clouddrop-drops/` and `clouddrop-captures/`, and it saves any Capture left in `clouddrop-captures/` to Downloads before deleting the folder.

**Checking credentials: `Uploader.verify`**
1. `GET /ping` with Basic auth. This proves the key and secret are valid, but **not** that the key may upload.
2. A signed `POST /image/upload` with **no file**:
   - a key that can upload gets `400 "Missing required parameter - file"`
   - a key without upload permission gets `403`
   - nothing is created either way

   This step exists because the user once pasted a restricted key: it passed the ping, then every upload failed with `403 … missing permissions (actions=["create"])`.

After `verify` passes and the key is saved, the settings window runs one search with `max_results=1` and one `Uploader.probeDeletePermission` (a signed destroy of a random public_id that can't exist: `not found` means allowed). Only a 403 counts: the key stays saved, and the window stays open with a warning about the Link History or Delete. A network error or rate limit says nothing about the key and is ignored.

**Delete**
- `POST /v1_1/<cloud>/<image|video>/destroy`, form-encoded. Signed params: `invalidate=true`, `public_id`, `timestamp`; `api_key` and `signature` aren't signed. Values are percent-encoded in the body (older public_ids contain the filename) but signed as is.
- It's the Upload API, so it doesn't count toward the Admin API's 500 calls an hour. Don't switch to the Admin API's `DELETE /resources/…` for this.
- It answers 200 with `{"result":"ok"}` or `{"result":"not found"}`; both count as gone. A 403 becomes `DeleteError.notAllowedToDelete`.
- `invalidate=true` purges the CDN: a live test saw the Share Link 404 within 20 seconds.

**Link History search**
- `POST /v1_1/<cloud>/resources/search` with Basic auth and a JSON body: `expression=asset_folder=clouddrop`, `sort_by created_at desc`, `max_results=10`, and `fields` for `public_id`, `format`, `resource_type`, `created_at`, `display_name` and `bytes`.
- It returns images and videos in one call. Anything else is skipped.
- **Filter on the asset folder.** The account holds hundreds of assets from another tool in the root folder.
- The folder has two public_id shapes: `d/xxxxxxxx`, and the older `clouddrop/YYMMDD_HHMMSS_…`. Share Links built from either resolve.
- **Rate limit:** the Admin API, Search included, allows 500 calls an hour on the Free plan. That's shared by both Macs and every tool using the key. It's reported in `X-FeatureRateLimit-Limit/-Remaining/-Reset`, and exceeding it answers 420 (or 429).
- **Search is eventually consistent:** a new asset can take a few seconds to show up. That's why `LinkHistory` keeps unconfirmed entries.
- Each thumbnail costs one transformation per image, once; repeat requests are free.

**Usage**
- `GET /v1_1/<cloud>/usage` with Basic auth: `storage.usage` (bytes) and `credits.used_percent`. It's updated once a day (`last_updated`).
- Counts: `POST /resources/search` with `expression=resource_type:image` (then `video`) and `max_results=0`, reading `total_count`. The Free plan doesn't support `aggregate`, so this is the cheapest way.
- All three are Admin API calls on the shared 500-an-hour budget: at most about 25 an hour from this line.

**Errors**
- `UploadError.cloudinary(message)` carries Cloudinary's `error.message`, plus `(HTTP n)`.
- A 403 becomes `UploadError.notAllowedToUpload(cloudinaryMessage:)`. The menu shows the readable "isn't allowed to upload" message, and its `description` (what the log prints) adds Cloudinary's own message.

**The account's plan:** Free. Size limits are 10 MB per image and 100 MB per video. If the plan changes, update `MediaKind.sizeLimit`, the tests, the README and ADR 0003 together.

## Coding conventions

- **Swift 6 strict concurrency must compile cleanly, with no warnings.**
  - UI types and `UploadQueue` are `@MainActor`.
  - Core types are `Sendable` structs or enums.
  - Hop back to the main actor with `Task { @MainActor in … }`.
  - Use `@unchecked Sendable` only on tiny NSObject delegates that hold nothing but `let` `@Sendable` closures, as `ProgressDelegate` does.
- **Match the surrounding style:**
  - small files by responsibility
  - `///` doc comments that say *why*, used sparingly
  - no `// MARK:` noise beyond the existing sections in `StatusController`
  - expression-bodied `switch` returns where the code already uses them
- **Use glossary terms in names and UI text**, for example "Share Link", not "public URL", in comments and messages.
- **User-facing error messages** are short, specific sentences that name the file: `"rec.mov is 250 MB, video limit is 100 MB"`. They appear in the menu's ⚠︎ line, truncated to 60 characters with the full text in the tooltip.
- **Logging** uses `Logger(subsystem: "com.hurayraiit.clouddrop", category: "upload")` (the global `log` in `UploadQueue.swift`). Mark non-secret strings `privacy: .public` so they're readable. **Never log the API secret, the Cloudinary URL or the Authorization header.**
- **SF Symbols only** for icons (template images), and no asset catalogs. The status item title uses monospaced digits so `NN%` doesn't jitter.

## Testing

**Unit tests (`make test`)**
- Add or extend a `@Suite` in `Tests/CloudDropCoreTests/CloudDropCoreTests.swift` for **any change to `CloudDropCore`**.
- Use parameterized `@Test(arguments:)` for tables of inputs.
- They cover: parsing the Cloudinary URL, public_id names, signing (including Cloudinary's documented example), media kind detection, Size Limit boundaries and messages, reading upload responses (including the 403 and taken-name cases), the temp-file sweep, thumbnails (local, and Cloudinary's URL and decoding), Share Link shapes (image, video, HEIC), menu truncation and file sizes, the Link History search (request, reading results, 403, rate limit, merging unconfirmed Uploads, hiding Deleted ones) and its time labels, the Usage line (requests, reading answers, its text), and Deletes (the destroy request and its signing and encoding, reading the answer).

**App target**
- It has no unit tests. After touching `StatusController`, `UploadQueue`, the settings window, the Keychain or the login item, go through the **manual checklist in README.md**. If you can't run it (you can't drag files in a GUI), say so plainly and list which items the user needs to check.

**Live checks against Cloudinary**
- These are allowed, carefully. The account is the user's real one.
- Build a throwaway harness **outside the repo**, in a scratch or temp directory:
  ```sh
  swiftc -O Sources/CloudDropCore/*.swift harness/main.swift -o harness/e2e
  ```
  Here `main.swift` calls `Uploader` or `HistorySearch` directly and reads credentials from an environment variable. Use top-level code, not `-parse-as-library`.
- To get credentials without printing them, extract `CLOUDINARY_URL` from `~/.zshrc` with `grep` into a shell variable. Never `echo` it, and never read the app's Keychain item: that would prompt the user.
- Upload only tiny generated files. **Delete every test asset afterwards**, with `Uploader.delete` or the Admin API's `DELETE /v1_1/<cloud>/resources/<type>/upload?public_ids[]=…`.
- To test failure paths without touching the account, use fake credentials such as `cloudinary://1:2@nonexistent-cloud`.

**Measuring memory**
- For the harness, use `/usr/bin/time -l` and look at the `peak memory footprint` line.
- For the running app, use `footprint -p $(pgrep -x CloudDrop)` or `top -l 3 -pid …`.

**Diagnosing the running app:**

```sh
/usr/bin/log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
/usr/bin/log show --last 30m --info --predicate 'subsystem == "com.hurayraiit.clouddrop"'
```

The app's Last Error text is only in memory. **Ask the user to read the ⚠︎ line before reinstalling**, because `make install` restarts the app and loses it.

## Known gotchas

- **⌘V in the settings field needs `NSApp.mainMenu`.** A menu-bar-only (`LSUIElement`) app has no visible menu bar, but without an Edit menu, key equivalents like ⌘V don't reach the text field. `AppDelegate.makeMainMenu()` provides a hidden one. Keep it.
- **Activating windows:** call `NSApp.activate()` before showing the settings window, or it opens behind other apps.
- **The Keychain prompt** only appears after a rebuild, not on first save, because the app that created the item is trusted automatically. The Link History's fetch at launch reads the Keychain, so after `make install` the prompt appears right away.
- **Browser drags** aren't officially supported (ADR 0004). If a browser offers a file promise, it may still upload. This is known and accepted; don't add special handling unless the user asks.
- **The notch:** on the MacBook Pro, menu bar items that don't fit are hidden behind the notch. This is an accepted risk; there's no fallback trigger by design.
- **SMAppService** works best when the app lives in `/Applications`, which is why `make install` copies it there.

## Out of scope (ADR 0004)

Don't add any of these unless the user explicitly asks, and then revisit ADR 0004:
- renaming uploads (deleting is in scope since [ADR 0007](docs/adr/0007-delete-from-the-link-history.md))
- Cloudinary transformations (beyond HEIC → JPG and the Link History's thumbnails). Compressing videos on the Mac is in scope ([ADR 0008](docs/adr/0008-compress-videos-before-upload.md))
- other cloud services
- Link History written to disk
- clipboard images, browser-drag support, non-media files
- auto-update
- a Dock icon
- retries
- a quit confirmation
- notifications and sounds
- a settings UI beyond the one field, Launch at Login, and the compression section

## Security and privacy rules

- **Never print, log, commit or paste** the API secret or the full Cloudinary URL. That covers terminal output, commit messages and chat. It's fine to refer to a key by its last 4 characters.
- **Credentials live only in the login Keychain** (service `com.hurayraiit.clouddrop`) and in the user's own `~/.zshrc`. Don't add `.env` files, config files or UserDefaults storage for them.
- Don't read the app's Keychain item from the shell (`security find-generic-password …`). It triggers a prompt and exposes the secret.
- **Every file uploaded to Cloudinary is public.** Only upload test assets you generated, and delete them.

## Git workflow

- **Repo:** `git@github.com:HurayraIIT/cloudinary-drop.git` (private). The branch is `main`.
- **Before committing:** `make test` must pass, and `make app` must build without warnings or errors.
- **Commit messages:** an imperative subject under about 70 characters, then a body that explains **why**, including the symptom and root cause for bug fixes. End with the co-author trailer the harness asks for.
- **Keep the docs in step with the code:**
  - glossary change → `CONTEXT.md`
  - behaviour change → the README tables and the manual checklist
  - a decision → an ADR
  - a change to an invariant → this file
- **Push** only when the user asks, or when the task clearly includes shipping it.
- **Never commit** `build/`, `.build/` or `.swiftpm/`; they're gitignored.
