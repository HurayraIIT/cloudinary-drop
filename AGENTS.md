# AGENTS.md

This is a guide for AI coding agents working on CloudDrop. Read it before changing anything. For the user-facing view, read [README.md](README.md).

## What this project is

CloudDrop is a **personal** macOS menu bar app. The user drops image or video files on its menu bar icon, and each one is uploaded to Cloudinary. The resulting public link opens in the default browser and is copied to the clipboard.

- It has one user, one Cloudinary account and two Macs (M1 Air and M4 Pro), all on macOS 26.
- It is never distributed, notarized or put on the App Store.
- It is deliberately minimal, and resisting feature creep is part of the job (see [ADR 0004](docs/adr/0004-scope-boundaries.md)).

## Read these first

| File | Why |
|---|---|
| [CONTEXT.md](CONTEXT.md) | **The glossary.** Drop, Media File, Size Limit, Upload, Upload Queue, Share Link, Link History, Last Error, Cloudinary URL. Use these exact terms in code, comments, UI text and commits, and avoid the synonyms it lists under *Avoid* |
| [docs/adr/](docs/adr/) | **Why things are the way they are.** Don't "fix" anything an ADR explains without discussing it with the user first |
| [README.md](README.md) | Behaviour as the user sees it, plus the manual test checklist |

The ADRs:
- **0001:** native Swift + AppKit, built with SwiftPM and a Makefile. No Xcode project, no SwiftUI `MenuBarExtra`; Tauri and Electron were rejected with reasons.
- **0002:** the Cloudinary URL is pasted once and stored in the Keychain. Reading `~/.zshrc` and using an unsigned preset were rejected.
- **0003:** signed uploads go straight to Cloudinary, with no server. The Free-plan Size Limits are enforced on the Mac.
- **0004:** the explicit list of things that are out of scope.

`CONTEXT.md` is a glossary **only**: no implementation details. Add an ADR only for decisions that are hard to reverse, would surprise a future reader, **and** came from a real trade-off. Use the next number (`0005-…`) and keep it to a paragraph or two.

## Environment facts

- **Command Line Tools only, no Xcode.** `xcodebuild` doesn't work. Never add an `.xcodeproj`, `.xcworkspace`, asset catalogs, storyboards or anything else that needs Xcode.
- **Swift 6.x, `swift-tools-version:6.0`, Swift 6 language mode**, so strict concurrency checking is on. The platform is `.macOS("26.0")`.
- **No third-party dependencies.** Only Apple frameworks are used: AppKit, Foundation, CryptoKit, Security, ServiceManagement, UniformTypeIdentifiers and OSLog. Don't add Swift packages.
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
    PublicID.swift                public_id = clouddrop/<yyMMdd_HHmmss>_<4-char random>_<slug>; the slug rules
    MediaKind.swift               image/video from a UTType; Size Limits; Refusal messages; checkMediaFile(...)
    ShareLink.swift               Share Link from secure_url (the HEIC/HEIF → .jpg exception); MenuText.truncateMiddle
    Uploader.swift                Signing, the streamed multipart upload with progress, verify() (ping + upload-permission probe)
  CloudDrop/                      Executable target: the AppKit app. Not unit-tested; use the manual checklist
    main.swift                    NSApplication with the .accessory activation policy
    AppDelegate.swift             Installs a hidden main menu (needed for ⌘V/⌘C in text fields), login item, StatusController
    StatusController.swift        NSStatusItem, drag destination, icon states, menu building, settings window
    UploadQueue.swift             @MainActor Upload Queue: validation, sequential uploads, Link History, Last Error, logging
    SettingsWindowController.swift  One secure text field: parse, Uploader.verify, KeychainStore.save
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
   - checks that credentials exist; if not, it refuses and opens settings
   - reads file URLs from the pasteboard, falling back to `NSFilePromiseReceiver`. Promised files are received into a temporary folder and deleted after uploading.
4. `UploadQueue.add` runs `checkMediaFile` (type and Size Limit). A file that fails gets `refuse(message)`, which sets the Last Error and flashes ✗. A file that passes is appended to `pending`.
5. `drain()` uploads **one at a time**. For each success:
   - `ShareLink.make` builds the Share Link
   - it's copied to the clipboard and opened with `NSWorkspace.shared.open`
   - it's added to the front of the Link History, which is capped at 10
   - the ✓ flash is shown

   A failure sets the Last Error and flashes ✗, and the queue **continues** with the next file.
6. `StatusController.render()` picks the icon: flash (✓/✗, 2 s) > uploading (`arrow.up.circle` + ` NN%`) > idle (`icloud.and.arrow.up`).

## Invariants: don't break these

These are decisions the user made during design. Changing any of them needs their explicit approval.

**Uploads**
- **Sequential uploads.** One at a time, in drop order. A new Drop joins the end of the queue, and a failed Upload never stops the rest.
- **Every successful Upload opens the Share Link in the browser *and* copies it.** The clipboard ends up holding the last success. There's no batch or joined-links mode.
- **Size Limits:** images ≤ 10,485,760 bytes and videos ≤ 104,857,600 bytes, checked **before** uploading. There's no transcoding or downscaling, and no chunked uploads (100 MB is already the plan's per-file maximum).
- **Accepted types:** `UTType` conforming to `.image` → image, `.movie` → video. Everything else is refused.

