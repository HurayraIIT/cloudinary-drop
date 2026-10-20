# CloudDrop

A tiny macOS menu bar app: **drop an image or video on the cloud icon and get a public Cloudinary link.** The link opens in your browser and is copied to your clipboard.

It's built for one person, one Cloudinary account and two Macs. It isn't distributed or notarized, and it will never be on the App Store.

- Native Swift + AppKit, about 540 KB installed, about 16 MB of memory when idle ([resource use](#resource-use))
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
>
> It also checks that the key may **list** uploads (Cloudinary's Search API), which the menu's recent links need, and that it may **delete** them. A key that can upload but not list or delete is still saved, with a warning. Without listing, the menu only shows what this Mac uploaded; without deleting, the trash button fails.

### 2. Paste it into CloudDrop

1. Click the cloud icon and choose **Set Cloudinary URL…** (⌘,).
2. Paste the URL. A whole shell line such as `export CLOUDINARY_URL="cloudinary://…"` is fine too.
3. Press **Save**. CloudDrop checks the URL with Cloudinary (without creating anything) and stores it in your login Keychain.

You only do this once per Mac.

### 3. Launch at Login

It's on by default. Toggle it from the menu.

## Using it

**Drag image or video files onto the cloud icon.** Files from Finder, file promises (Photos, Mail), and floating screenshot or screen recording thumbnails ([Captures](#limits-and-naming)) all work.

For each file:
1. The icon shows upload progress: `↑ 42%`.
2. The **Share Link** opens in your default browser and is copied to the clipboard.
3. The icon shows ✓ for 2 seconds, or ✗ if something went wrong.

Drop several files and they upload **one at a time, in order**. Each one opens its own browser tab, so the clipboard ends up holding the **last** link. Dropping more files while an upload is running adds them to the end of the queue. If one file fails, the rest still upload.

### The menu

Click the icon to see:

| Item | What it does |
|---|---|
| ⚠︎ *error* | The last problem from your most recent Drop or Delete, or Captures saved to Downloads at launch. Hover for the full text. It clears when you drop or delete something new |
| Recent links | The 10 newest uploads in your Cloudinary account's `clouddrop` folder, **from either Mac**, newest first. Each row shows a thumbnail (a film icon for videos), the filename, then the file size (`850 KB`, `4.2 MB`, `87 MB`, as dropped) and the time (`02:34 PM` today, then `Yesterday`, `Mon`, `12 Sep`) in right-aligned columns, and three buttons: **Copy**, **Open in Browser** and **Delete** (trash). Clicking the row also copies, and the icon flashes ✓. Hover for the URL, the full date and the size. The list refreshes in the background each time you open the menu (at most every 30 seconds), and your own uploads appear immediately |
| Couldn't refresh Link History | The last refresh failed, for example because you're offline, and the list may be out of date. Hover for the reason |
| Link History paused until 03:00 PM | Cloudinary's hourly API limit (500 calls, shared by both Macs) was reached. Refreshes resume at that time; uploads aren't affected |
| `1,210 images · 26 videos · 636 MB · 12% of credits` | Your **whole account's** Usage, not just CloudDrop's uploads: how many images and videos it holds, how much storage they use (`1.3 GB` from 1000 MB up), and how much of the month's 25 credits are used. The Free plan has no storage limit of its own; storage, bandwidth and transformations all spend the same credits, so the percentage is what's left. Cloudinary updates storage and credits once a day. Hidden until the first fetch works, or if the key can't read it |
| Set Cloudinary URL… | Paste or replace the Cloudinary URL |
| Launch at Login | Start CloudDrop when you log in |
| Quit CloudDrop | Quits immediately. Any running uploads stop, and unfinished Captures are saved to Downloads |

### Icon states

| Icon | Meaning |
|---|---|
| ☁︎ (cloud with arrow) | Idle, ready for a Drop |
| Highlighted | You're dragging at least one image or video over it |
| ↑ `42%` | Uploading; the percentage is for the current file |
| ✓ | An upload finished and its link is on the clipboard, a link was copied, or a Delete finished |
| ✗ | Something was refused or failed, or unfinished Captures were saved to Downloads at launch; open the menu to see why |

## Limits and naming

**What gets uploaded:**

| | |
|---|---|
| Accepted | Images (PNG, JPEG, HEIC, GIF, WebP, …) and videos (MOV, MP4, …) |
| Refused | Everything else (PDFs, zips, folders), and files whose size can't be read |
| Not supported | Dragging from a browser. It may work when the browser hands over a real file, but it isn't guaranteed |
| Size limits | Images up to **10 MB**, videos up to **100 MB** (Cloudinary Free plan). Larger files are refused before uploading, with the size shown |
| Captures | A screenshot or recording dropped straight from its floating thumbnail exists nowhere else. If it isn't uploaded (refused, failed, no Cloudinary URL yet, or CloudDrop quit first), it's saved to your **Downloads** folder as `cd-<name>`, and the menu says so. Other files are never moved or deleted |

Files dragged from apps such as Photos or Mail arrive as file promises into their own temporary folders and are deleted after uploading; because the original still exists in the source app, they are not saved to Downloads if refused or failed. Files dragged from Finder or other folders are never moved or deleted.

**Where files end up:** each file gets a random 8-character name in the `d/` folder, so links are short and never reveal the original filename:

```
Screenshot 2026-09-29 at 12.31.45.png
→ https://res.cloudinary.com/<cloud>/d/k3f9x2ab.png

Screen Recording 2026-09-28 at 14.15.03.mov
→ https://res.cloudinary.com/<cloud>/video/upload/d/k3f9x2ab.mov
```

- Video links keep `/video/upload/`, because Cloudinary only allows the shorter form for images.
- In the Cloudinary console, the files sit in the `clouddrop` folder and show their original filename.
- The random name makes links hard to guess. CloudDrop never replaces an existing file. If a name is somehow already taken, that Upload fails with "Its random name was already taken, drop it again", and the old link keeps its file.
- Links made before this change (`…/clouddrop/260928_…`) keep working.

**What the link points to:** exactly the file that was uploaded. That's the original file, byte for byte, with two exceptions. A **compressed video** links to its compressed `.mp4`. **HEIC photos** get a `.jpg` link so they display in every browser; Cloudinary converts them when the link is first opened.

### Deleting an upload

Uploaded the wrong file? Click the **trash** button on its row in the menu. An alert names the file; choose **Delete** to remove it from Cloudinary for good. Its Share Link stops working within a minute or so, and the row disappears. Cancel is the default button, so Return never deletes.

- Any of the 10 recent links can be deleted, whichever Mac uploaded it.
- There's no undo: the Free plan keeps no backups.
- The clipboard is left alone, even if it still holds the deleted link.
- If the file was already deleted (on the other Mac, or in the console), it counts as done.

To rename files, or delete older ones, use the Cloudinary console.

## Updating and uninstalling

**Update:**

```sh
cd cloudinary-drop
git pull
make install
```

After each rebuild, macOS asks whether CloudDrop may use its Keychain item as soon as the new build launches, because it loads the recent links straight away. Choose **Always Allow**. This happens because local builds are signed ad-hoc, so each build looks like a new app to macOS (see [ADR 0002](docs/adr/0002-cloudinary-url-in-keychain.md)).

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

**An upload from the other Mac isn't in the menu yet.**
The list refreshes when you open the menu, but not more than once every 30 seconds, and Cloudinary can take a few seconds to list a new upload. Close the menu and open it again a little later. If the menu says "Couldn't refresh Link History", hover over that line to see why.

**The menu says "Couldn't read the Cloudinary URL from the Keychain".**
You chose **Deny** on the Keychain prompt, or it was dismissed. Your URL is still saved. Drop a file to be asked again, and choose **Always Allow**.

**No Keychain prompt appeared.**
That's expected. The prompt only appears after a rebuild.

**See exactly what happened:**

```sh
log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
```

This logs every upload, refusal and failure, including Cloudinary's error message. Secrets are never logged.

## Resource use

Measured on an M4 MacBook Pro running macOS 26.6.2 (2026-09-30):

| | |
|---|---|
| App size | 544 KB (a 546 KB binary; the Swift runtime ships with macOS) |
| Memory, idle | about 16 MB after launch, including the first Link History fetch; about 30 MB after some use (opening the menu with its thumbnails, an upload) |
| CPU, idle | 0.0%, with about 5 threads and no timers or polling; about 0.03 s of CPU a minute and 10–16 idle wakeups a minute |
| Energy, idle | 0.0 in `top`'s power column, so it doesn't keep the Mac awake |
| Network, idle | none. At launch, one search for the Link History and three calls for the Usage line. After that, only when you open the menu: at most one Link History search every 30 seconds, the two Usage counts at most every 5 minutes (sooner after an upload or Delete), and the Usage storage and credits at most hourly. Each thumbnail is about 1 KB. A Delete is one request, and doesn't count toward the hourly limit |
| Upload of a 75 MB video | about 1 second of CPU in total, peak memory about 17 MB (measured 2026-09-28) |

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
                   signing, size limits, Share Links, the upload request,
                   the Link History search, Deletes, Usage, temporary file and Capture handling
  CloudDrop/       The AppKit app: menu bar icon and drops, Upload Queue,
                   Link History, Usage line, menu, settings window, Keychain, Launch at Login
Tests/             Swift Testing unit tests for CloudDropCore
Resources/         Info.plist (menu-bar-only, bundle id com.hurayraiit.clouddrop)
CONTEXT.md         Glossary: Drop, Media File, Capture, Size Limit, Upload, Share Link, …
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
  - 0005: short Share Links
  - 0006: recent links fetched from Cloudinary
  - 0007: deleting from the recent links

  Read these before adding features.

## Manual test checklist

Drag-and-drop, the Keychain and the menu aren't covered by `make test`. After changing them, check:

- [ ] Before any URL is saved, a Drop shows "Set Cloudinary URL first", flashes ✗ and opens the settings window.
- [ ] Before any URL is saved, dropping a Capture preserves it to Downloads as `cd-<name>`.
- [ ] A wrong secret in settings shows "Cloudinary rejected the API key or secret" and saves nothing.
- [ ] A read-only API key is refused at Save with "isn't allowed to upload".
- [ ] ⌘V pastes into the settings field.
- [ ] Dragging a PNG over the icon highlights it. Dragging only a PDF does not.
- [ ] Dropping a PNG shows `↑ n%`, then ✓. The link opens in the browser and is on the clipboard.
- [ ] An image link looks like `…/<cloud>/d/k3f9x2ab.png` and a video link like `…/<cloud>/video/upload/d/k3f9x2ab.mov`, with no `v…` version.
- [ ] In the Cloudinary console, a new upload is in the `clouddrop` folder and shows its original filename.
- [ ] Dropping the floating screenshot thumbnail works like a PNG.
- [ ] A HEIC photo's link ends in `.jpg` and displays in Chrome.
- [ ] A screen recording (`.mov`, 10–100 MB) uploads and plays in the browser.
- [ ] Dropping 3 images uploads them in order, opens 3 tabs, and the clipboard holds the last link.
- [ ] Dropping a PDF together with a PNG uploads the PNG. The menu still shows the PDF's error until the next Drop.
- [ ] A 12 MB image or a 150 MB video is refused with its size and the limit.
- [ ] A recording dropped from its floating thumbnail uploads, and nothing is left in Downloads.
- [ ] A refused one (e.g. over 100 MB) is saved as `~/Downloads/cd-<name>`, and the ⚠︎ line ends with "Saved to Downloads."
- [ ] Quitting while a recording dropped from its floating thumbnail is uploading saves it to Downloads, and the next launch flashes ✗ and shows "Saved 1 unfinished Capture to Downloads".
- [ ] After a rebuild, choosing **Deny** on the Keychain prompt shows "Couldn't read the Cloudinary URL from the Keychain" without opening settings. Clicking the icon again doesn't bring the prompt back. The next Drop asks again, and **Always Allow** uploads it and fills in the recent links.
- [ ] Pressing Return twice quickly in the settings window checks the URL only once.
- [ ] An image dragged from `/tmp` in Finder uploads and is still in `/tmp` afterwards.
- [ ] Recent links show the newest first, at most 10, with long names shortened in the middle. Hovering shows the URL, the full date and the size.
- [ ] Sizes and times line up in two right-aligned grey columns on every row, including a mix of `Yesterday` and `02:34 PM`. A screenshot name like `SCR-20261001-kywz.png` fits without shortening.
- [ ] Right after launch, the first click shows the account's recent links, including ones older than this launch, with `Yesterday`/weekday/date labels.
- [ ] A file uploaded on the **other Mac** appears here the next time the menu is opened (after at most 30 seconds), with a thumbnail if it's an image.
- [ ] Your own new upload appears at the top immediately and doesn't disappear and reappear a few seconds later.
- [ ] With the menu open while a refresh finishes, the rows update in place without jumping more than needed, and the highlight stays on the same entry.
- [ ] With Wi-Fi off, opening the menu keeps the old list and shows "Couldn't refresh Link History", with the reason on hover. Turning Wi-Fi back on clears it at the next refresh.
- [ ] Saving a key that can upload but not list or delete shows the warning and keeps the window open.
- [ ] Each image row has a rounded square thumbnail, and each video row a film icon.
- [ ] Hovering a row or moving with the arrow keys highlights it. Return copies the highlighted row.
- [ ] Clicking a row or its Copy button copies without opening, closes the menu and flashes ✓. The Open button opens the link and closes the menu.
- [ ] Each row has a trash button after Open, with a slightly wider gap. It's grey normally and white on the highlighted row, and the filename shortens to make room.
- [ ] Clicking trash closes the menu and shows an alert naming the file, with its thumbnail (or a film icon), a red **Delete** and a default **Cancel**. Return cancels. Esc cancels or does nothing, but never deletes.
- [ ] Cancel leaves everything as it was.
- [ ] Delete flashes ✓, the row is gone from the menu straight away and stays gone across the next few menu opens, and the Share Link 404s within a minute or so. The clipboard is unchanged.
- [ ] Deleting a video row works the same way.
- [ ] Deleting a row the other Mac already deleted still flashes ✓ and removes the row.
- [ ] With Wi-Fi off, Delete flashes ✗ and the menu shows "Couldn't delete <file>: …", and the row stays. The next Drop or Delete clears that line.
- [ ] Right after launch, the first click shows a line like `1,210 images · 26 videos · 636 MB · 12% of credits` under a separator below the recent links, matching the Cloudinary console's totals. It's as bright and as large as the filenames, lines up with "Set Cloudinary URL…", has no separator between it and "Set Cloudinary URL…", never highlights, and has no tooltip.
- [ ] After an upload, the image or video count goes up by one at the next menu open after about 15 seconds. After a Delete, it goes down.
- [ ] With the menu open when the Usage line first arrives, it appears in place and the highlight stays on the same row.
- [ ] With Wi-Fi off, the Usage line keeps its last values and shows no error.
- [ ] Deleting while a queue of uploads is running doesn't stop or reorder the uploads.
- [ ] Turning Wi-Fi off mid-upload ends with ✗ and a network error, and the next queued file is still tried.
- [ ] Launch at Login toggles and survives a restart.
