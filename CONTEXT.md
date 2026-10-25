# CloudDrop

A personal macOS menu bar app that turns images and videos dropped on its icon into public Cloudinary links. Single user, single Cloudinary account, never distributed.

## Language

### Dropping and uploading

**Drop**:
One drag-and-drop gesture onto the menu bar icon, carrying one or more files.
_Avoid_: Drag, import, batch

**Media File**:
A file in a Drop that is an image or a video and fits the account's Size Limit once it's ready to upload, which for a video means after any Compression. Anything else in a Drop is refused.
_Avoid_: Asset, attachment, item

**Capture**:
A screenshot or screen recording dropped straight from its floating thumbnail, before macOS has saved it anywhere, so CloudDrop holds the only copy. A Capture that isn't uploaded is saved to Downloads instead of being lost.
_Avoid_: Temporary file, floating thumbnail, screen grab

**Size Limit**:
The largest file the Cloudinary account accepts: one limit for images and a larger one for videos.
_Avoid_: Quota, max size

**Compression**:
Re-encoding a video on the Mac, before its Upload, into a smaller MP4 that any browser can play. It's on by default, can be turned off, and is unavailable while ffmpeg isn't installed. Images are never compressed, and the original file is never changed.
_Avoid_: Transcoding, optimising, shrinking

**Quality Level**:
How much sharpness Compression may give up for a smaller file, chosen from three levels in the menu. A video whose compressed file is still over the Size Limit is refused, not compressed again at a lower level.
_Avoid_: CRF, preset

**Upload**:
Sending one Media File to Cloudinary.
_Avoid_: Sync, push

**Upload Queue**:
The Media Files waiting to be uploaded, sent one at a time in the order they were dropped. A new Drop joins the end of the queue, and a failed Upload does not stop the ones after it.
_Avoid_: Batch, job list

**Share Link**:
The short public URL of an uploaded Media File, pointing to exactly what was uploaded: the original file, or for a compressed video its MP4. A HEIC image's Share Link delivers it as JPEG so any browser can show it. It uses a random name that never reveals the original filename, and never changes what it points to. After each successful Upload it is placed on the clipboard, so the clipboard holds the latest one, and opened in the default browser unless that's turned off on this Mac.
_Avoid_: URL, public link, delivery URL

### What the menu shows

**Link History**:
The fifty most recent Uploads in the account, from either Mac, newest first, each labelled by filename (ending in `.mp4` for a compressed video, to match its Share Link), the size of what was uploaded, and upload time. It is read from Cloudinary, so every Mac shows the same list. Choosing one copies its Share Link again without opening it.
_Avoid_: Recents, log

**Delete**:
Permanently removing an uploaded Media File from Cloudinary, chosen from its Link History entry after a confirmation. Its Share Link stops working within minutes, and it cannot be undone.
_Avoid_: Remove, destroy, trash

**Usage**:
The whole account's image and video counts, its stored bytes, and the share of the monthly credit allowance used, as Cloudinary reports them. It covers every file in the account, not only CloudDrop's Uploads. The Free plan has no storage limit of its own, so the credit share is the only measure of what's left.
_Avoid_: Quota, stats, storage, account info

**Last Error**:
The most recent failure message (a refused file, a failed Upload or Delete, Captures saved to Downloads, or a Cloudinary URL that couldn't be read), shown in the menu. It clears when the next Drop or Delete begins.
_Avoid_: Error log

### Setup

**Cloudinary URL**:
The single `cloudinary://key:secret@cloud` credential that identifies the account. It is entered once per Mac.
_Avoid_: API key, credentials, config