**Naming and links**
- **The public_id format** is `clouddrop/260928_141503_k3f9_<slug>`. The slug rule, in order:
  1. drop the extension
  2. lowercase
  3. turn anything outside `a-z0-9_-` into `-`
  4. collapse runs of `-`
  5. trim `-` from both ends
  6. cap at 40 characters, then trim again

  An empty slug means no trailing `_`. The timestamp is local time.
- **Share Link = Cloudinary's `secure_url`, byte-for-byte**, except `.heic`/`.heif`, which become `.jpg`. Don't add `f_auto`, `q_auto` or other transformations.

**Menu**
- **The Last Error clears when the next Drop begins**, not when an Upload next succeeds. Otherwise a refusal in a mixed Drop would vanish before the user saw it.
- **Link History is in memory only**, newest first, max 10. Each label is `truncateMiddle(filename, 30) · HH:mm` with the URL as a tooltip. Clicking copies the link and does **not** open it.
- **Quit is immediate**, with no confirmation while uploads are running.
- **No notifications and no sounds.** Feedback is the icon only.

**Setup**
- **Launch at Login** is registered once on first launch, tracked by the `didApplyDefaultLoginItem` UserDefaults flag, and toggled from the menu.
- **Credentials** are read lazily from the Keychain on first use and cached in `StatusController`. The settings window updates the cache when it saves.

## The Cloudinary API: what matters

**Signed upload**
- Endpoint: `POST https://api.cloudinary.com/v1_1/<cloud>/<image|video>/upload`, multipart. The resource type is explicit, not `auto`.
- Signed params: `asset_folder`, `public_id` and `timestamp`. The signature is SHA-1 of the sorted `k=v` pairs joined by `&`, followed by the secret. `api_key`, `signature` and `file` are **not** signed. The signing test includes the example from Cloudinary's docs.
- **The account uses dynamic folder mode.** The legacy `folder` param would only set the console folder, not the URL path. So we send **both**:
  - `asset_folder=clouddrop` for the console folder
  - `public_id=clouddrop/…` for the URL path

  Don't switch to `folder`.

**Timeouts**
- `timeoutIntervalForRequest = 60`, an idle/stall timeout.
- `timeoutIntervalForResource = 24h`. A 100 MB video on slow Wi-Fi can take minutes, so don't add an overall deadline.

**Memory**
- The multipart body is **streamed to a temp file** in 1 MB chunks, then sent with `session.upload(for:fromFile:delegate:)`.
- Each chunk is copied inside `autoreleasepool`. Without it every chunk stays alive until the upload finishes: a 75 MB video peaked at about 80 MB before this fix and about 17 MB after. Never load a whole file into `Data`.
- Progress comes from a per-task `URLSessionTaskDelegate` (`didSendBodyData`) and is hopped to the main actor.

**Checking credentials: `Uploader.verify`**
1. `GET /ping` with Basic auth. This proves the key and secret are valid, but **not** that the key may upload.
2. A signed `POST /image/upload` with **no file**:
   - a key that can upload gets `400 "Missing required parameter - file"`
   - a key without upload permission gets `403`
   - nothing is created either way

   This step exists because the user once pasted a restricted key: it passed the ping, then every upload failed with `403 … missing permissions (actions=["create"])`.

**Errors**
- `UploadError.cloudinary(message)` carries Cloudinary's `error.message`, plus `(HTTP n)`.
- A 403 during upload is mapped to a readable "isn't allowed to upload" message.

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
- They cover: parsing the Cloudinary URL, slug and public_id rules, signing (including Cloudinary's documented example), media kind detection, Size Limit boundaries and messages, the HEIC link, and menu truncation.

**App target**
- It has no unit tests. After touching `StatusController`, `UploadQueue`, the settings window, the Keychain or the login item, go through the **manual checklist in README.md**. If you can't run it (you can't drag files in a GUI), say so plainly and list which items the user needs to check.

**Live checks against Cloudinary**
- These are allowed, carefully. The account is the user's real one.
- Build a throwaway harness **outside the repo**, in a scratch or temp directory:
  ```sh
  swiftc -O Sources/CloudDropCore/*.swift harness/main.swift -o harness/e2e
  ```
  Here `main.swift` calls `Uploader` directly and reads credentials from an environment variable.
- To get credentials without printing them, extract `CLOUDINARY_URL` from `~/.zshrc` with `grep` into a shell variable. Never `echo` it, and never read the app's Keychain item: that would prompt the user.
- Upload only tiny generated files. **Delete every test asset afterwards** with the Admin API, `DELETE /v1_1/<cloud>/resources/<type>/upload?public_ids[]=…`.
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
- **The Keychain prompt** only appears after a rebuild, not on first save, because the app that created the item is trusted automatically.
- **Browser drags** aren't officially supported (ADR 0004). If a browser offers a file promise, it may still upload. This is known and accepted; don't add special handling unless the user asks.
- **The notch:** on the MacBook Pro, menu bar items that don't fit are hidden behind the notch. This is an accepted risk; there's no fallback trigger by design.
- **SMAppService** works best when the app lives in `/Applications`, which is why `make install` copies it there.

## Out of scope (ADR 0004)

Don't add any of these unless the user explicitly asks, and then revisit ADR 0004:
- deleting or renaming uploads
- Cloudinary transformations (beyond HEIC → JPG)
- other cloud services
- persistent Link History
- clipboard images, browser-drag support, non-media files
- auto-update
- a Dock icon
- retries
- a quit confirmation
- notifications and sounds
- a settings UI beyond the one field

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
