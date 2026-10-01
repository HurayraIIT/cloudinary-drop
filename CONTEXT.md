# CloudDrop

A personal macOS menu bar app that turns images and videos dropped on its icon into public Cloudinary links. Single user, single Cloudinary account, never distributed.

## Language

### Dropping and uploading

**Drop**:
One drag-and-drop gesture onto the menu bar icon, carrying one or more files.
_Avoid_: Drag, import, batch

**Media File**:
A file in a Drop that is an image or a video and fits the account's Size Limit. Anything else in a Drop is refused.
_Avoid_: Asset, attachment, item

**Size Limit**:
The largest file the Cloudinary account accepts: one limit for images and a larger one for videos.
_Avoid_: Quota, max size

**Upload**:
Sending one Media File to Cloudinary.
_Avoid_: Sync, push

**Upload Queue**:
The Media Files waiting to be uploaded, sent one at a time in the order they were dropped. A new Drop joins the end of the queue, and a failed Upload does not stop the ones after it.
_Avoid_: Batch, job list

**Share Link**:
The short public URL of an uploaded Media File, pointing to the original file byte-for-byte, except that a HEIC image's Share Link delivers it as JPEG so any browser can show it. It uses a random name that never reveals the original filename, and never changes what it points to. After each successful Upload it is opened in the default browser and placed on the clipboard, so the clipboard holds the latest one.
_Avoid_: URL, public link, delivery URL

### What the menu shows

**Link History**:
The ten most recent Uploads in the account, from either Mac, newest first, each labelled by original filename, the size of the Media File as dropped, and upload time. It is read from Cloudinary, so every Mac shows the same list. Choosing one copies its Share Link again without opening it.
_Avoid_: Recents, log

**Delete**:
Permanently removing an uploaded Media File from Cloudinary, chosen from its Link History entry after a confirmation. Its Share Link stops working within minutes, and it cannot be undone.
_Avoid_: Remove, destroy, trash

**Last Error**:
The most recent failure message (a refused file, a failed Upload or a failed Delete), shown in the menu. It clears when the next Drop or Delete begins.
_Avoid_: Error log

### Setup

**Cloudinary URL**:
The single `cloudinary://key:secret@cloud` credential that identifies the account. It is entered once per Mac.
_Avoid_: API key, credentials, config
