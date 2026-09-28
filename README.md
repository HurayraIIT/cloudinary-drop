# CloudDrop

A tiny macOS menu bar app for personal use. Drop an image or video on its icon and it uploads to Cloudinary, opens the public link in your browser and copies it to the clipboard.

Vocabulary is in [CONTEXT.md](CONTEXT.md), and decisions are in [docs/adr/](docs/adr/).

## Install (on each Mac)

Needs macOS 26 and Command Line Tools (`xcode-select --install`). Xcode is not required.

```sh
git clone git@github.com:HurayraIIT/cloudinary-drop.git
cd cloudinary-drop
make install      # builds build/CloudDrop.app, copies it to /Applications and launches it
```

On first launch:
1. Click the cloud icon, choose **Set Cloudinary URL…**, paste `cloudinary://key:secret@cloud` and press Save. The URL is checked with Cloudinary and stored in the Keychain.
2. No Keychain prompt appears at first, because CloudDrop created the Keychain item itself. After a rebuild (`make install`), the next Drop makes macOS ask whether CloudDrop may use the item, because builds are signed ad-hoc (ADR 0002). Choose **Always Allow**.

Launch at Login is on by default and can be toggled in the menu.

## Develop

Failures are logged. To watch them:

```sh
log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
```

```sh
make test    # Swift Testing via Command Line Tools; fails if no tests ran
make app     # builds build/CloudDrop.app without installing
make uninstall
```

## What it does

| | |
|---|---|
| Accepts | Image and video files from Finder or the screenshot thumbnail |
| Refuses | Anything else, images over 10 MB, videos over 100 MB |
| Uploads | One at a time. New Drops join the queue, and a failure doesn't stop the rest |
| Names | `clouddrop/260928_141503_k3f9_screenshot.png` |
| Share Link | The original file. HEIC is delivered as `.jpg` |
| Icon | ☁︎ idle · `↑ 42%` uploading · ✓ / ✗ for 2 seconds |
| Menu | Last Error · the last 10 Share Links (click to copy) · Set Cloudinary URL… · Launch at Login · Quit |

## Manual test checklist

Drag-and-drop, Keychain and the menu aren't covered by `make test`. After changing them, check:

- [ ] Before any URL is saved, a Drop shows "Set Cloudinary URL first", flashes ✗ and opens the settings window.
- [ ] A wrong secret in settings shows "Cloudinary rejected the API key or secret" and saves nothing.
- [ ] ⌘V pastes into the settings field.
- [ ] Dragging a PNG over the icon highlights it. Dragging only a PDF does not.
- [ ] Dropping a PNG shows `↑ n%`, then ✓. The link opens in the browser and is on the clipboard.
- [ ] Dropping the floating screenshot thumbnail works like a PNG.
- [ ] A HEIC photo's link ends in `.jpg` and displays in Chrome.
- [ ] A screen recording (`.mov`, 10–100 MB) uploads and plays in the browser.
- [ ] Dropping 3 images uploads them in order, opens 3 tabs, and the clipboard holds the last link.
- [ ] Dropping a PDF together with a PNG uploads the PNG. The menu still shows the PDF's Last Error until the next Drop.
- [ ] A 12 MB image or a 150 MB video is refused with its size and the limit.
- [ ] Link History shows the newest first, at most 10, with long names shortened in the middle. Hovering shows the URL, and clicking copies without opening.
- [ ] Turning Wi-Fi off mid-upload ends with ✗ and a network error, and the next queued file is still tried.
- [ ] Launch at Login toggles and survives a restart.
