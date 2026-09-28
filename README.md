# CloudDrop

A tiny macOS menu bar app: **drop an image or video on the cloud icon and get a public Cloudinary link.** The link opens in your browser and is copied to your clipboard.

It's built for one person, one Cloudinary account and two Macs. It isn't distributed or notarized, and it will never be on the App Store.

- Native Swift + AppKit, about 380 KB installed, about 12 MB of memory when idle ([resource use](#resource-use))
- No Dock icon, no windows except a one-time settings field
- Uploads go straight from your Mac to Cloudinary, with no server in between

---

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [First-time setup](#first-time-setup)
- [Using it](#using-it)
- [Limits and naming](#limits-and-naming)
- [Updating and uninstalling](#updating-and-uninstalling)
- [Troubleshooting](#troubleshooting)
- [Resource use](#resource-use)
- [Development](#development)
- [Manual test checklist](#manual-test-checklist)

---

## Requirements

| | |
|---|---|
| Mac | Apple silicon (tested on M1 and M4) |
| macOS | 26 or later |
| Tools | Command Line Tools (`xcode-select --install`). Full Xcode is **not** needed |
| Cloudinary | An account and an API key **that is allowed to upload** (see [below](#first-time-setup)) |

## Install

Do this on each Mac:

```sh
xcode-select --install        # once per Mac, skip if already installed
git clone git@github.com:HurayraIIT/cloudinary-drop.git
cd cloudinary-drop
make install
```

`make install` builds `CloudDrop.app`, signs it for local use, copies it to `/Applications` and launches it. A cloud icon appears in the menu bar.

## First-time setup

### 1. Get a Cloudinary URL with upload permission

In the Cloudinary console, open **Settings → API Keys** and pick a key. You need the **Cloudinary URL**, which looks like this:

```
cloudinary://<api_key>:<api_secret>@<cloud_name>
```

> **The key must be allowed to upload.** Cloudinary can restrict what each API key may do. A read-only key is a valid key, but every upload fails with *"missing permissions (actions=["create"])"*. CloudDrop checks for this when you save, and refuses a key that can't upload.

### 2. Paste it into CloudDrop

1. Click the cloud icon and choose **Set Cloudinary URL…** (⌘,).
2. Paste the URL. A whole shell line such as `export CLOUDINARY_URL="cloudinary://…"` is fine too.
3. Press **Save**. CloudDrop checks the URL with Cloudinary (without creating anything) and stores it in your login Keychain.

You only do this once per Mac.

### 3. Launch at Login

It's on by default. Toggle it from the menu.

## Using it

**Drag image or video files onto the cloud icon.** Files from Finder and the floating screenshot thumbnail both work.

For each file:
1. The icon shows upload progress: `↑ 42%`.
2. The **Share Link** opens in your default browser and is copied to the clipboard.
3. The icon shows ✓ for 2 seconds, or ✗ if something went wrong.

Drop several files and they upload **one at a time, in order**. Each one opens its own browser tab, so the clipboard ends up holding the **last** link. Dropping more files while an upload is running adds them to the end of the queue. If one file fails, the rest still upload.

### The menu

Click the icon to see:

| Item | What it does |
|---|---|
| ⚠︎ *error* | The last problem from your most recent Drop. Hover for the full text. It clears when you drop something new |
| Recent links | The last 10 Share Links, newest first. Each row shows a thumbnail (a film icon for videos), `filename · time`, and two buttons: **Copy** and **Open in Browser**. Clicking the row also copies, and the icon flashes ✓. Hover for the URL. The list is lost when the app quits |
| Set Cloudinary URL… | Paste or replace the Cloudinary URL |
| Launch at Login | Start CloudDrop when you log in |
| Quit CloudDrop | Quits immediately. Any unfinished uploads are dropped |

### Icon states

| Icon | Meaning |
|---|---|
| ☁︎ (cloud with arrow) | Idle, ready for a Drop |
| Highlighted | You're dragging at least one image or video over it |
| ↑ `42%` | Uploading; the percentage is for the current file |
| ✓ | An upload finished, and its link is on the clipboard |
| ✗ | Something was refused or failed; open the menu to see why |

## Limits and naming

**What gets uploaded:**

| | |
|---|---|
| Accepted | Images (PNG, JPEG, HEIC, GIF, WebP, …) and videos (MOV, MP4, …) |
| Refused | Everything else (PDFs, zips, folders), and files whose size can't be read |
| Not supported | Dragging from a browser. It may work when the browser hands over a real file, but it isn't guaranteed |
| Size limits | Images up to **10 MB**, videos up to **100 MB** (Cloudinary Free plan). Larger files are refused before uploading, with the size shown |

**Where files end up:** in the `clouddrop` folder of your Cloudinary account, named with a timestamp, a random suffix and the original filename:

```
Screen Recording 2026-09-28 at 14.15.03.mov
→ https://res.cloudinary.com/<cloud>/video/upload/v…/clouddrop/260928_141503_k3f9_screen-recording-2026-09-28-at-14-15-03.mov
```

- The random suffix makes links hard to guess and stops two uploads with the same filename from colliding.
- Filenames are lowercased, and anything other than `a–z 0–9 _ -` becomes `-`. The name part is capped at 40 characters.

**What the link points to:** the Share Link is the original file, byte for byte. The one exception is **HEIC photos**, which get a `.jpg` link so they display in every browser. Cloudinary converts them when the link is first opened.

CloudDrop only uploads. To delete or rename files, use the Cloudinary console.

## Updating and uninstalling

**Update:**

```sh
cd cloudinary-drop
git pull
make install
```

After each rebuild, your next Drop makes macOS ask whether CloudDrop may use its Keychain item. Choose **Always Allow**. This happens because local builds are signed ad-hoc, so each build looks like a new app to macOS (see [ADR 0002](docs/adr/0002-cloudinary-url-in-keychain.md)).

**Uninstall:**

1. Turn off **Launch at Login** in the menu.
2. Remove the app:
   ```sh
   make uninstall
   ```
3. Optionally, remove the saved Cloudinary URL:
   ```sh
   security delete-generic-password -s com.hurayraiit.clouddrop
   ```

## Troubleshooting

**Every upload fails with "isn't allowed to upload" or "missing permissions (actions=["create"])".**
The API key can't create assets. Use a key with upload permission ([step 1](#1-get-a-cloudinary-url-with-upload-permission)).

**Saving the URL fails with "rejected the API key or secret".**
The key or secret is wrong, or it has been revoked. Copy the Cloudinary URL again from the console.

**Nothing happens when I drop, or the icon doesn't highlight.**
- Only images and videos highlight the icon.
- Browser drags aren't supported. Save the image first, then drop the file.
- If the icon isn't visible at all, it may be hidden behind the notch on a MacBook Pro. ⌘-drag it further left, or free up space in the menu bar.

**A file was refused as too large.**
Images must be 10 MB or less and videos 100 MB or less. Compress the file first.

**No Keychain prompt appeared.**
That's expected. The prompt only appears after a rebuild.

**See exactly what happened:**

```sh
log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
```

This logs every upload, refusal and failure, including Cloudinary's error message. Secrets are never logged.

## Resource use

Measured on an M4 MacBook Pro running macOS 26.6 (2026-09-28):

| | |
|---|---|
| App size | 384 KB (a 381 KB binary; the Swift runtime ships with macOS) |
| Memory, idle | about 12 MB after launch, about 19 MB after opening the menu and settings window |
| CPU, idle | 0.0%, with about 3 threads and no timers or polling |
| Energy, idle | 0.0 in `top`'s power column, so it doesn't keep the Mac awake |
| Upload of a 75 MB video | about 1 second of CPU in total, peak memory about 17 MB |

The file is streamed from disk in 1 MB pieces, so memory doesn't grow with file size. Upload time depends on your connection: 75 MB took about 70 seconds over Wi-Fi.

## Development

```sh
make test       # unit tests (Swift Testing); fails if the tests fail or if none ran
make app        # build build/CloudDrop.app without installing
make install    # build, copy to /Applications, relaunch
make clean
```

**Testing without Xcode:**
- XCTest isn't available with only Command Line Tools, so the tests use Swift Testing.
- SwiftPM needs extra flags to find Swift Testing, and without them `swift test` quietly runs **zero** tests and still reports success. `make test` passes the flags and checks that tests actually ran. Always use it instead of plain `swift test`.

**Layout:**

```
Sources/
  CloudDropCore/   Pure logic, unit-tested: Cloudinary URL parsing, naming,
                   signing, size limits, Share Links, the upload request
  CloudDrop/       The AppKit app: menu bar icon and drops, Upload Queue,
                   menu, settings window, Keychain, Launch at Login
Tests/             Swift Testing unit tests for CloudDropCore
Resources/         Info.plist (menu-bar-only, bundle id com.hurayraiit.clouddrop)
CONTEXT.md         Glossary: Drop, Media File, Upload, Share Link, …
docs/adr/          Architecture decisions and what's deliberately out of scope
```

**Working on it with an AI agent?** Point it at [AGENTS.md](AGENTS.md), which covers invariants, gotchas, Cloudinary API details and testing rules.

**Design docs:**
- The words used in the code and UI are defined in [CONTEXT.md](CONTEXT.md).
- Why things are the way they are is recorded in [docs/adr/](docs/adr/):
  - 0001: native AppKit over SwiftUI, Tauri or Xcode
  - 0002: Cloudinary URL in the Keychain
  - 0003: direct signed uploads
  - 0004: what's out of scope

  Read these before adding features.

## Manual test checklist

Drag-and-drop, the Keychain and the menu aren't covered by `make test`. After changing them, check:

- [ ] Before any URL is saved, a Drop shows "Set Cloudinary URL first", flashes ✗ and opens the settings window.
- [ ] A wrong secret in settings shows "Cloudinary rejected the API key or secret" and saves nothing.
- [ ] A read-only API key is refused at Save with "isn't allowed to upload".
- [ ] ⌘V pastes into the settings field.
- [ ] Dragging a PNG over the icon highlights it. Dragging only a PDF does not.
- [ ] Dropping a PNG shows `↑ n%`, then ✓. The link opens in the browser and is on the clipboard.
- [ ] Dropping the floating screenshot thumbnail works like a PNG.
- [ ] A HEIC photo's link ends in `.jpg` and displays in Chrome.
- [ ] A screen recording (`.mov`, 10–100 MB) uploads and plays in the browser.
- [ ] Dropping 3 images uploads them in order, opens 3 tabs, and the clipboard holds the last link.
- [ ] Dropping a PDF together with a PNG uploads the PNG. The menu still shows the PDF's error until the next Drop.
- [ ] A 12 MB image or a 150 MB video is refused with its size and the limit.
- [ ] Recent links show the newest first, at most 10, with long names shortened in the middle. Hovering shows the URL.
- [ ] Each image row has a rounded square thumbnail, and each video row a film icon.
- [ ] Hovering a row or moving with the arrow keys highlights it. Return copies the highlighted row.
- [ ] Clicking a row or its Copy button copies without opening, closes the menu and flashes ✓. The Open button opens the link and closes the menu.
- [ ] Turning Wi-Fi off mid-upload ends with ✗ and a network error, and the next queued file is still tried.
- [ ] Launch at Login toggles and survives a restart.
